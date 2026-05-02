import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../../../models/playlist_bundle.dart';
import '../../../models/playlist_item.dart';
import '../../../services/token_store.dart';
import 'device_heartbeat_service.dart';
import 'media_cache_service.dart';
import 'playlist_api.dart';
import 'playlist_storage.dart';

typedef PlaylistSyncDiagnostic = void Function(String message);

/// Loads cached playlist, syncs with API in background, prefetches before swapping playback.
class PlaylistSyncService extends ChangeNotifier {
  PlaylistSyncService({
    required PlaylistStorage storage,
    required PlaylistApi api,
    required MediaCacheService cache,
    required TokenStore tokenStore,
    required DeviceHeartbeatService heartbeat,
    PlaylistSyncDiagnostic? logDiagnostic,
  })  : _storage = storage,
        _api = api,
        _cache = cache,
        _tokenStore = tokenStore,
        _heartbeat = heartbeat,
        _logDiagnostic = logDiagnostic;

  final PlaylistStorage _storage;
  final PlaylistApi _api;
  final MediaCacheService _cache;
  final TokenStore _tokenStore;
  final DeviceHeartbeatService _heartbeat;
  final PlaylistSyncDiagnostic? _logDiagnostic;

  List<PlaylistItem> _active = [];
  List<PlaylistItem>? _pendingPlayable;
  int _epoch = 0;
  Timer? _pollTimer;
  Timer? _boundaryTimer;
  Timer? _backoffTimer;
  bool _bootstrapStarted = false;
  bool _syncRunning = false;
  bool _syncQueued = false;
  int _backoffAttempt = 0;

  /// Items safe to play (cached files exist).
  List<PlaylistItem> get activeItems => List.unmodifiable(_active);

  /// Increments whenever [activeItems] is replaced atomically after prefetch.
  int get playbackEpoch => _epoch;

  void _log(String message) {
    _logDiagnostic?.call(message);
    if (kDebugMode) {
      debugPrint('PlaylistSyncService: $message');
    }
  }

  Future<void> bootstrap() async {
    if (_bootstrapStarted) return;
    _bootstrapStarted = true;

    await _hydrateFromDisk();

    unawaited(sync());

    _pollTimer ??= Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(sync()),
    );

    _heartbeat.start();
  }

  Future<void> _hydrateFromDisk() async {
    final bundle = _storage.load();
    if (bundle == null || bundle.items.isEmpty) {
      _active = [];
      _epoch++;
      notifyListeners();
      return;
    }

    final playable = await _cache.prefetchAndFilter(bundle.items);
    _active = playable;
    _epoch++;
    notifyListeners();
    _scheduleBoundaryTimer(bundle.nextBoundaryUtc);
  }

  /// Coalesced sync: at most one run in flight; duplicate callers get merged.
  Future<void> sync() async {
    if (_syncRunning) {
      _syncQueued = true;
      return;
    }
    _syncRunning = true;
    try {
      await _runSync();
    } finally {
      _syncRunning = false;
      if (_syncQueued) {
        _syncQueued = false;
        unawaited(sync());
      }
    }
  }

  Future<void> _runSync() async {
    final token = _tokenStore.accessToken;
    if (token == null || token.isEmpty) {
      _log('sync skipped: missing device access token');
      return;
    }

    final deviceId = _tokenStore.loadPairedDevice()?.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      _log('sync skipped: no paired device');
      return;
    }

    _cancelBackoffTimer();

    PlaylistBundle? remote;
    try {
      remote = await _api.fetchPlaylist(deviceId);
    } on AppAuthException catch (e) {
      _log('sync stopped: session invalid (${e.message})');
      return;
    } catch (e, st) {
      _log('sync network error: $e');
      if (kDebugMode) debugPrint('$st');
      _scheduleBackoffRetry();
      return;
    }

    if (remote == null) {
      _log('sync: empty or failed response; keeping cached playback');
      _scheduleBackoffRetry();
      return;
    }

    _backoffAttempt = 0;

    final stored = _storage.load();

    final pastBoundary = _isPastStoredBoundary(stored);
    if (remote.version == stored?.version && !pastBoundary) {
      await _rebuildPlayableFromDiskIfChanged();
      _scheduleBoundaryTimer(stored?.nextBoundaryUtc);
      return;
    }

    if (remote.items.isEmpty) {
      _log('remote reported zero items; keeping last known good playback');
      _scheduleBoundaryTimer(remote.nextBoundaryUtc);
      return;
    }

    final playable = await _cache.prefetchAndFilter(remote.items);

    if (remote.items.isNotEmpty && playable.isEmpty) {
      _log(
        'prefetch produced no playable items; keeping current loop',
      );
      _scheduleBoundaryTimer(remote.nextBoundaryUtc);
      return;
    }

    await _storage.save(remote);

    if (_active.isEmpty) {
      _pendingPlayable = null;
      _active = playable;
      _epoch++;
      notifyListeners();
      _scheduleBoundaryTimer(remote.nextBoundaryUtc);
      return;
    }

    if (_listIdentical(_active, playable)) {
      _pendingPlayable = null;
      _scheduleBoundaryTimer(remote.nextBoundaryUtc);
      return;
    }

    _pendingPlayable = playable;
    _scheduleBoundaryTimer(remote.nextBoundaryUtc);
  }

  bool _isPastStoredBoundary(PlaylistBundle? stored) {
    final nb = stored?.nextBoundaryUtc;
    if (nb == null) return false;
    final now = DateTime.now().toUtc();
    return !now.isBefore(nb);
  }

  void _scheduleBoundaryTimer(DateTime? nextBoundaryUtc) {
    _boundaryTimer?.cancel();
    if (nextBoundaryUtc == null) return;
    final now = DateTime.now().toUtc();
    var wait = nextBoundaryUtc.difference(now);
    if (wait.isNegative) wait = Duration.zero;
    const maxWait = Duration(hours: 24);
    if (wait > maxWait) wait = maxWait;
    _boundaryTimer = Timer(wait, () {
      unawaited(sync());
    });
  }

  /// Called at slide boundaries to apply a prefetched playlist without cutting mid-item.
  bool commitPendingPlaylistAtBoundary() {
    final pending = _pendingPlayable;
    if (pending == null || pending.isEmpty) return false;
    if (_listIdentical(_active, pending)) {
      _pendingPlayable = null;
      return false;
    }
    _pendingPlayable = null;
    _active = pending;
    _epoch++;
    notifyListeners();
    return true;
  }

  void _scheduleBackoffRetry() {
    if (_backoffTimer != null) return;
    final sec = math.min(120, 1 << math.min(_backoffAttempt, 7));
    _backoffAttempt++;
    _backoffTimer = Timer(Duration(seconds: sec), () {
      _backoffTimer = null;
      unawaited(sync());
    });
    _log('scheduled retry in ${sec}s (attempt $_backoffAttempt)');
  }

  void _cancelBackoffTimer() {
    _backoffTimer?.cancel();
    _backoffTimer = null;
  }

  Future<void> _rebuildPlayableFromDiskIfChanged() async {
    final bundle = _storage.load();
    if (bundle == null) return;
    final playable = await _cache.prefetchAndFilter(bundle.items);
    if (_listIdentical(_active, playable)) return;
    _active = playable;
    _epoch++;
    notifyListeners();
  }

  bool _listIdentical(List<PlaylistItem> a, List<PlaylistItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].url != b[i].url ||
          a[i].mediaKind != b[i].mediaKind) {
        return false;
      }
    }
    return true;
  }

  void disposeTimer() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _boundaryTimer?.cancel();
    _boundaryTimer = null;
    _cancelBackoffTimer();
    _heartbeat.stop();
  }
}
