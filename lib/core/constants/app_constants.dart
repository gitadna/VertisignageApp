/// App-wide non-secret constants (timeouts live with Dio / WS clients).
abstract final class AppConstants {
  static const String appName = 'Vertisignage';

  /// Max retries for transient HTTP failures (GET / idempotent).
  static const int httpMaxRetries = 3;

  /// WebSocket reconnect attempts are effectively unbounded; delay is capped.
  static const Duration wsReconnectMaxDelay = Duration(seconds: 60);
}
