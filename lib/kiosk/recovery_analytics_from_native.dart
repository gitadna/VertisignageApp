import 'dart:io';

import 'package:flutter/services.dart';

import '../core/logging/kiosk_log.dart';

typedef RecoveryAnalyticsNativeCallback = void Function(
  String message,
  Map<String, Object?> meta,
);

/// Receives structured recovery payloads from Android via cached [FlutterEngine] (no Activity).
abstract final class RecoveryAnalyticsFromNative {
  static const MethodChannel _channel = MethodChannel('vertisignage/recovery_analytics');

  static RecoveryAnalyticsNativeCallback? onEvent;

  static void start() {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'event') return;
      final raw = call.arguments;
      if (raw is! Map) return;
      final meta = Map<String, Object?>.from(
        raw.map((k, v) => MapEntry(k.toString(), _normalize(v))),
      );
      final message = meta.remove('message')?.toString() ?? 'event';
      KioskLog.event('recovery_analytics', message, meta: meta);
      onEvent?.call(message, meta);
    });
  }

  static Object? _normalize(Object? v) {
    if (v is num || v is String || v is bool) return v;
    return v?.toString();
  }
}
