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

  /// Console log filtering.
  ///
  /// Defaults:
  /// - KIOSK_CONSOLE_LOG_LEVEL=warn  (prints warn+error only)
  /// - KIOSK_CONSOLE_USER_LOGS=true (prints user logs)
  ///
  /// Example:
  /// flutter run ... --dart-define=KIOSK_CONSOLE_LOG_LEVEL=info --dart-define=KIOSK_CONSOLE_USER_LOGS=true
  static const String _consoleLevelRaw =
      String.fromEnvironment('KIOSK_CONSOLE_LOG_LEVEL', defaultValue: 'warn');
  static const bool _consoleUserLogs =
      bool.fromEnvironment('KIOSK_CONSOLE_USER_LOGS', defaultValue: true);

  /// Wired after DI (Phase 8 fleet logging).
  static void bindRemoteSink(KioskRemoteSink? sink) {
    _remoteSink = sink;
  }

  static int _levelRank(String level) {
    switch (level.toLowerCase()) {
      case 'error':
      case 'e':
        return 40;
      case 'warn':
      case 'warning':
      case 'w':
        return 30;
      case 'info':
      case 'i':
        return 20;
      case 'debug':
      case 'd':
        return 10;
      default:
        return 20;
    }
  }

  static bool _shouldPrintConsole(String level) {
    if (!kDebugMode) return false;
    return _levelRank(level) >= _levelRank(_consoleLevelRaw);
  }

  static void d(String tag, String message) => _console('debug', tag, message);

  static void i(String tag, String message) => _console('info', tag, message);

  static void w(String tag, String message, [Object? error, StackTrace? stack]) {
    final msg = error == null ? message : '$message: $error';
    _console('warn', tag, msg, stack: stack);
  }

  /// Explicit "user log" channel (kept even when console level is warn).
  static void user(String tag, String message) {
    if (!_consoleUserLogs || !kDebugMode) return;
    debugPrint('[Kiosk][USER][$tag] $message');
    onLog?.call(tag, message, null);
  }

  static void _console(
    String level,
    String tag,
    String message, {
    StackTrace? stack,
  }) {
    if (_shouldPrintConsole(level)) {
      final lvl = level.toUpperCase();
      if (stack != null) {
        debugPrint('[Kiosk][$lvl][$tag] $message\n$stack');
      } else {
        debugPrint('[Kiosk][$lvl][$tag] $message');
      }
    }
    onLog?.call(tag, message, stack);
  }

  static void e(String tag, Object error, [StackTrace? stack]) {
    _console('error', tag, error.toString(), stack: stack);
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
    // NOTE: Intentionally remote-only by default to keep `flutter run` readable.
    // Use [user] / [i] / [w] / [e] for console logs.
    _remoteSink?.call(
      level: level,
      category: category,
      message: message,
      meta: meta,
    );
  }
}
