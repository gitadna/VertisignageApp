import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/playlist_item.dart';
import '../data/media_cache_service.dart';
import '../data/playlist_sync_service.dart';

/// Current slide and resolved media (`localPath` for files, `webUri` for URL slides).
class PlayerDisplayState {
  const PlayerDisplayState({
    required this.item,
    required this.generation,
    this.localPath,
    this.webUri,
  });

  final PlaylistItem item;
  final int generation;
  final String? localPath;
  final Uri? webUri;

  bool get isWebSlide => webUri != null;
  bool get isFileSlide => localPath != null;
}

/// Drives playlist timing, caching, preload, and resilient skipping across media kinds.
class PlayerController {
  PlayerController({
    required MediaCacheService cache,
    required PlaylistSyncService sync,
  })  : _cache = cache,
        _sync = sync {
    _sync.addListener(_onPlaylistChanged);
  }

  final MediaCacheService _cache;
  final PlaylistSyncService _sync;

  final ValueNotifier<PlayerDisplayState?> display =
      ValueNotifier<PlayerDisplayState?>(null);

  List<PlaylistItem> _playlist = [];
  int _index = 0;
  Timer? _slideTimer;
  Timer? _webLoadTimer;
  bool _running = false;
  bool _handledRasterFailure = false;
  int _lastEpoch = -1;
  int _generationCounter = 0;

  List<PlaylistItem> get playlist => _playlist;

  void _onPlaylistChanged() {
    final epoch = _sync.playbackEpoch;
    if (epoch == _lastEpoch) return;
    _lastEpoch = epoch;
    _playlist = List.unmodifiable(_sync.activeItems);
    _index = 0;
    _handledRasterFailure = false;
    _cancelTimers();
    if (!_running) return;
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
    _cancelTimers();
  }

  void _cancelTimers() {
    _slideTimer?.cancel();
    _slideTimer = null;
    _webLoadTimer?.cancel();
    _webLoadTimer = null;
  }

  Future<void> _goToNextSlide() async {
    if (!_running) return;
    _cancelTimers();

    if (_sync.commitPendingPlaylistAtBoundary()) {
      return;
    }

    if (_playlist.isEmpty) return;
    _index = (_index + 1) % _playlist.length;
    await _presentCurrent();
  }

  Future<void> _presentCurrent() async {
    if (!_running || _playlist.isEmpty) return;

    _cancelTimers();
    _handledRasterFailure = false;

    final item = _playlist[_index];
    final gen = ++_generationCounter;

    if (item.mediaKind == PlaylistMediaKind.url) {
      final uri = Uri.tryParse(item.url.trim());
      if (uri == null ||
          !uri.hasAuthority ||
          !(uri.isScheme('http') || uri.isScheme('https'))) {
        await _goToNextSlide();
        return;
      }

      display.value = PlayerDisplayState(
        item: item,
        generation: gen,
        webUri: uri,
      );

      _webLoadTimer = Timer(const Duration(seconds: 15), () {
        if (!_running) return;
        if (display.value?.generation != gen) return;
        unawaited(onWebLoadFailed());
      });

      unawaited(_preloadNext());
      return;
    }

    display.value = PlayerDisplayState(item: item, generation: gen);

    final path = await _cache.resolveLocalPath(item.url);
    if (!_running) return;
    if (path == null) {
      await _goToNextSlide();
      return;
    }

    display.value = PlayerDisplayState(
      item: item,
      generation: gen,
      localPath: path,
    );

    unawaited(_preloadNext());

    final ms = item.durationMs <= 0 ? 1000 : item.durationMs;
    _slideTimer = Timer(Duration(milliseconds: ms), () {
      unawaited(_onDwellElapsed(gen));
    });
  }

  Future<void> _onDwellElapsed(int token) async {
    if (!_running) return;
    if (display.value?.generation != token) return;
    await _goToNextSlide();
  }

  Future<void> _preloadNext() async {
    if (_playlist.length <= 1 || !_running) return;
    final next = _playlist[(_index + 1) % _playlist.length];
    if (next.mediaKind == PlaylistMediaKind.url) return;
    await _cache.resolveLocalPath(next.url);
  }

  /// WebView reached a stable load point — start dwell timer.
  Future<void> onWebLoadSuccess() async {
    if (!_running) return;
    final state = display.value;
    if (state == null || !state.isWebSlide) return;

    _webLoadTimer?.cancel();
    _webLoadTimer = null;

    final ms = state.item.durationMs <= 0 ? 10000 : state.item.durationMs;
    final token = state.generation;
    _slideTimer = Timer(Duration(milliseconds: ms), () {
      unawaited(_onDwellElapsed(token));
    });
  }

  /// WebView error / load watchdog — skip item.
  Future<void> onWebLoadFailed() async {
    if (!_running) return;
    await _goToNextSlide();
  }

  /// Video finished naturally or decoder error.
  Future<void> onVideoEnded(int generation, {bool hadError = false}) async {
    if (!_running) return;
    if (display.value?.generation != generation) return;
    if (hadError && kDebugMode) {
      debugPrint('PlayerController: video ${hadError ? 'error' : 'ended'}');
    }
    await _goToNextSlide();
  }

  /// Static image failed to render — skip item.
  void onRasterDisplayFailed() {
    if (!_running || _handledRasterFailure) return;
    _handledRasterFailure = true;
    _cancelTimers();
    unawaited(_goToNextSlide());
  }

  void dispose() {
    _sync.removeListener(_onPlaylistChanged);
    stop();
    display.dispose();
  }
}
