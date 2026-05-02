import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/websocket/realtime_client.dart';
import '../../../core/websocket/realtime_command.dart';
import '../../../services/device_service.dart';
import '../../../services/token_store.dart';
import 'emergency_overlay_notifier.dart';
import 'playlist_sync_service.dart';

/// Subscribes to [RealtimeClient.messages] once and routes typed commands.
class RealtimeDispatcher {
  RealtimeDispatcher({
    required RealtimeClient realtime,
    required PlaylistSyncService playlistSync,
    required EmergencyOverlayNotifier emergencyOverlay,
    required TokenStore tokenStore,
    required DeviceService device,
  })  : _realtime = realtime,
        _playlistSync = playlistSync,
        _emergencyOverlay = emergencyOverlay,
        _tokenStore = tokenStore,
        _device = device;

  final RealtimeClient _realtime;
  final PlaylistSyncService _playlistSync;
  final EmergencyOverlayNotifier _emergencyOverlay;
  final TokenStore _tokenStore;
  final DeviceService _device;

  StreamSubscription<RealtimeMessage>? _subscription;
  bool _started = false;

  /// Idempotent; safe to call from [PlayerScreen] bootstrap.
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

  void _onMessage(RealtimeMessage m) {
    try {
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
