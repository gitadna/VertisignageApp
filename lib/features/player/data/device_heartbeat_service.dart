import 'dart:async';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../services/token_store.dart';

/// Periodic authenticated heartbeat so the backend sees the kiosk as online.
class DeviceHeartbeatService {
  DeviceHeartbeatService({
    required Dio dio,
    required TokenStore tokenStore,
    Duration interval = const Duration(seconds: 45),
  })  : _dio = dio,
        _tokenStore = tokenStore,
        _interval = interval;

  final Dio _dio;
  final TokenStore _tokenStore;
  final Duration _interval;

  Timer? _timer;
  PackageInfo? _packageInfo;

  void start() {
    _timer ??= Timer.periodic(_interval, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    final device = _tokenStore.loadPairedDevice();
    final token = _tokenStore.accessToken;
    if (device == null || token == null || token.isEmpty) return;

    _packageInfo ??= await PackageInfo.fromPlatform();

    try {
      await _dio.post<void>(
        '/api/devices/${device.deviceId}/heartbeat',
        data: <String, dynamic>{
          'status': 'online',
          'reportedAt': DateTime.now().toUtc().toIso8601String(),
          'appVersion': _packageInfo!.version,
        },
      );
    } catch (_) {
      // Non-fatal; playback is unaffected.
    }
  }
}
