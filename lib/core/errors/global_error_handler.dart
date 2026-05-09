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
      // In release, Flutter framework errors are often recoverable (widget build/layout, image
      // decode, etc). We still log them, but do not count them towards safe mode by default.
      if (!kReleaseMode) {
        unawaited(
          _maybeRecordCrash(
            sig: _signatureFrom(details.exception, details.exceptionAsString()),
            source: 'flutter_framework',
          ),
        );
      }
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      KioskLog.e('zone', error, stack);
      // Zone/dispatcher errors are more likely to indicate an app-level failure. We record them
      // (deduped by signature) so true crash loops still trigger recovery mode protection.
      unawaited(
        _maybeRecordCrash(
          sig: _signatureFrom(error, error.toString()),
          source: 'zone',
        ),
      );
      return true;
    };
  }

  static String _signatureFrom(Object? error, String fallback) {
    final type = error == null ? 'null' : error.runtimeType.toString();
    final msg = (fallback).trim();
    final trimmed = msg.length > 160 ? msg.substring(0, 160) : msg;
    return '$type:$trimmed';
  }

  static Future<void> _maybeRecordCrash({
    required String sig,
    required String source,
  }) async {
    try {
      final env = sl<EnvironmentConfig>();
      if (!env.enableSafeMode) return;
      await sl<KioskRecoveryStore>().recordCrashMarker(sig: sig, source: source);
    } catch (_) {}
  }
}

