import 'package:flutter/widgets.dart';

import '../core/logging/kiosk_log.dart';
import '../features/player/data/announcement_overlay_notifier.dart';
import '../features/player/data/emergency_overlay_notifier.dart';
import '../features/player/data/playlist_sync_service.dart';
import '../features/voice_broadcast/data/voice_broadcast_player.dart';

/// Single active kiosk runtime mode for fleet diagnostics (admin timeline).
enum KioskRuntimeMode {
  backgroundRuntime,
  foregroundPresentation,
  overlayPresentation,
  recoveryTransition,
}

String _runtimeModeTelemetryName(KioskRuntimeMode m) => switch (m) {
      KioskRuntimeMode.backgroundRuntime => 'background_runtime',
      KioskRuntimeMode.foregroundPresentation => 'foreground_presentation',
      KioskRuntimeMode.overlayPresentation => 'overlay_presentation',
      KioskRuntimeMode.recoveryTransition => 'recovery_transition',
    };

/// Coordinates runtime mode + admin timeline events; one mode active at a time.
class RuntimeModeCoordinator with WidgetsBindingObserver {
  RuntimeModeCoordinator({
    required PlaylistSyncService playlistSync,
    required AnnouncementOverlayNotifier announcement,
    required EmergencyOverlayNotifier emergency,
    required VoiceBroadcastPlayer voicePlayer,
  })  : _playlistSync = playlistSync,
        _announcement = announcement,
        _emergency = emergency,
        _voicePlayer = voicePlayer;

  final PlaylistSyncService _playlistSync;
  final AnnouncementOverlayNotifier _announcement;
  final EmergencyOverlayNotifier _emergency;
  final VoiceBroadcastPlayer _voicePlayer;

  bool _started = false;
  KioskRuntimeMode _mode = KioskRuntimeMode.backgroundRuntime;
  String? _lastSilentRecoveryAttemptId;
  int? _silentRecoveryStartedAtMs;
  bool _hadPlaylistItems = false;

  KioskRuntimeMode get mode => _mode;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _hadPlaylistItems = _playlistSync.activeItems.isNotEmpty;
    _playlistSync.addListener(_onNotifiersChanged);
    _announcement.addListener(_onNotifiersChanged);
    _emergency.addListener(_onNotifiersChanged);
    _voicePlayer.takeoverState.addListener(_onNotifiersChanged);
    _recomputeMode(reason: 'start');
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _playlistSync.removeListener(_onNotifiersChanged);
    _announcement.removeListener(_onNotifiersChanged);
    _emergency.removeListener(_onNotifiersChanged);
    _voicePlayer.takeoverState.removeListener(_onNotifiersChanged);
  }

  void _onNotifiersChanged() => _recomputeMode(reason: 'notifier');

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _recomputeMode(reason: 'lifecycle_${state.name}');
  }

  /// Native recovery analytics (`recovery_started` / `recovery_completed`).
  void onNativeRecoveryAnalytics(String message, Map<String, Object?> meta) {
    if (message == 'recovery_started') {
      _setMode(KioskRuntimeMode.recoveryTransition, 'native_recovery_started');
      KioskLog.event(
        'admin_timeline',
        'recovery_started',
        meta: Map<String, Object?>.from(meta),
      );
      return;
    }
    if (message == 'recovery_completed') {
      final silent = meta['silent_runtime_restore'] == true;
      if (silent) {
        _silentRecoveryStartedAtMs = DateTime.now().millisecondsSinceEpoch;
        _lastSilentRecoveryAttemptId = meta['recovery_attempt_id']?.toString();
      }
      KioskLog.event(
        'admin_timeline',
        'recovery_completed',
        meta: Map<String, Object?>.from(meta),
      );
      _recomputeMode(reason: 'recovery_completed');
      return;
    }
    KioskLog.event('admin_timeline', message, meta: Map<String, Object?>.from(meta));
  }

  void onPresentationDemandEdge({required bool prev, required bool now}) {
    if (now && !prev) {
      KioskLog.event(
        'admin_timeline',
        'foreground_requested',
        meta: <String, Object?>{
          'source': _demandSourceLabel(),
        },
      );
    }
    _recomputeMode(reason: 'presentation_demand');
  }

  void onForegroundWakeSucceeded() {
    KioskLog.event(
      'admin_timeline',
      'foreground_success',
      meta: const <String, Object?>{'source': 'presentation_demand'},
    );
  }

  void onMoveTaskToBackResult({required bool? ok}) {
    KioskLog.event(
      'admin_timeline',
      'returned_to_background',
      meta: <String, Object?>{
        'move_task_to_back_ok': ok,
      },
    );
    _recomputeMode(reason: 'move_task_to_back');
  }

  /// After native heartbeat flush: measure silent background restore latency.
  void onPresentationHeartbeat({
    required String uiVisibilityState,
    required bool presentationRequiresVisibility,
  }) {
    final pendingSilent = _silentRecoveryStartedAtMs;
    if (pendingSilent == null) return;
    if (uiVisibilityState != 'background' || presentationRequiresVisibility) return;
    final elapsed = DateTime.now().millisecondsSinceEpoch - pendingSilent;
    _silentRecoveryStartedAtMs = null;
    final attemptId = _lastSilentRecoveryAttemptId;
    _lastSilentRecoveryAttemptId = null;
    final meta = <String, Object?>{
      'time_to_background_runtime_ms': elapsed,
    };
    if (attemptId != null) {
      meta['recovery_attempt_id'] = attemptId;
    }
    KioskLog.event(
      'recovery_analytics',
      'silent_background_runtime_measured',
      meta: meta,
    );
  }

  void _recomputeMode({required String reason}) {
    if (!_started) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final wants = _presentationWantsForeground();
    final overlayOnly =
        _announcement.isActive &&
        !wants &&
        (lifecycle == AppLifecycleState.paused ||
            lifecycle == AppLifecycleState.inactive ||
            lifecycle == AppLifecycleState.hidden);

    final KioskRuntimeMode next;
    if (overlayOnly) {
      next = KioskRuntimeMode.overlayPresentation;
    } else if (wants &&
        (lifecycle == AppLifecycleState.resumed || lifecycle == null)) {
      next = KioskRuntimeMode.foregroundPresentation;
    } else {
      next = KioskRuntimeMode.backgroundRuntime;
    }
    _setMode(next, reason);
    _trackPlaylistSessions(wants);
  }

  void _trackPlaylistSessions(bool wantsForeground) {
    final hasItems = _playlistSync.activeItems.isNotEmpty;
    if (hasItems && !_hadPlaylistItems && wantsForeground) {
      KioskLog.event(
        'admin_timeline',
        'playlist_foreground_session_started',
        meta: <String, Object?>{
          'playback_epoch': _playlistSync.playbackEpoch,
        },
      );
    } else if (!hasItems && _hadPlaylistItems) {
      KioskLog.event(
        'admin_timeline',
        'playlist_foreground_session_completed',
        meta: <String, Object?>{
          'playback_epoch': _playlistSync.playbackEpoch,
        },
      );
    }
    _hadPlaylistItems = hasItems;
  }

  void _setMode(KioskRuntimeMode next, String reason) {
    if (next == _mode) return;
    final from = _mode;
    _mode = next;
    KioskLog.event(
      'admin_timeline',
      'runtime_mode_changed',
      meta: <String, Object?>{
        'from': _runtimeModeTelemetryName(from),
        'to': _runtimeModeTelemetryName(next),
        'reason': reason,
      },
    );
  }

  bool _presentationWantsForeground() {
    if (_emergency.isActive) return true;
    if (_announcement.isActive) return true;
    if (_voicePlayer.hasTakeoverVisible) return true;
    if (_playlistSync.activeItems.isNotEmpty) return true;
    return false;
  }

  String _demandSourceLabel() {
    if (_emergency.isActive) return 'emergency';
    if (_announcement.isActive) return 'announcement';
    if (_voicePlayer.hasTakeoverVisible) return 'voice';
    if (_playlistSync.activeItems.isNotEmpty) return 'schedule';
    return 'unknown';
  }
}
