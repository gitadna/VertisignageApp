import 'dart:async';

import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../services/token_store.dart';
import '../constants/app_constants.dart';
import '../utils/exponential_backoff.dart';
import 'realtime_client.dart';

/// [RealtimeClient] using [WebSocketChannel] with exponential backoff reconnect.
/// Passes device JWT as `?token=` on each connection attempt (refreshes on reconnect).
class WebSocketRealtimeClient implements RealtimeClient {
  WebSocketRealtimeClient({
    required String wsBaseUrl,
    required TokenStore tokenStore,
  })  : _wsBaseUrl = wsBaseUrl,
        _tokenStore = tokenStore;

  final String _wsBaseUrl;
  final TokenStore _tokenStore;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _idleWatchdogTimer;

  final _states =
      StreamController<RealtimeConnectionState>.broadcast(sync: true);
  final _messages = StreamController<RealtimeMessage>.broadcast(sync: true);

  int _reconnectAttempt = 0;
  bool _userDisconnected = false;
  bool _connectInFlight = false;

  DateTime? _connectedAtUtc;
  DateTime? _lastMessageAtUtc;

  static const Duration _idleWatchdogTick = Duration(seconds: 30);
  // If we appear "connected" but receive nothing for too long, assume OEM/network wedged socket.
  static const Duration _maxConnectedSilence = Duration(minutes: 6);

  Uri _buildUri() {
    final base = Uri.parse(_wsBaseUrl);
    final token = _tokenStore.accessToken;
    final qp = Map<String, String>.from(base.queryParameters);
    if (token != null && token.isNotEmpty) {
      qp['token'] = token;
    }
    return base.replace(queryParameters: qp);
  }

  @override
  Stream<RealtimeConnectionState> get connectionStates => _states.stream;

  @override
  Stream<RealtimeMessage> get messages => _messages.stream;

  @override
  bool get isConnected =>
      _channel != null && _subscription != null && !_userDisconnected;

  @override
  Future<void> connect() async {
    if (_connectInFlight) return;
    if (!_userDisconnected &&
        _channel != null &&
        _subscription != null) {
      return;
    }
    _userDisconnected = false;
    _connectInFlight = true;
    try {
      await _openChannel();
    } finally {
      _connectInFlight = false;
    }
  }

  Future<void> _openChannel() async {
    _emit(RealtimeConnectionState.connecting);
    await _subscription?.cancel();
    try {
      final uri = _buildUri();
      _channel = WebSocketChannel.connect(uri);
      _connectedAtUtc = DateTime.now().toUtc();
      _lastMessageAtUtc = _connectedAtUtc;
      _subscription = _channel!.stream.listen(
        (dynamic data) {
          _lastMessageAtUtc = DateTime.now().toUtc();
          if (data is String) {
            _messages.add(RealtimeMessage(data));
          } else {
            _messages.add(RealtimeMessage(data.toString()));
          }
        },
        onError: (Object e, StackTrace _) {
          _scheduleReconnect();
        },
        onDone: () {
          _subscription = null;
          _channel = null;
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _reconnectAttempt = 0;
      _startIdleWatchdog();
      _emit(RealtimeConnectionState.connected);
    } catch (_) {
      _emit(RealtimeConnectionState.reconnecting);
      _scheduleReconnect();
    }
  }

  void _emit(RealtimeConnectionState s) {
    if (!_states.isClosed) _states.add(s);
  }

  void _scheduleReconnect() {
    if (_userDisconnected) {
      _emit(RealtimeConnectionState.disconnected);
      return;
    }

    _reconnectTimer?.cancel();
    _emit(RealtimeConnectionState.reconnecting);

    final delay = computeBackoffDelay(
      attemptIndex: _reconnectAttempt,
      max: AppConstants.wsReconnectMaxDelay,
    );
    _reconnectAttempt++;

    _reconnectTimer = Timer(delay, () async {
      if (_userDisconnected) return;
      await _openChannel();
    });
  }

  @override
  void disconnect() {
    _userDisconnected = true;
    _idleWatchdogTimer?.cancel();
    _idleWatchdogTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    unawaited(_subscription?.cancel());
    _subscription = null;

    final ch = _channel;
    _channel = null;
    try {
      ch?.sink.close(ws_status.normalClosure);
    } catch (_) {}

    _reconnectAttempt = 0;
    _connectedAtUtc = null;
    _lastMessageAtUtc = null;
    _emit(RealtimeConnectionState.disconnected);
  }

  void _startIdleWatchdog() {
    _idleWatchdogTimer?.cancel();
    _idleWatchdogTimer = Timer.periodic(_idleWatchdogTick, (_) {
      if (_userDisconnected) return;
      if (!isConnected) return;
      final last = _lastMessageAtUtc ?? _connectedAtUtc;
      if (last == null) return;
      final silentFor = DateTime.now().toUtc().difference(last);
      if (silentFor < _maxConnectedSilence) return;
      // Force a reconnect cycle by closing the channel; onDone will schedule reconnect.
      try {
        _channel?.sink.close(ws_status.normalClosure);
      } catch (_) {}
    });
  }

  /// Dispose stream controllers when tearing down the app (tests / hot restart).
  void dispose() {
    disconnect();
    unawaited(_states.close());
    unawaited(_messages.close());
  }
}
