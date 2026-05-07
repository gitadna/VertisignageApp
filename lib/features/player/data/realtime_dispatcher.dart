import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/config/environment_config.dart';
import '../../../core/logging/kiosk_log.dart';
import '../../../core/websocket/realtime_client.dart';
import '../../../core/websocket/realtime_command.dart';
import '../../../services/device_service.dart';
import '../../../services/token_store.dart';
import 'announcement_overlay_notifier.dart';
import 'emergency_overlay_notifier.dart';
import 'kiosk_fleet_api.dart';
import 'media_cache_service.dart';
import 'ota_update_service.dart';
import 'player_telemetry.dart';
import 'playlist_sync_service.dart';
import '../presentation/player_controller.dart';

/// Subscribes to [RealtimeClient.messages] once and routes typed commands (non-blocking).
class RealtimeDispatcher {
  RealtimeDispatcher({
    required RealtimeClient realtime,
    required PlaylistSyncService playlistSync,
    required EmergencyOverlayNotifier emergencyOverlay,
    required AnnouncementOverlayNotifier announcementOverlay,
    required PlayerController player,
    required TokenStore tokenStore,
    required DeviceService device,
    required EnvironmentConfig env,
    required KioskFleetApi fleetApi,
    required MediaCacheService cache,
    required OtaUpdateService ota,
    required PlayerTelemetry telemetry,
  })  : _realtime = realtime,
        _playlistSync = playlistSync,
        _emergencyOverlay = emergencyOverlay,
        _announcementOverlay = announcementOverlay,
        _player = player,
        _tokenStore = tokenStore,
        _device = device,
        _env = env,
        _fleetApi = fleetApi,
        _cache = cache,
        _ota = ota,
        _telemetry = telemetry;

  final RealtimeClient _realtime;
  final PlaylistSyncService _playlistSync;
  final EmergencyOverlayNotifier _emergencyOverlay;
  final AnnouncementOverlayNotifier _announcementOverlay;
  final PlayerController _player;
  final TokenStore _tokenStore;
  final DeviceService _device;
  final EnvironmentConfig _env;
  final KioskFleetApi _fleetApi;
  final MediaCacheService _cache;
  final OtaUpdateService _ota;
  final PlayerTelemetry _telemetry;
  DateTime? _activeOverlayCreatedAt;
  /// Latest ordering key for the active full-screen announcement (pushedAt ?? createdAt).
  DateTime? _activeAnnouncementOrderUtc;

  final LinkedHashSet<String> _recentMessageIds = LinkedHashSet<String>();

  // Subscription is held for the process lifetime; [dispose] intentionally no-ops.
  // ignore: unused_field
  StreamSubscription<RealtimeMessage>? _subscription;
  bool _started = false;

  void ensureStarted() {
    if (_started) return;
    if (!_tokenStore.hasPairedDevice) return;

    _started = true;
    _subscription = _realtime.messages.listen(
      _onMessage,
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('RealtimeDispatcher stream error: $e\n$st');
        }
      },
    );
  }

  bool _dedupe(String messageId) {
    if (_recentMessageIds.contains(messageId)) return true;
    _recentMessageIds.add(messageId);
    while (_recentMessageIds.length > 64) {
      _recentMessageIds.remove(_recentMessageIds.first);
    }
    return false;
  }

  bool _canApplyIncoming(DateTime? createdAt) {
    if (createdAt == null) return true;
    final active = _activeOverlayCreatedAt;
    if (active == null) return true;
    return !createdAt.isBefore(active);
  }

  bool _shouldApplyAnnouncement(AnnouncementCommand cmd) {
    final incoming =
        cmd.pushedAtUtc ?? cmd.createdAt ?? DateTime.now().toUtc();
    final active = _activeAnnouncementOrderUtc;
    if (active == null) return true;
    return !incoming.isBefore(active);
  }

  Future<bool> _waitForForeground({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == null || state == AppLifecycleState.resumed) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  int? _scheduleEndsEpochMs(DateTime? utc) {
    if (utc == null) return null;
    return utc.toUtc().millisecondsSinceEpoch;
  }

  Future<Map<String, dynamic>> _ensureForegroundOrUseNativeOverlay({
    required String text,
    required String? mediaUrl,
    required String? mediaKind,
    required bool untilDismissed,
    required int durationSec,
    required int? scheduleEndsAtEpochMs,
  }) async {
    final launchDispatched = await _device.wakeAppToForeground();
    final resumed = launchDispatched && await _waitForForeground();
    final lifecycle = WidgetsBinding.instance.lifecycleState?.name ?? 'unknown';
    if (resumed) {
      await _device.hideOverlay();
      return <String, dynamic>{
        'path': 'wake_foreground',
        'launchDispatched': launchDispatched,
        'lifecycleState': lifecycle,
      };
    }
    final overlayShown = await _device.showOverlay(
      text: text,
      mediaUrl: mediaUrl,
      mediaKind: mediaKind,
      untilDismissed: untilDismissed,
      durationSec: durationSec,
      scheduleEndsAtEpochMs: scheduleEndsAtEpochMs,
    );
    return <String, dynamic>{
      'path': overlayShown ? 'native_overlay_fallback' : 'wake_failed_overlay_failed',
      'launchDispatched': launchDispatched,
      'lifecycleState': lifecycle,
      'nativeOverlayShown': overlayShown,
    };
  }

  String? _resolveMediaUrl(String? rawUrl) {
    final raw = rawUrl?.trim();
    if (raw == null || raw.isEmpty) return null;
    final parsed = Uri.tryParse(raw);
    final baseRaw = _env.apiBaseUrl.trim();
    final baseNoApi = baseRaw.replaceAll(RegExp(r'/api/?$'), '');
    final base = Uri.tryParse(baseNoApi);
    if (parsed != null && (parsed.isScheme('http') || parsed.isScheme('https'))) {
      if (base != null &&
          (parsed.host == 'localhost' ||
              parsed.host == '127.0.0.1' ||
              parsed.host == '::1')) {
        return parsed.replace(
          scheme: base.scheme,
          host: base.host,
          port: base.hasPort ? base.port : null,
        ).toString();
      }
      return parsed.toString();
    }
    if (base == null || !(base.isScheme('http') || base.isScheme('https'))) {
      return null;
    }
    final rel = raw.startsWith('/') ? raw : '/$raw';
    return base.resolve(rel).toString();
  }

  AnnouncementMediaKind _inferMediaKind({
    required String? mediaUrl,
    required String? mediaKindHint,
    required String? contentTypeHint,
  }) {
    if (mediaUrl == null || mediaUrl.isEmpty) return AnnouncementMediaKind.none;
    final kind = mediaKindHint?.trim().toLowerCase();
    if (kind == 'video') return AnnouncementMediaKind.video;
    if (kind == 'image') return AnnouncementMediaKind.image;
    if (kind == 'url') return AnnouncementMediaKind.url;

    final contentType = contentTypeHint?.trim().toLowerCase();
    if (contentType != null && contentType.startsWith('video/')) {
      return AnnouncementMediaKind.video;
    }
    if (contentType != null && contentType.startsWith('image/')) {
      return AnnouncementMediaKind.image;
    }

    final lowerUrl = mediaUrl.toLowerCase();
    if (RegExp(r'\.(mp4|webm|m3u8|mov)(\?|$)').hasMatch(lowerUrl)) {
      return AnnouncementMediaKind.video;
    }
    return AnnouncementMediaKind.image;
  }

  VoidCallback _announcementDismissHandler({required bool resumePreviousPlayback}) {
    if (!resumePreviousPlayback) return _player.endAnnouncementHold;
    return () {
      _player.endAnnouncementHold();
      // Refresh right after instant content ends so prior playlist/schedule context resumes quickly.
      unawaited(_playlistSync.sync(forceCommit: true));
    };
  }

  void _onMessage(RealtimeMessage m) {
    try {
      try {
        final dynamic decoded = jsonDecode(m.payload);
        if (decoded is Map && decoded['type'] is String) {
          KioskLog.event(
            'realtime',
            decoded['type'] as String,
            level: 'debug',
          );
        }
      } catch (_) {}

      final cmd = parseRealtimeCommand(m.payload);
      if (cmd == null) return;
      unawaited(_dispatch(cmd));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('RealtimeDispatcher parse/dispatch error: $e\n$st');
      }
    }
  }

  Future<void> _dispatch(RealtimeCommand cmd) async {
    if (cmd is PingCommand) {
      await _fleetApi.postCommandAck(
        messageId: cmd.messageId,
        commandType: 'PING',
        ok: true,
        detail: <String, dynamic>{'pong': true},
      );
      return;
    }

    if (cmd is GetStatusCommand) {
      final info = await PackageInfo.fromPlatform();
      final cacheMb = await _cache.approximateCacheSizeMb();
      final detail = <String, dynamic>{
        'appVersion': info.version,
        'buildNumber': info.buildNumber,
        'syncStatus': _telemetry.syncStatus,
        'lastSuccessfulSyncUtc':
            _telemetry.lastSuccessfulSyncUtc?.toUtc().toIso8601String(),
        'currentPlaylistId': _telemetry.currentPlaylistId,
        'currentScheduleId': _telemetry.currentScheduleId,
      };
      final mb = cacheMb;
      if (mb != null) {
        detail['cacheUsedMb'] = mb;
      }
      await _fleetApi.postCommandAck(
        messageId: cmd.messageId,
        commandType: 'GET_STATUS',
        ok: true,
        detail: detail,
      );
      return;
    }

    if (cmd is ClearCacheCommand) {
      if (_dedupe(cmd.messageId)) return;
      await _cache.clearDiskCache();
      await _fleetApi.postCommandAck(
        messageId: cmd.messageId,
        commandType: 'CLEAR_CACHE',
        ok: true,
      );
      unawaited(_playlistSync.sync());
      return;
    }

    if (cmd is UpdateAppCommand) {
      if (_dedupe(cmd.messageId)) return;
      unawaited(_ota.handleUpdateApp(cmd));
      return;
    }

    if (cmd is OverlayShowCommand) {
      if (_dedupe(cmd.messageId)) return;
      if (!_canApplyIncoming(cmd.createdAt)) return;
      _activeOverlayCreatedAt = cmd.createdAt ?? DateTime.now().toUtc();
      final overlayUrl = _resolveMediaUrl(cmd.mediaUrl);
      final fallbackKind = _inferMediaKind(
        mediaUrl: overlayUrl,
        mediaKindHint: cmd.mediaKind,
        contentTypeHint: cmd.contentType,
      );
      final takeover = await _ensureForegroundOrUseNativeOverlay(
        text: cmd.text,
        mediaUrl: overlayUrl,
        mediaKind: cmd.mediaKind,
        untilDismissed: cmd.untilDismissed,
        durationSec: cmd.durationSec,
        scheduleEndsAtEpochMs: null,
      );
      _player.beginAnnouncementHold();
      _announcementOverlay.show(
        announcementId: 'overlay-fallback-${cmd.messageId}',
        durationSec: cmd.durationSec,
        untilDismissed: cmd.untilDismissed,
        mode: AnnouncementRenderMode.overlay,
        title: cmd.text,
        body: null,
        mediaKind: fallbackKind,
        mediaUrl: fallbackKind == AnnouncementMediaKind.none ? null : overlayUrl,
        onDismiss: _announcementDismissHandler(
          resumePreviousPlayback: cmd.resumePreviousPlayback,
        ),
      );
      await _fleetApi.postCommandAck(
        messageId: cmd.messageId,
        commandType: 'OVERLAY_SHOW',
        ok: true,
        detail: <String, dynamic>{
          ...takeover,
          'render': 'in_app_overlay',
        },
      );
      return;
    }

    if (cmd is OverlayHideCommand) {
      if (_dedupe(cmd.messageId)) return;
      _activeOverlayCreatedAt = null;
      _announcementOverlay.dismissManual();
      await _device.hideOverlay();
      await _fleetApi.postCommandAck(
        messageId: cmd.messageId,
        commandType: 'OVERLAY_HIDE',
        ok: true,
      );
      return;
    }

    if (cmd is PlaylistUpdatedCommand) {
      final forceCommitNow =
          cmd.forceImmediate && !_player.announcementHold.value;
      await _playlistSync.sync(forceCommit: forceCommitNow);
      return;
    }
    if (cmd is SyncRequestCommand) {
      final forceCommitNow =
          cmd.forceImmediate && !_player.announcementHold.value;
      await _playlistSync.sync(forceCommit: forceCommitNow);
      return;
    }
    if (cmd is AnnouncementCommand) {
      final dedupeKey = cmd.pushedAtUtc != null
          ? '${cmd.announcementId}|${cmd.pushedAtUtc!.millisecondsSinceEpoch}'
          : cmd.announcementId;
      if (!await _device.pushDedupeTryConsume(dedupeKey)) return;
      if (!_shouldApplyAnnouncement(cmd)) return;
      final orderUtc =
          cmd.pushedAtUtc ?? cmd.createdAt ?? DateTime.now().toUtc();
      _activeAnnouncementOrderUtc = orderUtc;
      _activeOverlayCreatedAt = cmd.createdAt ?? DateTime.now().toUtc();
      _player.beginAnnouncementHold();
      final url = _resolveMediaUrl(cmd.mediaUrl);
      final kind = _inferMediaKind(
        mediaUrl: url,
        mediaKindHint: cmd.mediaKind,
        contentTypeHint: cmd.contentType,
      );
      final renderMode = cmd.mode == 'ticker'
          ? AnnouncementRenderMode.ticker
          : AnnouncementRenderMode.overlay;

      if (renderMode == AnnouncementRenderMode.overlay) {
        final takeover = await _ensureForegroundOrUseNativeOverlay(
          text: cmd.title,
          mediaUrl: url,
          mediaKind: cmd.mediaKind,
          untilDismissed: cmd.untilDismissed,
          durationSec: cmd.durationSec,
          scheduleEndsAtEpochMs: _scheduleEndsEpochMs(cmd.scheduleEndsAtUtc),
        );
        KioskLog.event(
          'takeover',
          'announcement_takeover_path',
          level: 'info',
          detail: takeover,
        );
      }

      _announcementOverlay.show(
        announcementId: cmd.announcementId,
        durationSec: cmd.durationSec,
        untilDismissed: cmd.untilDismissed,
        mode: renderMode,
        title: cmd.title,
        body: cmd.body,
        mediaKind: kind,
        mediaUrl: url,
        presentationEndsAtUtc: cmd.scheduleEndsAtUtc,
        onDismiss: _announcementDismissHandler(
          resumePreviousPlayback: cmd.resumePreviousPlayback,
        ),
      );
      return;
    }
    if (cmd is AnnouncementTransportCommand) {
      _announcementOverlay.applyTransportCommand(
        announcementId: cmd.announcementId,
        action: cmd.action,
        volume: cmd.volume,
      );
      return;
    }
    if (cmd is AnnouncementClearCommand) {
      _activeOverlayCreatedAt = null;
      _activeAnnouncementOrderUtc = null;
      _announcementOverlay.dismissManual();
      await _device.hideOverlay();
      return;
    }

    if (cmd is EmergencyAlertCommand) {
      _emergencyOverlay.show(
        alertId: cmd.alertId,
        title: cmd.title,
        message: cmd.message,
      );
      return;
    }
    if (cmd is AlertResolvedCommand) {
      _emergencyOverlay.clear(cmd.alertId);
      return;
    }
    if (cmd is VolumeSetCommand) {
      await _device.setVolumePercent(cmd.volume);
      return;
    }
    if (cmd is MuteSetCommand) {
      await _device.setMuted(cmd.muted);
      return;
    }
    if (cmd is BrightnessSetCommand) {
      await _device.setBrightnessPercent(cmd.brightness);
      return;
    }
    if (cmd is PlaybackPauseCommand) {
      if (cmd.paused) {
        _player.requestPause();
      } else {
        _player.requestResume();
      }
      return;
    }
    if (cmd is PlaybackSkipCommand) {
      if (cmd.direction == 'previous') {
        await _player.goToPrevious();
      } else {
        await _player.goToNext();
      }
      return;
    }
    if (cmd is WakeAppCommand) {
      final launchDispatched = await _device.wakeAppToForeground();
      final resumed = launchDispatched && await _waitForForeground();
      final lifecycle = WidgetsBinding.instance.lifecycleState?.name;
      await _fleetApi.postCommandAck(
        messageId: cmd.messageId,
        commandType: 'WAKE_APP',
        ok: resumed,
        detail: <String, dynamic>{
          'reason': cmd.reason ?? 'admin_wake',
          'path': resumed ? 'wake_foreground' : 'wake_failed',
          'launchDispatched': launchDispatched,
          'lifecycleState': lifecycle ?? 'unknown',
        },
      );
      return;
    }
    if (cmd is RestartAppCommand) {
      await _device.restartApplication();
    }
  }

  /// Parses a full `{ "type", "payload" }` JSON frame (WebSocket or FCM `vs_payload`).
  Future<void> dispatchRealtimePayload(String rawJson) async {
    try {
      final cmd = parseRealtimeCommand(rawJson);
      if (cmd != null) await _dispatch(cmd);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('RealtimeDispatcher.dispatchRealtimePayload error: $e\n$st');
      }
    }
  }

  /// Routes FCM data keys when they reach Flutter (e.g. ticker, CLEAR forward, or fallback delivery).
  ///
  /// Android typically intercepts `ANNOUNCEMENT` in native code first; killed-state overlays still
  /// use Kotlin [VertiPushCommandHandler] + [OverlayWindowService].
  Future<void> dispatchFromFcmData(Map<String, dynamic> data) async {
    final vsCmd = data['vs_cmd']?.toString();
    if (vsCmd == null) return;

    try {
      if (vsCmd == 'ANNOUNCEMENT') {
        final payload = data['vs_payload']?.toString();
        if (payload != null && payload.isNotEmpty) {
          await dispatchRealtimePayload(payload);
        }
        return;
      }
      if (vsCmd == 'ANNOUNCEMENT_REF') {
        final id = data['vs_announcement_id']?.toString();
        if (id == null || id.isEmpty) return;
        final raw = await _fleetApi.fetchAnnouncementWireJson(id);
        if (raw != null) await dispatchRealtimePayload(raw);
        return;
      }
      if (vsCmd == 'ANNOUNCEMENT_CLEAR') {
        final aid = data['vs_announcement_id']?.toString();
        await _dispatch(
          AnnouncementClearCommand(
            announcementId: (aid != null && aid.isNotEmpty) ? aid : null,
          ),
        );
        return;
      }
      if (vsCmd == 'ANNOUNCEMENT_TRANSPORT') {
        final payload = data['vs_payload']?.toString();
        if (payload != null && payload.isNotEmpty) {
          await dispatchRealtimePayload(payload);
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('RealtimeDispatcher.dispatchFromFcmData error: $e\n$st');
      }
    }
  }

  /// [RealtimeDispatcher] is a process-wide singleton; do not tear down the
  /// WebSocket subscription from UI scope. Deactivate only for tests if needed.
  void dispose() {}
}
