import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/environment_config.dart';
import '../di/injection.dart';
import '../logging/kiosk_log.dart';
import '../recovery/kiosk_recovery_store.dart';

/// Installs Flutter / zone-level handlers so failures are logged without stopping playback.
abstract final class GlobalErrorHandler {
  static void install() {
    FlutterError.onError = (FlutterErrorDetails details) {
      KioskLog.e(
        'FlutterError',
        details.exceptionAsString(),
        details.stack,
      );
      unawaited(_maybeRecordCrash());
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      KioskLog.e('zone', error, stack);
      unawaited(_maybeRecordCrash());
      return true;
    };
  }

  static Future<void> _maybeRecordCrash() async {
    try {
      final env = sl<EnvironmentConfig>();
      if (!env.enableSafeMode) return;
      await sl<KioskRecoveryStore>().recordCrashMarker();
    } catch (_) {}
  }
}

