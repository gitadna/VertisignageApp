import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/storage_keys.dart';
import '../../../core/storage/local_storage.dart';
import '../../../core/utils/exponential_backoff.dart';
import '../../../services/token_store.dart';
import '../../../services/device_service.dart';
import 'media_cache_service.dart';
import 'player_telemetry.dart';

/// Periodic authenticated heartbeat: online status, telemetry, and version.
class DeviceHeartbeatService {
  DeviceHeartbeatService({
    required Dio dio,
    required TokenStore tokenStore,
    required PlayerTelemetry telemetry,
    required MediaCacheService cache,
    required DeviceService device,
    required LocalStorage storage,
    Duration interval = const Duration(seconds: 45),
  })  : _dio = dio,
        _tokenStore = tokenStore,
        _telemetry = telemetry,
        _cache = cache,
        _device = device,
        _storage = storage,
        _interval = interval;

  final Dio _dio;
  final TokenStore _tokenStore;
  final PlayerTelemetry _telemetry;
  final MediaCacheService _cache;
  final DeviceService _device;
  final LocalStorage _storage;
  final Duration _interval;

  Timer? _timer;
  Timer? _retryTimer;
  PackageInfo? _packageInfo;
  static final DateTime _processStartedAt = DateTime.now();

  int _retryAttempt = 0;
  bool _postInFlight = false;

  DateTime? _lastCacheMetricAtUtc;
  int? _lastCacheUsedMb;
  static const Duration _cacheMetricInterval = Duration(minutes: 60);

  static const int _maxPersistedRetries = 24;

  void start() {
    _timer ??= Timer.periodic(_interval, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<List<Map<String, dynamic>>> _readRetryQueue() async {
    try {
      final raw = _storage.getString(
        StorageKeys.deviceBox,
        StorageKeys.heartbeatRetryQueueJson,
      );
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <Map<String, dynamic>>[];
      for (final e in decoded) {
        if (e is Map<String, dynamic>) {
          out.add(e);
        } else if (e is Map) {
          out.add(Map<String, dynamic>.from(e));
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeRetryQueue(List<Map<String, dynamic>> items) async {
    try {
      if (items.isEmpty) {
        await _storage.remove(
          StorageKeys.deviceBox,
          StorageKeys.heartbeatRetryQueueJson,
        );
        return;
      }
      while (items.length > _maxPersistedRetries) {
        items.removeAt(0);
      }
      await _storage.setString(
        StorageKeys.deviceBox,
        StorageKeys.heartbeatRetryQueueJson,
        jsonEncode(items),
      );
    } catch (_) {}
  }

  Future<void> _appendFailedBody(Map<String, dynamic> body) async {
    final list = await _readRetryQueue();
    list.add(body);
    await _writeRetryQueue(list);
  }

  Future<void> _tick() async {
    if (_postInFlight) return;
    final device = _tokenStore.loadPairedDevice();
    final token = _tokenStore.accessToken;
    if (device == null || token == null || token.isEmpty) return;

    _postInFlight = true;
    try {
      _packageInfo ??= await PackageInfo.fromPlatform();

      var pending = await _readRetryQueue();
      while (pending.isNotEmpty) {
        final first = pending.first;
        await _mergeModule4Fields(first);
        if (await _postHeartbeat(device.deviceId, first)) {
          pending.removeAt(0);
          _retryAttempt = 0;
          await _writeRetryQueue(pending);
        } else {
          await _writeRetryQueue(pending);
          _scheduleBackoffRetry();
          return;
        }
      }

      final body = _buildBody();
      await _mergeModule4Fields(body);
      if (await _postHeartbeat(device.deviceId, body)) {
        _retryAttempt = 0;
        _retryTimer?.cancel();
        _retryTimer = null;
      } else {
        await _appendFailedBody(body);
        _scheduleBackoffRetry();
      }
    } finally {
      _postInFlight = false;
    }
  }

  Map<String, dynamic> _buildBody() {
    final uptimeSec =
        DateTime.now().difference(_processStartedAt).inSeconds.clamp(0, 1 << 30);

    final body = <String, dynamic>{
      'status': 'online',
      'reportedAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': _packageInfo!.version,
      'reportedUptimeSec': uptimeSec,
      'syncStatus': _telemetry.syncStatus,
    };
    final ls = _telemetry.lastSuccessfulSyncUtc?.toUtc().toIso8601String();
    if (ls != null) body['lastSyncAt'] = ls;
    final pid = _telemetry.currentPlaylistId;
    if (pid != null) body['currentPlaylistId'] = pid;
    final sid = _telemetry.currentScheduleId;
    if (sid != null) body['currentScheduleId'] = sid;
    body['supportsWakeRelay'] = true;
    body['supportsOverlay'] = true;
    return body;
  }

  Future<void> _mergeModule4Fields(Map<String, dynamic> body) async {
    if (!Platform.isAndroid) return;
    try {
      final snap = await _device.getHealthSnapshot();
      final m4 = snap['module4'];
      if (m4 is! Map) return;
      body['m4OemProfile'] = m4['oemProfileId'];
      body['m4LoopRecent'] = m4['loopRecent'];
      body['m4LoopInWindow'] = m4['loopInWindow'];
      final wd = m4['watchdog'];
      if (wd is Map) {
        body['m4LastStage'] = wd['m4LastStage'];
        body['m4LastReason'] = wd['m4LastReason'];
        body['m4UiVisibility'] = wd['uiVisibilityState'];
      }
    } catch (_) {}
  }

  Future<bool> _postHeartbeat(
    String deviceId,
    Map<String, dynamic> data,
  ) async {
    try {
      final nowUtc = DateTime.now().toUtc();
      int? cacheMb;
      final lastAt = _lastCacheMetricAtUtc;
      if (lastAt == null || nowUtc.difference(lastAt) >= _cacheMetricInterval) {
        _lastCacheMetricAtUtc = nowUtc;
        _lastCacheUsedMb = await _cache.approximateCacheSizeMb();
      }
      cacheMb = _lastCacheUsedMb;
      final payload = Map<String, dynamic>.from(data);
      final isOwner = await _device.isDeviceOwner();
      final inLockTask = await _device.isInLockTask();
      payload['supportsDeviceOwner'] = true;
      payload['deviceOwner'] = isOwner;
      payload['kioskMode'] = isOwner && inLockTask;
      payload['overlayPermissionGranted'] = await _device.canDrawOverlays();
      if (cacheMb != null) {
        payload['cacheUsedMb'] = cacheMb;
      }
      await _dio.post<void>(
        '/api/devices/$deviceId/heartbeat',
        data: payload,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void _scheduleBackoffRetry() {
    _retryTimer?.cancel();
    final delay = computeBackoffDelay(
      attemptIndex: _retryAttempt,
      base: const Duration(seconds: 3),
      max: AppConstants.heartbeatRetryMaxDelay,
    );
    _retryAttempt++;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_tick());
    });
  }
}
