import 'dart:async';

import '../core/telemetry/fleet_telemetry.dart';
import '../core/websocket/realtime_client.dart';
import '../features/player/data/realtime_dispatcher.dart';
import '../services/token_store.dart';

/// Keeps fleet WebSocket + [RealtimeDispatcher] aligned with pairing state for the
/// whole process (not per-screen). Screens must not call [RealtimeClient.disconnect].
class FleetRealtimeCoordinator {
  FleetRealtimeCoordinator({
    required TokenStore tokenStore,
    required RealtimeDispatcher dispatcher,
    required RealtimeClient realtime,
  })  : _tokenStore = tokenStore,
        _dispatcher = dispatcher,
        _realtime = realtime;

  final TokenStore _tokenStore;
  final RealtimeDispatcher _dispatcher;
  final RealtimeClient _realtime;

  bool _listening = false;
  StreamSubscription<RealtimeConnectionState>? _firstConnectSub;
  DateTime? _startedAt;
  bool _firstConnectLogged = false;

  void start() {
    if (_listening) return;
    _listening = true;
    _startedAt = DateTime.now();
    _firstConnectSub = _realtime.connectionStates.listen((state) {
      if (_firstConnectLogged) return;
      if (state != RealtimeConnectionState.connected) return;
      _firstConnectLogged = true;
      final elapsed = _startedAt == null
          ? -1
          : DateTime.now().difference(_startedAt!).inMilliseconds;
      FleetTelemetry.event('boot', 'websocket_connected_after_boot elapsedMs=$elapsed');
      _firstConnectSub?.cancel();
      _firstConnectSub = null;
    });
    _tokenStore.addListener(_sync);
    _sync();
  }

  void stop() {
    if (!_listening) return;
    _listening = false;
    _tokenStore.removeListener(_sync);
    _firstConnectSub?.cancel();
    _firstConnectSub = null;
  }

  void _sync() {
    final token = _tokenStore.accessToken;
    final paired = _tokenStore.hasPairedDevice;
    if (paired && token != null && token.isNotEmpty) {
      _dispatcher.ensureStarted();
      unawaited(_realtime.connect());
    } else {
      _realtime.disconnect();
    }
  }
}
