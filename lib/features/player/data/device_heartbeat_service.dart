import 'dart:async';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../services/token_store.dart';
import 'media_cache_service.dart';
import 'player_telemetry.dart';

/// Periodic authenticated heartbeat: online status, telemetry, and version.
class DeviceHeartbeatService {
  DeviceHeartbeatService({
    required Dio dio,
    required TokenStore tokenStore,
    required PlayerTelemetry telemetry,
    required MediaCacheService cache,
    Duration interval = const Duration(seconds: 45),
  })  : _dio = dio,
        _tokenStore = tokenStore,
        _telemetry = telemetry,
        _cache = cache,
        _interval = interval;

  final Dio _dio;
  final TokenStore _tokenStore;
  final PlayerTelemetry _telemetry;
  final MediaCacheService _cache;
  final Duration _interval;

  Timer? _timer;
  PackageInfo? _packageInfo;
  static final DateTime _processStartedAt = DateTime.now();

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

    final uptimeSec =
        DateTime.now().difference(_processStartedAt).inSeconds.clamp(0, 1 << 30);

    final cacheMb = await _cache.approximateCacheSizeMb();

    try {
      await _dio.post<void>(
        '/api/devices/${device.deviceId}/heartbeat',
        data: <String, dynamic>{
          'status': 'online',
          'reportedAt': DateTime.now().toUtc().toIso8601String(),
          'appVersion': _packageInfo!.version,
          'reportedUptimeSec': uptimeSec,
          'syncStatus': _telemetry.syncStatus,
          'lastSyncAt':
              _telemetry.lastSuccessfulSyncUtc?.toUtc().toIso8601String(),
          'currentPlaylistId': _telemetry.currentPlaylistId,
          'currentScheduleId': _telemetry.currentScheduleId,
          if (cacheMb != null) 'cacheUsedMb': cacheMb,
        },
      );
    } catch (_) {
      // Non-fatal; playback is unaffected.
    }
  }
}
