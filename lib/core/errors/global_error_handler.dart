import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../logging/kiosk_log.dart';

/// Installs Flutter / zone-level handlers so failures are logged without stopping playback.
abstract final class GlobalErrorHandler {
  static void install() {
    FlutterError.onError = (FlutterErrorDetails details) {
      KioskLog.e(
        'FlutterError',
        details.exceptionAsString(),
        details.stack,
      );
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      KioskLog.e('zone', error, stack);
      return true;
    };
  }
}
