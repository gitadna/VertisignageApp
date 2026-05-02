import 'dart:async';

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

  void start() {
    if (_listening) return;
    _listening = true;
    _tokenStore.addListener(_sync);
    _sync();
  }

  void stop() {
    if (!_listening) return;
    _listening = false;
    _tokenStore.removeListener(_sync);
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
