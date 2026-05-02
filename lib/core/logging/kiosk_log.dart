import 'package:flutter/foundation.dart';

typedef KioskRemoteSink = void Function({
  required String level,
  required String category,
  required String message,
  Map<String, Object?>? meta,
});

/// Operational logging (debug: console; release: optional remote shipping).
abstract final class KioskLog {
  static void Function(String tag, Object? message, StackTrace? stack)? onLog;

  static KioskRemoteSink? _remoteSink;

  /// Wired after DI (Phase 8 fleet logging).
  static void bindRemoteSink(KioskRemoteSink? sink) {
    _remoteSink = sink;
  }

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
    _remoteSink?.call(
      level: 'error',
      category: tag,
      message: error.toString(),
      meta: stack != null ? <String, Object?>{'stack': stack.toString()} : null,
    );
  }

  /// Structured fleet log (non-blocking).
  static void event(
    String category,
    String message, {
    String level = 'info',
    Map<String, Object?>? meta,
  }) {
    d(category, message);
    _remoteSink?.call(
      level: level,
      category: category,
      message: message,
      meta: meta,
    );
  }
}
