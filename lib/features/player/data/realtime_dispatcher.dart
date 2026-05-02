import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/logging/kiosk_log.dart';
import '../../../core/websocket/realtime_client.dart';
import '../../../core/websocket/realtime_command.dart';
import '../../../services/device_service.dart';
import '../../../services/token_store.dart';
import 'emergency_overlay_notifier.dart';
import 'kiosk_fleet_api.dart';
import 'media_cache_service.dart';
import 'ota_update_service.dart';
import 'player_telemetry.dart';
import 'playlist_sync_service.dart';

/// Subscribes to [RealtimeClient.messages] once and routes typed commands (non-blocking).
class RealtimeDispatcher {
  RealtimeDispatcher({
    required RealtimeClient realtime,
    required PlaylistSyncService playlistSync,
    required EmergencyOverlayNotifier emergencyOverlay,
    required TokenStore tokenStore,
    required DeviceService device,
    required KioskFleetApi fleetApi,
    required MediaCacheService cache,
    required OtaUpdateService ota,
    required PlayerTelemetry telemetry,
  })  : _realtime = realtime,
        _playlistSync = playlistSync,
        _emergencyOverlay = emergencyOverlay,
        _tokenStore = tokenStore,
        _device = device,
        _fleetApi = fleetApi,
        _cache = cache,
        _ota = ota,
        _telemetry = telemetry;

  final RealtimeClient _realtime;
  final PlaylistSyncService _playlistSync;
  final EmergencyOverlayNotifier _emergencyOverlay;
  final TokenStore _tokenStore;
  final DeviceService _device;
  final KioskFleetApi _fleetApi;
  final MediaCacheService _cache;
  final OtaUpdateService _ota;
  final PlayerTelemetry _telemetry;

  final LinkedHashSet<String> _recentMessageIds = LinkedHashSet<String>();

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
      await _fleetApi.postCommandAck(
        messageId: cmd.messageId,
        commandType: 'GET_STATUS',
        ok: true,
        detail: <String, dynamic>{
          'appVersion': info.version,
          'buildNumber': info.buildNumber,
          'syncStatus': _telemetry.syncStatus,
          'lastSuccessfulSyncUtc':
              _telemetry.lastSuccessfulSyncUtc?.toUtc().toIso8601String(),
          'currentPlaylistId': _telemetry.currentPlaylistId,
          'currentScheduleId': _telemetry.currentScheduleId,
          if (cacheMb != null) 'cacheUsedMb': cacheMb,
        },
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

    if (cmd is PlaylistUpdatedCommand || cmd is SyncRequestCommand) {
      await _playlistSync.sync();
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
    if (cmd is RestartAppCommand) {
      await _device.restartApplication();
    }
  }

  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _started = false;
  }
}
