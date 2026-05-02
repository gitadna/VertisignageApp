import 'dart:async';

import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/app_constants.dart';
import '../utils/exponential_backoff.dart';
import 'realtime_client.dart';

/// [RealtimeClient] using [WebSocketChannel] with exponential backoff reconnect.
class WebSocketRealtimeClient implements RealtimeClient {
  WebSocketRealtimeClient({required String wsUrl}) : _wsUrl = wsUrl;

  final String _wsUrl;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;

  final _states =
      StreamController<RealtimeConnectionState>.broadcast(sync: true);
  final _messages = StreamController<RealtimeMessage>.broadcast(sync: true);

  int _reconnectAttempt = 0;
  bool _userDisconnected = false;
  bool _connectInFlight = false;

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
      final uri = Uri.parse(_wsUrl);
      _channel = WebSocketChannel.connect(uri);
      _subscription = _channel!.stream.listen(
        (dynamic data) {
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
      _emit(RealtimeConnectionState.connected);
    } catch (_, __) {
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
    _emit(RealtimeConnectionState.disconnected);
  }

  /// Dispose stream controllers when tearing down the app (tests / hot restart).
  void dispose() {
    disconnect();
    unawaited(_states.close());
    unawaited(_messages.close());
  }
}
