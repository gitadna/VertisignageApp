import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../../../models/playlist_bundle.dart';
import '../../../models/playlist_item.dart';
import '../../../models/playlist_schedule_context.dart';
import '../../../services/device_service.dart';
import '../../../services/token_store.dart';
import 'device_heartbeat_service.dart';
import 'media_cache_service.dart';
import 'player_telemetry.dart';
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
    required DeviceService device,
    PlayerTelemetry? telemetry,
    PlaylistSyncDiagnostic? logDiagnostic,
    /// Strict kiosk installs still kick native recovery at schedule boundaries; teacher tablets rely on alarms less.
    this.enqueueRecoveryOnScheduleBoundary = true,
  })  : _storage = storage,
        _api = api,
        _cache = cache,
        _tokenStore = tokenStore,
        _heartbeat = heartbeat,
        _device = device,
        _telemetry = telemetry,
        _logDiagnostic = logDiagnostic;

  final PlaylistStorage _storage;
  final PlaylistApi _api;
  final MediaCacheService _cache;
  final TokenStore _tokenStore;
  final DeviceHeartbeatService _heartbeat;
  final DeviceService _device;
  final bool enqueueRecoveryOnScheduleBoundary;
  final PlayerTelemetry? _telemetry;
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
  String? _lastSyncError;
  bool _serverPlaylistEmpty = false;

  /// True while a playlist fetch / prefetch round trip is in flight.
  bool get isSyncing => _syncRunning;

  /// Last sync failure message for kiosk UI (cleared on successful API response).
  String? get lastSyncError => _lastSyncError;

  /// Last successful API response had zero items (show empty state when [activeItems] is empty).
  bool get serverPlaylistEmpty => _serverPlaylistEmpty;

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
      const Duration(minutes: 3),
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

  bool _forceCommitNextRun = false;

  /// Coalesced sync: at most one run in flight; duplicate callers get merged.
  ///
  /// When [forceCommit] is true, any prefetched playlist that lands during this run is promoted
  /// to active playback immediately, instead of waiting for the next slide boundary. Use this
  /// whenever the backend indicates an explicit content-replacement event (force-immediate
  /// PLAYLIST_UPDATED), so kiosks reflect admin changes within a second even mid-video.
  Future<void> sync({bool forceCommit = false}) async {
    if (forceCommit) _forceCommitNextRun = true;
    if (_syncRunning) {
      _syncQueued = true;
      return;
    }
    _syncRunning = true;
    notifyListeners();
    try {
      await _runSync();
      if (_forceCommitNextRun) {
        _forceCommitNextRun = false;
        commitPendingPlaylistImmediately();
      }
    } finally {
      _syncRunning = false;
      notifyListeners();
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

    _telemetry?.markSyncStarted();
    var outcomeOk = false;
    PlaylistBundle? outcomeBundle;

    try {
      _cancelBackoffTimer();

      PlaylistBundle? remote;
      try {
        remote = await _api.fetchPlaylist(deviceId);
      } on AppAuthException catch (e) {
        _lastSyncError = e.message;
        _serverPlaylistEmpty = false;
        _log('sync stopped: session invalid (${e.message})');
        return;
      } catch (e, st) {
        _lastSyncError =
            'Could not reach the server. Check the connection and try again.';
        _serverPlaylistEmpty = false;
        _log('sync network error: $e');
        if (kDebugMode) debugPrint('$st');
        _scheduleBackoffRetry();
        return;
      }

      if (remote == null) {
        _log('sync: empty or failed response; keeping cached playback');
        _lastSyncError =
            'Could not load the playlist. Check the connection and try again.';
        _serverPlaylistEmpty = false;
        _scheduleBackoffRetry();
        return;
      }

      _lastSyncError = null;
      _backoffAttempt = 0;

      final stored = _storage.load();

      final pastBoundary = _isPastStoredBoundary(stored);
      final unchangedBundle = remote.version == stored?.version &&
          !pastBoundary &&
          _storedPlaylistMatchesRemote(stored, remote);
      if (unchangedBundle) {
        _serverPlaylistEmpty = remote.items.isEmpty;
        await _rebuildPlayableFromDiskIfChanged();
        _scheduleBoundaryTimer(stored?.nextBoundaryUtc);
        outcomeOk = true;
        outcomeBundle = stored;
        return;
      }

      if (remote.items.isEmpty) {
        _serverPlaylistEmpty = true;
        final fallbackMode =
            remote.organization?.playbackFallbackMode.toLowerCase() ?? 'none';
        final strictOutsideWindow =
            fallbackMode == 'none' || remote.schedule?.source == 'none';
        if (strictOutsideWindow) {
          _log(
            'remote reported zero items (schedule.strict/no fallback); clearing playback',
          );
          await _cache.pruneToUrls(const <String>[]);
          await _storage.save(remote);
          _pendingPlayable = null;
          _active = [];
          _epoch++;
          notifyListeners();
          _scheduleBoundaryTimer(remote.nextBoundaryUtc);
          outcomeOk = true;
          outcomeBundle = remote;
          return;
        }
        _log('remote reported zero items; keeping last known good playback');
        _scheduleBoundaryTimer(remote.nextBoundaryUtc);
        outcomeOk = true;
        outcomeBundle = remote;
        return;
      }

      _serverPlaylistEmpty = false;

      final playable = await _cache.prefetchAndFilter(remote.items);

      if (remote.items.isNotEmpty && playable.isEmpty) {
        _log(
          'prefetch produced no playable items; keeping current loop',
        );
        if (_active.isEmpty) {
          _lastSyncError =
              'Could not prepare media. Check storage space and network.';
        }
        _scheduleBoundaryTimer(remote.nextBoundaryUtc);
        return;
      }

      await _storage.save(remote);
      await _pruneCacheForPlayable(playable);

      if (_active.isEmpty) {
        _pendingPlayable = null;
        _active = playable;
        _epoch++;
        notifyListeners();
        _scheduleBoundaryTimer(remote.nextBoundaryUtc);
        outcomeOk = true;
        outcomeBundle = remote;
        return;
      }

      if (_playlistRowsEqual(_active, playable)) {
        _pendingPlayable = null;
        _scheduleBoundaryTimer(remote.nextBoundaryUtc);
        outcomeOk = true;
        outcomeBundle = remote;
        return;
      }

      _pendingPlayable = playable;
      _scheduleBoundaryTimer(remote.nextBoundaryUtc);
      outcomeOk = true;
      outcomeBundle = remote;
    } finally {
      _telemetry?.markSyncOutcome(ok: outcomeOk, bundle: outcomeBundle);
    }
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
    // Schedule edges that were already in the past or are <= 1s away should re-sync immediately AND
    // again ~1s later, in case the server's `nextBoundaryUtc` is slightly ahead of our wall clock or
    // the kiosk lost the previous notification while the schedule lifecycle worker was still mid-tick.
    final isEdge = wait <= const Duration(seconds: 1);
    _boundaryTimer = Timer(wait, () {
      if (enqueueRecoveryOnScheduleBoundary) {
        unawaited(_device.recoveryEnqueueNow('schedule_boundary_hit'));
      }
      unawaited(sync(forceCommit: true));
      if (isEdge) {
        if (enqueueRecoveryOnScheduleBoundary) {
          unawaited(_device.recoveryEnqueueNow('schedule_boundary_edge'));
        }
        Timer(const Duration(seconds: 1), () {
          if (enqueueRecoveryOnScheduleBoundary) {
            unawaited(_device.recoveryEnqueueNow('schedule_boundary_retry'));
          }
          unawaited(sync(forceCommit: true));
        });
      }
    });
  }

  /// Called at slide boundaries to apply a prefetched playlist without cutting mid-item.
  bool commitPendingPlaylistAtBoundary() {
    final pending = _pendingPlayable;
    if (pending == null || pending.isEmpty) return false;
    if (_playlistRowsEqual(_active, pending)) {
      _pendingPlayable = null;
      return false;
    }
    _pendingPlayable = null;
    _active = pending;
    _epoch++;
    notifyListeners();
    return true;
  }

  /// Promote the prefetched playlist immediately, even mid-slide. Used when the backend signals an
  /// explicit content-replacement event (force-immediate PLAYLIST_UPDATED). Returns true when the
  /// active playlist actually changed (so the caller can re-arm UI accordingly).
  bool commitPendingPlaylistImmediately() {
    final pending = _pendingPlayable;
    if (pending == null) return false;
    if (_playlistRowsEqual(_active, pending)) {
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
    if (_playlistRowsEqual(_active, playable)) return;
    _active = playable;
    _epoch++;
    notifyListeners();
  }

  bool _storedPlaylistMatchesRemote(
    PlaylistBundle? stored,
    PlaylistBundle remote,
  ) {
    if (stored == null) return false;
    return _playlistRowsEqual(stored.items, remote.items) &&
        _scheduleEqual(stored.schedule, remote.schedule) &&
        _instantUtcEqual(stored.nextBoundaryUtc, remote.nextBoundaryUtc);
  }

  bool _instantUtcEqual(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.toUtc().millisecondsSinceEpoch == b.toUtc().millisecondsSinceEpoch;
  }

  bool _scheduleEqual(
    PlaylistScheduleContext? a,
    PlaylistScheduleContext? b,
  ) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.source == b.source &&
        a.playlistId == b.playlistId &&
        a.scheduleId == b.scheduleId &&
        a.name == b.name &&
        a.priority == b.priority &&
        a.timezone == b.timezone &&
        _instantUtcEqual(a.windowStartUtc, b.windowStartUtc) &&
        _instantUtcEqual(a.windowEndUtc, b.windowEndUtc);
  }

  bool _playlistRowsEqual(List<PlaylistItem> a, List<PlaylistItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.id != y.id ||
          x.url != y.url ||
          x.mediaKind != y.mediaKind ||
          x.durationMs != y.durationMs ||
          x.order != y.order ||
          x.muted != y.muted ||
          x.transition != y.transition ||
          x.fitMode != y.fitMode) {
        return false;
      }
    }
    return true;
  }

  Future<void> _pruneCacheForPlayable(List<PlaylistItem> playable) async {
    final keepUrls = <String>{
      for (final item in _active)
        if (item.mediaKind != PlaylistMediaKind.url) item.url.trim(),
      for (final item in playable)
        if (item.mediaKind != PlaylistMediaKind.url) item.url.trim(),
    };
    await _cache.pruneToUrls(keepUrls);
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
