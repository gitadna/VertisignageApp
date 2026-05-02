/// App-wide non-secret constants (timeouts live with Dio / WS clients).
abstract final class AppConstants {
  static const String appName = 'Vertisignage';

  /// Max retries for transient HTTP failures (GET / idempotent).
  static const int httpMaxRetries = 3;

  /// WebSocket reconnect attempts are effectively unbounded; delay is capped.
  static const Duration wsReconnectMaxDelay = Duration(seconds: 60);

  /// If no slide advances within this window, force next item (stuck decoder / timer).
  static const Duration stuckSlideWatchdog = Duration(seconds: 52);

  /// Fleet log upload retry backoff cap (exponential with jitter).
  static const Duration fleetUploadRetryMaxDelay = Duration(minutes: 5);

  /// Heartbeat POST retry backoff cap.
  static const Duration heartbeatRetryMaxDelay = Duration(minutes: 5);
}
