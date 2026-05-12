import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/logging/kiosk_log.dart';
import '../features/player/data/announcement_overlay_notifier.dart';
import '../features/player/data/emergency_overlay_notifier.dart';
import '../features/player/presentation/player_controller.dart';
import '../features/player/data/player_telemetry.dart';
import '../features/player/data/playlist_sync_service.dart';
import '../features/voice_broadcast/data/voice_broadcast_player.dart';
import '../services/device_service.dart';
import 'presentation_session_manager.dart';
import 'runtime_mode_coordinator.dart';

/// Flutter → native runtime truth for Module 4 watchdog (no websocket / schedule changes).
class PresentationRuntimeHeartbeat with WidgetsBindingObserver {
  PresentationRuntimeHeartbeat({
    required DeviceService device,
    required PlayerController player,
    required PlaylistSyncService sync,
    required PlayerTelemetry telemetry,
    required AnnouncementOverlayNotifier announcement,
    required EmergencyOverlayNotifier emergency,
    required VoiceBroadcastPlayer voicePlayer,
    required PresentationSessionManager session,
    RuntimeModeCoordinator? runtimeMode,
  })  : _device = device,
        _player = player,
        _sync = sync,
        _telemetry = telemetry,
        _announcement = announcement,
        _emergency = emergency,
        _voicePlayer = voicePlayer,
        _session = session,
        _runtimeMode = runtimeMode;

  static const MethodChannel _fromNative = MethodChannel('vertisignage/recovery_from_native');

  final DeviceService _device;
  final PlayerController _player;
  final PlaylistSyncService _sync;
  final PlayerTelemetry _telemetry;
  final AnnouncementOverlayNotifier _announcement;
  final EmergencyOverlayNotifier _emergency;
  final VoiceBroadcastPlayer _voicePlayer;
  final PresentationSessionManager _session;
  final RuntimeModeCoordinator? _runtimeMode;

  bool _started = false;
  Timer? _timer;
  String _appLifecycle = 'unknown';
  int _lastPlayerRenderMs = 0;
  int _lastPushToNativeMs = 0;

  void start() {
    if (_started) return;
    if (!Platform.isAndroid) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _fromNative.setMethodCallHandler(_onNativeCall);
    _player.display.addListener(_onDisplayChanged);
    _announcement.addListener(_scheduleFlushSoon);
    _emergency.addListener(_scheduleFlushSoon);
    _voicePlayer.takeoverState.addListener(_scheduleFlushSoon);
    _sync.addListener(_scheduleFlushSoon);
    _scheduleFlushSoon();
    _armTimer(_fastInterval);
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    _fromNative.setMethodCallHandler(null);
    _player.display.removeListener(_onDisplayChanged);
    _announcement.removeListener(_scheduleFlushSoon);
    _emergency.removeListener(_scheduleFlushSoon);
    _voicePlayer.takeoverState.removeListener(_scheduleFlushSoon);
    _sync.removeListener(_scheduleFlushSoon);
  }

  static const Duration _fastInterval = Duration(seconds: 12);
  static const Duration _slowInterval = Duration(seconds: 55);
  static const int _minNativeGapMsSlow = 2200;
  static const int _minNativeGapMsFast = 900;

  Duration get _interval =>
      _presentationRequiresVisibility() ? _fastInterval : _slowInterval;

  void _armTimer(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, _tick);
  }

  void _tick() {
    if (!_started) return;
    unawaited(_flush());
    _armTimer(_interval);
  }

  void _scheduleFlushSoon() {
    if (!_started) return;
    unawaited(_flush());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycle = state.name;
    KioskLog.event(
      'm4_visibility',
      'app_lifecycle',
      meta: <String, Object?>{'state': state.name},
    );
    _scheduleFlushSoon();
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'recoverPresentationSurface') {
      KioskLog.event(
        'm4_recovery',
        'native_recover_presentation_surface',
        meta: <String, Object?>{'sessionId': _session.sessionId},
      );
      await _player.recoverPresentationSurface();
      return null;
    }
    return null;
  }

  void _onDisplayChanged() {
    _lastPlayerRenderMs = DateTime.now().millisecondsSinceEpoch;
    _scheduleFlushSoon();
  }

  bool _presentationRequiresVisibility() {
    if (_emergency.isActive) return true;
    if (_announcement.isActive) return true;
    if (_voicePlayer.hasTakeoverVisible) return true;
    if (_sync.activeItems.isNotEmpty) return true;
    return false;
  }

  String _playbackStateLabel() {
    if (_player.playlist.isEmpty) return 'idle';
    if (_player.playbackSuspended.value) return 'suspended';
    if (_player.userPaused.value) return 'paused';
    return 'playing';
  }

  Future<void> _flush() async {
    if (!Platform.isAndroid) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final minGap = _presentationRequiresVisibility() ? _minNativeGapMsFast : _minNativeGapMsSlow;
    if (now - _lastPushToNativeMs < minGap) {
      return;
    }
    _lastPushToNativeMs = now;
    final disp = _player.display.value;
    final item = disp?.item;
    try {
      await _device.reportPresentationRuntimeHeartbeat(<String, Object?>{
        'nowMs': now,
        'route': 'player',
        'playlistId': _telemetry.currentPlaylistId,
        'playbackState': _playbackStateLabel(),
        'playbackEpoch': _sync.playbackEpoch,
        'currentContentId': item?.id,
        'appLifecycle': _appLifecycle,
        'presentationRequiresVisibility': _presentationRequiresVisibility(),
        'sessionId': _session.sessionId,
        'playlistGeneration': _sync.playbackEpoch,
        'playbackGeneration': disp?.generation,
        'playerFrameMs': _lastPlayerRenderMs > 0 ? _lastPlayerRenderMs : now,
        'lastSuccessfulRenderMs': _lastPlayerRenderMs > 0 ? _lastPlayerRenderMs : now,
        'uiVisibilityState': _mapLifecycleToUiVisibility(_appLifecycle),
      });
      final vis = _mapLifecycleToUiVisibility(_appLifecycle);
      _runtimeMode?.onPresentationHeartbeat(
        uiVisibilityState: vis,
        presentationRequiresVisibility: _presentationRequiresVisibility(),
      );
    } catch (e, st) {
      KioskLog.w('PresentationRuntimeHeartbeat', 'flush failed', e, st);
    }
  }

  static String _mapLifecycleToUiVisibility(String lifecycle) {
    switch (lifecycle) {
      case 'resumed':
        return 'foreground';
      case 'paused':
      case 'inactive':
      case 'hidden':
        return 'background';
      case 'detached':
        return 'detached';
      default:
        return 'unknown';
    }
  }
}
