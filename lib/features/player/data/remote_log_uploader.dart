import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../../../core/config/environment_config.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/storage_keys.dart';
import '../../../core/storage/local_storage.dart';
import '../../../core/utils/exponential_backoff.dart';
import 'kiosk_fleet_api.dart';

/// Buffers structured logs and POSTs them in batches (never blocks producers).
class RemoteLogUploader {
  RemoteLogUploader({
    required KioskFleetApi api,
    required EnvironmentConfig env,
    required LocalStorage storage,
  })  : _api = api,
        _env = env,
        _storage = storage;

  final KioskFleetApi _api;
  final EnvironmentConfig _env;
  final LocalStorage _storage;

  final Queue<Map<String, dynamic>> _queue = Queue<Map<String, dynamic>>();
  Timer? _flushTimer;
  Timer? _retryTimer;
  bool _flushing = false;
  int _retryAttempt = 0;

  static const int _maxQueued = 400;
  static const int _batchSize = 40;
  static const Duration _flushInterval = Duration(seconds: 25);

  /// Call once after [LocalStorage.init] so queued logs survive process death.
  Future<void> restoreFromDisk() async {
    if (!_env.enableRemoteLogShipping) return;
    try {
      final raw = _storage.getString(
        StorageKeys.deviceBox,
        StorageKeys.remoteLogQueueJson,
      );
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final e in decoded) {
        if (e is Map<String, dynamic> && _queue.length < _maxQueued) {
          _queue.addLast(e);
        } else if (e is Map) {
          _queue.addLast(Map<String, dynamic>.from(e));
          if (_queue.length >= _maxQueued) break;
        }
      }
      if (_queue.isNotEmpty) {
        unawaited(_flush());
      }
    } catch (_) {}
  }

  Future<void> _persistQueueToDisk() async {
    if (!_env.enableRemoteLogShipping) return;
    try {
      final list = _queue.toList();
      await _storage.setString(
        StorageKeys.deviceBox,
        StorageKeys.remoteLogQueueJson,
        jsonEncode(list),
      );
    } catch (_) {}
  }

  void enqueue({
    required String level,
    required String category,
    required String message,
    Map<String, Object?>? meta,
  }) {
    if (!_env.enableRemoteLogShipping) return;

    if (_queue.length >= _maxQueued) {
      _queue.removeFirst();
    }
    _queue.add(<String, dynamic>{
      'level': level,
      'category': category,
      'message': message,
      'ts': DateTime.now().toUtc().toIso8601String(),
      if (meta != null && meta.isNotEmpty) 'meta': meta,
    });
    unawaited(_persistQueueToDisk());

    if (_queue.length >= _batchSize) {
      unawaited(_flush());
    } else {
      _flushTimer ??= Timer(_flushInterval, () {
        _flushTimer = null;
        unawaited(_flush());
      });
    }
  }

  Future<void> _flush() async {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    var ok = true;
    try {
      final batch = <Map<String, dynamic>>[];
      while (batch.length < _batchSize && _queue.isNotEmpty) {
        batch.add(_queue.removeFirst());
      }
      ok = await _api.postLogs(batch);
      if (!ok && batch.isNotEmpty) {
        for (final item in batch.reversed) {
          _queue.addFirst(item);
        }
      } else if (ok) {
        _retryAttempt = 0;
      }
    } finally {
      _flushing = false;
      unawaited(_persistQueueToDisk());
    }
    if (_queue.isEmpty) return;
    if (!ok) {
      _scheduleRetryFlush();
    } else {
      unawaited(_flush());
    }
  }

  void _scheduleRetryFlush() {
    _retryTimer?.cancel();
    final delay = computeBackoffDelay(
      attemptIndex: _retryAttempt,
      base: const Duration(seconds: 2),
      max: AppConstants.fleetUploadRetryMaxDelay,
    );
    _retryAttempt++;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_flush());
    });
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(_flush());
  }
}
