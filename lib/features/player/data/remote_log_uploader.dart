import 'dart:async';
import 'dart:collection';

import '../../../core/config/environment_config.dart';
import 'kiosk_fleet_api.dart';

/// Buffers structured logs and POSTs them in batches (never blocks producers).
class RemoteLogUploader {
  RemoteLogUploader({
    required KioskFleetApi api,
    required EnvironmentConfig env,
  })  : _api = api,
        _env = env;

  final KioskFleetApi _api;
  final EnvironmentConfig _env;

  final Queue<Map<String, dynamic>> _queue = Queue<Map<String, dynamic>>();
  Timer? _flushTimer;
  Timer? _retryTimer;
  bool _flushing = false;

  static const int _maxQueued = 400;
  static const int _batchSize = 40;
  static const Duration _flushInterval = Duration(seconds: 25);

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
      }
    } finally {
      _flushing = false;
      if (_queue.isEmpty) return;
      if (!ok) {
        _scheduleRetryFlush();
      } else {
        unawaited(_flush());
      }
    }
  }

  void _scheduleRetryFlush() {
    _retryTimer ??= Timer(const Duration(seconds: 15), () {
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
