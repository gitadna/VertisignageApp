/// Backend connection lifecycle for push/commands (transport-agnostic API).
enum RealtimeConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Raw WebSocket payload for domain modules to parse.
class RealtimeMessage {
  const RealtimeMessage(this.payload);

  final String payload;
}

/// Contract for realtime transport so player/commands can subscribe without
/// knowing whether the backend uses WebSockets or another channel.
abstract class RealtimeClient {
  Stream<RealtimeConnectionState> get connectionStates;

  Stream<RealtimeMessage> get messages;

  bool get isConnected;

  /// Opens the socket (idempotent; safe to call after disconnect).
  Future<void> connect();

  /// Closes the socket and stops auto-reconnect until [connect] is called again.
  void disconnect();
}
