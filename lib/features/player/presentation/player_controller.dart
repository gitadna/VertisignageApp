import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/playlist_item.dart';
import '../data/image_cache_service.dart';
import '../data/playlist_sync_service.dart';

/// Current slide + resolved cache path (`localPath == null` means loading / blank).
class PlayerDisplayState {
  const PlayerDisplayState({
    required this.item,
    this.localPath,
  });

  final PlaylistItem item;
  final String? localPath;
}

/// Drives playlist timing, caching, preload, and resilient skipping.
/// Playlist content comes from [PlaylistSyncService] (disk + API sync).
class PlayerController {
  PlayerController({
    required ImageCacheService cache,
    required PlaylistSyncService sync,
  })  : _cache = cache,
        _sync = sync {
    _sync.addListener(_onPlaylistChanged);
  }

  final ImageCacheService _cache;
  final PlaylistSyncService _sync;

  final ValueNotifier<PlayerDisplayState?> display =
      ValueNotifier<PlayerDisplayState?>(null);

  List<PlaylistItem> _playlist = [];
  int _index = 0;
  Timer? _timer;
  bool _running = false;
  bool _handledImageFailure = false;
  int _lastEpoch = -1;

  List<PlaylistItem> get playlist => _playlist;

  void _onPlaylistChanged() {
    final epoch = _sync.playbackEpoch;
    if (epoch == _lastEpoch) return;
    _lastEpoch = epoch;
    _playlist = List.unmodifiable(_sync.activeItems);
    _index = 0;
    _handledImageFailure = false;
    if (!_running) return;
    _timer?.cancel();
    if (_playlist.isEmpty) {
      display.value = null;
      return;
    }
    unawaited(_presentCurrent());
  }

  void start() {
    _lastEpoch = _sync.playbackEpoch;
    _playlist = List.unmodifiable(_sync.activeItems);
    if (_playlist.isEmpty) {
      display.value = null;
      return;
    }
    if (_running) return;
    _running = true;
    unawaited(_presentCurrent());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _presentCurrent() async {
    if (!_running || _playlist.isEmpty) return;

    _handledImageFailure = false;
    final item = _playlist[_index];
    display.value = PlayerDisplayState(item: item, localPath: null);

    final path = await _cache.resolveLocalPath(item.url);

    if (!_running) return;

    if (path == null) {
      _advanceAfterSkip();
      return;
    }

    display.value = PlayerDisplayState(item: item, localPath: path);

    unawaited(_preloadNext());

    final ms = item.durationMs <= 0 ? 1000 : item.durationMs;
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: ms), _onTimerElapsed);
  }

  void _onTimerElapsed() {
    if (!_running) return;
    _index = (_index + 1) % _playlist.length;
    unawaited(_presentCurrent());
  }

  void _advanceAfterSkip() {
    if (!_running) return;
    _index = (_index + 1) % _playlist.length;
    unawaited(_presentCurrent());
  }

  Future<void> _preloadNext() async {
    if (_playlist.length <= 1 || !_running) return;
    final next = _playlist[(_index + 1) % _playlist.length];
    await _cache.resolveLocalPath(next.url);
  }

  /// When [Image.file] fails to decode, advance without blocking the loop.
  void onImageDisplayFailed() {
    if (!_running || _handledImageFailure) return;
    _handledImageFailure = true;
    _timer?.cancel();
    _advanceAfterSkip();
  }

  void dispose() {
    _sync.removeListener(_onPlaylistChanged);
    stop();
    display.dispose();
  }
}
