import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/config/environment_config.dart';
import '../features/player/data/announcement_overlay_notifier.dart';
import '../features/player/data/emergency_overlay_notifier.dart';
import '../features/player/data/playback_perf_telemetry.dart';
import '../features/player/data/playlist_sync_service.dart';
import '../features/voice_broadcast/data/voice_broadcast_player.dart';
import '../services/device_service.dart';
import 'runtime_mode_coordinator.dart';

/// Pushes kiosk “should we steal focus?” state to native and optionally backgrounds the task
/// when scheduled / urgent playback ends.
///
/// **Wakelock** follows the same “wants foreground” signal (active playlist, announcements,
/// emergency, voice takeover) on all platforms.
///
/// **moveTaskToBack** is Android-only and skipped when [EnvironmentConfig.kioskLockTask] is true
/// (strict unattended kiosk must stay on-screen by design).
class ForegroundPresentationCoordinator {
  ForegroundPresentationCoordinator({
    required EnvironmentConfig env,
    required DeviceService device,
    required PlaylistSyncService playlistSync,
    required AnnouncementOverlayNotifier announcement,
    required EmergencyOverlayNotifier emergency,
    required VoiceBroadcastPlayer voicePlayer,
    RuntimeModeCoordinator? runtimeMode,
  })  : _env = env,
        _device = device,
        _playlistSync = playlistSync,
        _announcement = announcement,
        _emergency = emergency,
        _voicePlayer = voicePlayer,
        _runtimeMode = runtimeMode;

  final EnvironmentConfig _env;
  final DeviceService _device;
  final PlaylistSyncService _playlistSync;
  final AnnouncementOverlayNotifier _announcement;
  final EmergencyOverlayNotifier _emergency;
  final VoiceBroadcastPlayer _voicePlayer;
  final RuntimeModeCoordinator? _runtimeMode;

  Timer? _debounce;
  Timer? _minimizeAfterIdleDebounce;
  Timer? _wakeDemandDebounce;

  bool _started = false;
  bool _lastWantsForeground = false;

  void start() {
    if (_started) return;
    _started = true;

    if (Platform.isAndroid) {
      unawaited(
        _device.configureForegroundWake(
          relaxedTeacherMode: !_env.kioskLockTask,
        ),
      );
    }

    void onChange() => _scheduleSync();

    _playlistSync.addListener(onChange);
    _announcement.addListener(onChange);
    _emergency.addListener(onChange);
    _voicePlayer.takeoverState.addListener(onChange);

    _scheduleSync();
  }

  void _scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _debounce = null;
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    if (!_started) return;
    final wants = _presentationWantsForeground();
    final prev = _lastWantsForeground;
    _lastWantsForeground = wants;
    _runtimeMode?.onPresentationDemandEdge(prev: prev, now: wants);
    if (wants) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
    if (Platform.isAndroid) {
      await _device.syncForegroundPresentationState(
        presentationWantsForeground: wants,
      );
      _maybeWakeForPresentationDemand(prev: prev, now: wants);
      _maybeDeferToBackground(prev: prev, now: wants);
    }
  }

  void _maybeWakeForPresentationDemand({
    required bool prev,
    required bool now,
  }) {
    if (!now || prev) return;
    final lc = WidgetsBinding.instance.lifecycleState;
    if (lc == AppLifecycleState.resumed) return;
    _wakeDemandDebounce?.cancel();
    _wakeDemandDebounce = Timer(const Duration(milliseconds: 400), () async {
      _wakeDemandDebounce = null;
      if (!_presentationWantsForeground()) return;
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        return;
      }
      final ok = await _device.wakeAppToForeground();
      if (ok == true) {
        _runtimeMode?.onForegroundWakeSucceeded();
      }
    });
  }

  bool _presentationWantsForeground() {
    if (_emergency.isActive) return true;
    if (_announcement.isActive) return true;
    if (_voicePlayer.hasTakeoverVisible) return true;
    if (_playlistSync.activeItems.isNotEmpty) return true;
    return false;
  }

  void _maybeDeferToBackground({
    required bool prev,
    required bool now,
  }) {
    if (_env.kioskLockTask) return;
    if (!prev || now) return;

    _minimizeAfterIdleDebounce?.cancel();
    _minimizeAfterIdleDebounce = Timer(const Duration(milliseconds: 550), () {
      _minimizeAfterIdleDebounce = null;
      if (_presentationWantsForeground()) return;
      unawaited(() async {
        final ok = await _device.moveTaskToBack();
        if (ok == false) {
          PlaybackPerfTelemetry.moveTaskToBackDenied();
        }
        _runtimeMode?.onMoveTaskToBackResult(ok: ok);
      }());
    });
  }
}
