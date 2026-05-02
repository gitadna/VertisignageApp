import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/playlist_bundle.dart';
import '../../../models/playlist_item.dart';
import '../../../services/token_store.dart';
import 'image_cache_service.dart';
import 'playlist_api.dart';
import 'playlist_storage.dart';

/// Loads cached playlist, syncs with API in background, prefetches before swapping playback.
class PlaylistSyncService extends ChangeNotifier {
  PlaylistSyncService({
    required PlaylistStorage storage,
    required PlaylistApi api,
    required ImageCacheService cache,
    required TokenStore tokenStore,
  })  : _storage = storage,
        _api = api,
        _cache = cache,
        _tokenStore = tokenStore;

  final PlaylistStorage _storage;
  final PlaylistApi _api;
  final ImageCacheService _cache;
  final TokenStore _tokenStore;

  List<PlaylistItem> _active = [];
  int _epoch = 0;
  Timer? _pollTimer;
  bool _bootstrapStarted = false;

  /// Items safe to play (cached files exist).
  List<PlaylistItem> get activeItems => List.unmodifiable(_active);

  /// Increments whenever [activeItems] is replaced atomically after prefetch.
  int get playbackEpoch => _epoch;

  Future<void> bootstrap() async {
    if (_bootstrapStarted) return;
    _bootstrapStarted = true;

    await _hydrateFromDisk();

    unawaited(sync());

    _pollTimer ??= Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(sync()),
    );
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
  }

  /// Silent network failure; keeps existing playback and disk snapshot.
  Future<void> sync() async {
    final deviceId = _tokenStore.loadPairedDevice()?.deviceId;
    if (deviceId == null || deviceId.isEmpty) return;

    PlaylistBundle? remote;
    try {
      remote = await _api.fetchPlaylist(deviceId);
    } catch (_, __) {
      return;
    }

    if (remote == null) return;

    final stored = _storage.load();
    if (remote.version == stored?.version) {
      await _rebuildPlayableFromDiskIfChanged();
      return;
    }

    if (remote.items.isEmpty) {
      await _storage.save(remote);
      _active = [];
      _epoch++;
      notifyListeners();
      return;
    }

    final playable = await _cache.prefetchAndFilter(remote.items);

    if (remote.items.isNotEmpty && playable.isEmpty) {
      if (kDebugMode) {
        debugPrint('PlaylistSyncService: prefetch produced no playable items; keeping current loop.');
      }
      return;
    }

    await _storage.save(
      PlaylistBundle(version: remote.version, items: remote.items),
    );
    _active = playable;
    _epoch++;
    notifyListeners();
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
      if (a[i].id != b[i].id || a[i].url != b[i].url) return false;
    }
    return true;
  }

  void disposeTimer() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}
