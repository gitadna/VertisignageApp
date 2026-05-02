import 'package:flutter/foundation.dart';

/// Silent operational logging (debug: console; release: hook only—no user UI).
abstract final class KioskLog {
  static void Function(String tag, Object? message, StackTrace? stack)? onLog;

  static void d(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[Kiosk][$tag] $message');
    }
    onLog?.call(tag, message, null);
  }

  static void e(String tag, Object error, [StackTrace? stack]) {
    if (kDebugMode) {
      debugPrint('[Kiosk][$tag] $error\n${stack ?? StackTrace.current}');
    }
    onLog?.call(tag, error, stack);
  }
}
