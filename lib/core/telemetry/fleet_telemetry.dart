import '../logging/kiosk_log.dart';

/// Structured fleet diagnostics (forwarded to remote log upload when configured).
abstract final class FleetTelemetry {
  static void event(String category, String message) {
    KioskLog.event(category, message);
  }
}
