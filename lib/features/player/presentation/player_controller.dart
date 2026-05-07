import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../models/playlist_item.dart';
import '../data/media_cache_service.dart';
import '../data/playlist_sync_service.dart';

enum UrlRenderMode { web, video }

/// Current slide and resolved media (`localPath` for files, `webUri` for URL slides).
class PlayerDisplayState {
  const PlayerDisplayState({
    required this.item,
    required this.generation,
    this.localPath,
    this.webUri,
    this.urlRenderMode = UrlRenderMode.web,
    this.urlVideoFallbackUsed = false,
  });

  final PlaylistItem item;
  final int generation;
  final String? localPath;
  final Uri? webUri;
  final UrlRenderMode urlRenderMode;
  final bool urlVideoFallbackUsed;

  bool get isWebSlide => webUri != null;
  bool get isFileSlide => localPath != null;
  bool get isUrlVideoMode =>
      item.mediaKind == PlaylistMediaKind.url &&
      webUri != null &&
      urlRenderMode == UrlRenderMode.video;
}

/// Drives playlist timing, caching, preload, and resilient skipping across media kinds.
class PlayerController {
  PlayerController({
    required MediaCacheService cache,
    required PlaylistSyncService sync,
  })  : _cache = cache,
        _sync = sync {
    _sync.addListener(_onPlaylistChanged);
    userPaused.addListener(_syncPlaybackSuspended);
    announcementHold.addListener(_syncPlaybackSuspended);
    _syncPlaybackSuspended();
  }

  final MediaCacheService _cache;
  final PlaylistSyncService _sync;

  final ValueNotifier<PlayerDisplayState?> display =
      ValueNotifier<PlayerDisplayState?>(null);

  List<PlaylistItem> _playlist = [];
  int _index = 0;
  Timer? _slideTimer;
  Timer? _webLoadTimer;
  Timer? _progressWatchdog;
  bool _running = false;
  bool _handledRasterFailure = false;
  int _lastEpoch = -1;
  int _generationCounter = 0;
  int _videoErrorBurstCount = 0;
  String? _videoErrorBurstKey;
  DateTime? _videoErrorBurstStartedAt;

  static const int _videoErrorBurstThreshold = 3;
  static const Duration _videoErrorBurstWindow = Duration(seconds: 8);
  static const Duration _videoErrorCooldown = Duration(seconds: 3);

  /// When true, auto-advance timers are off and video should be paused.
  final ValueNotifier<bool> userPaused = ValueNotifier<bool>(false);

  /// Full-screen announcement overlay is blocking normal playlist timing.
  final ValueNotifier<bool> announcementHold = ValueNotifier<bool>(false);

  /// Union of [userPaused] and [announcementHold] for timers and video decoder.
  final ValueNotifier<bool> playbackSuspended = ValueNotifier<bool>(false);

  List<PlaylistItem> get playlist => _playlist;

  void _debug(String message) {
    if (!kDebugMode) return;
    debugPrint('PlayerController: $message');
  }

  void _syncPlaybackSuspended() {
    playbackSuspended.value = userPaused.value || announcementHold.value;
  }

  /// Pause playlist dwell timers and video while an announcement is shown.
  void beginAnnouncementHold() {
    if (announcementHold.value) return;
    announcementHold.value = true;
    _cancelDwellAndWatchdog();
    _webLoadTimer?.cancel();
    _webLoadTimer = null;
  }

  /// Resume after announcement dismisses (only clears announcement hold).
  void endAnnouncementHold() {
    if (!announcementHold.value) return;
    announcementHold.value = false;
    _resumeAdvanceTimers();
  }

  /// Pauses auto-advance and in-flight slide timers (WebView initial load timeout keeps running).
  void requestPause() {
    if (!userPaused.value) {
      userPaused.value = true;
    }
    _cancelDwellAndWatchdog();
  }

  /// Resumes timers for the current slide and clears [userPaused].
  void requestResume() {
    if (!userPaused.value) return;
    userPaused.value = false;
    _resumeAdvanceTimers();
  }

  void togglePause() {
    if (userPaused.value) {
      requestResume();
    } else {
      requestPause();
    }
  }

  Future<void> goToNext() async {
    await _goToNextSlide();
  }

  Future<void> goToPrevious() async {
    await _goToPreviousSlide();
  }

  void _cancelDwellAndWatchdog() {
    _slideTimer?.cancel();
    _slideTimer = null;
    _progressWatchdog?.cancel();
    _progressWatchdog = null;
  }

  void _resumeAdvanceTimers() {
    if (!_running || playbackSuspended.value) return;
    final state = display.value;
    if (state == null || _playlist.isEmpty) return;

    final gen = state.generation;
    final item = state.item;

    if (item.mediaKind == PlaylistMediaKind.url &&
        state.isWebSlide &&
        state.urlRenderMode == UrlRenderMode.web) {
      final ms = item.durationMs <= 0 ? 10000 : item.durationMs;
      _armProgressWatchdog(gen);
      _slideTimer = Timer(Duration(milliseconds: ms), () {
        unawaited(_onDwellElapsed(gen));
      });
      return;
    }

    final ms = item.durationMs <= 0 ? 10000 : item.durationMs;
    if (item.mediaKind != PlaylistMediaKind.video && !state.isUrlVideoMode) {
      _armProgressWatchdog(gen);
    }
    _slideTimer = Timer(Duration(milliseconds: ms), () {
      unawaited(_onDwellElapsed(gen));
    });
  }

  Future<void> _goToPreviousSlide() async {
    if (!_running) return;
    _cancelTimers();

    if (_sync.commitPendingPlaylistAtBoundary()) {
      return;
    }

    if (_playlist.isEmpty) return;
    _index = (_index - 1 + _playlist.length) % _playlist.length;
    await _presentCurrent();
  }

  void _onPlaylistChanged() {
    final epoch = _sync.playbackEpoch;
    if (epoch == _lastEpoch) return;
    _lastEpoch = epoch;
    _playlist = List.unmodifiable(_sync.activeItems);
    _index = 0;
    _handledRasterFailure = false;
    _cancelTimers();
    if (!_running) return;
    if (_playlist.isEmpty) {
      display.value = null;
      return;
    }
    unawaited(_presentCurrent());
  }

  void start() {
    _lastEpoch = _sync.playbackEpoch;
    _playlist = List.unmodifiable(_sync.activeItems);
    if (_running) return;
    _running = true;
    if (_playlist.isEmpty) {
      display.value = null;
      return;
    }
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
    _progressWatchdog?.cancel();
    _progressWatchdog = null;
  }

  void _armProgressWatchdog(int generation) {
    _progressWatchdog?.cancel();
    _progressWatchdog = Timer(AppConstants.stuckSlideWatchdog, () {
      if (!_running) return;
      if (display.value?.generation != generation) return;
      unawaited(_goToNextSlide());
    });
  }

  bool _looksLikeDirectVideoUrl(String rawUrl) {
    final u = rawUrl.trim().toLowerCase();
    return RegExp(r'\.(mp4|webm|m3u8|mov)(\?|$)').hasMatch(u);
  }

  bool _shouldPreferVideoForUrl(PlaylistItem item) {
    if (item.mediaKind != PlaylistMediaKind.url) return false;
    if (item.urlPlaybackKind == UrlPlaybackKind.videoPreferred) return true;
    if (item.urlPlaybackKind == UrlPlaybackKind.webPreferred) return false;
    return _looksLikeDirectVideoUrl(item.url);
  }

  Future<void> _goToNextSlide() async {
    if (!_running) return;
    _cancelTimers();

    if (_sync.commitPendingPlaylistAtBoundary()) {
      return;
    }

    if (_playlist.isEmpty) return;
    _index = (_index + 1) % _playlist.length;
    _debug('advance -> next index=$_index len=${_playlist.length}');
    await _presentCurrent();
  }

  Future<void> _presentCurrent() async {
    if (!_running || _playlist.isEmpty) return;

    _cancelTimers();
    _handledRasterFailure = false;

    final item = _playlist[_index];
    final gen = ++_generationCounter;
    _debug(
      'present gen=$gen idx=$_index kind=${item.mediaKind.wireValue} id=${item.id} order=${item.order}',
    );

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
        urlRenderMode: _shouldPreferVideoForUrl(item)
            ? UrlRenderMode.video
            : UrlRenderMode.web,
      );

      if (!playbackSuspended.value) {
        if (display.value?.urlRenderMode == UrlRenderMode.web) {
          _webLoadTimer = Timer(const Duration(seconds: 15), () {
            if (!_running) return;
            if (display.value?.generation != gen) return;
            unawaited(onWebLoadFailed());
          });
          _armProgressWatchdog(gen);
        }
        final ms = item.durationMs <= 0 ? 10000 : item.durationMs;
        _slideTimer = Timer(Duration(milliseconds: ms), () {
          unawaited(_onDwellElapsed(gen));
        });
      }

      unawaited(_preloadNext());
      return;
    }

    display.value = PlayerDisplayState(item: item, generation: gen);

    final path = await _cache.resolveLocalPath(item.url);
    if (!_running) return;
    if (path == null) {
      _debug('present gen=$gen skipped: local path resolve failed');
      await _goToNextSlide();
      return;
    }

    display.value = PlayerDisplayState(
      item: item,
      generation: gen,
      localPath: path,
    );

    unawaited(_preloadNext());

    if (!playbackSuspended.value) {
      if (item.mediaKind != PlaylistMediaKind.video) {
        _armProgressWatchdog(gen);
      }
      final ms = item.durationMs <= 0 ? 10000 : item.durationMs;
      _slideTimer = Timer(Duration(milliseconds: ms), () {
        unawaited(_onDwellElapsed(gen));
      });
    }
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

    if (playbackSuspended.value) {
      return;
    }

    final ms = state.item.durationMs <= 0 ? 10000 : state.item.durationMs;
    final token = state.generation;
    _armProgressWatchdog(token);
    _slideTimer = Timer(Duration(milliseconds: ms), () {
      unawaited(_onDwellElapsed(token));
    });
  }

  /// WebView error / load watchdog — skip item.
  Future<void> onWebLoadFailed() async {
    if (!_running) return;
    _debug('web load failed; skipping');
    await _goToNextSlide();
  }

  /// Video finished naturally or decoder error.
  Future<void> onVideoEnded(int generation, {bool hadError = false}) async {
    if (!_running) return;
    if (display.value?.generation != generation) return;
    final state = display.value;
    final item = state?.item;
    final itemKey = '${item?.id ?? 'unknown'}|${item?.url ?? ''}';

    if (hadError &&
        state != null &&
        state.isUrlVideoMode &&
        !state.urlVideoFallbackUsed &&
        state.webUri != null) {
      _cancelTimers();
      display.value = PlayerDisplayState(
        item: state.item,
        generation: state.generation,
        webUri: state.webUri,
        urlRenderMode: UrlRenderMode.web,
        urlVideoFallbackUsed: true,
      );
      if (!playbackSuspended.value) {
        _webLoadTimer = Timer(const Duration(seconds: 15), () {
          if (!_running) return;
          if (display.value?.generation != generation) return;
          unawaited(onWebLoadFailed());
        });
        _armProgressWatchdog(generation);
        final ms = state.item.durationMs <= 0 ? 10000 : state.item.durationMs;
        _slideTimer = Timer(Duration(milliseconds: ms), () {
          unawaited(_onDwellElapsed(generation));
        });
      }
      return;
    }

    if (!hadError) {
      _videoErrorBurstCount = 0;
      _videoErrorBurstKey = null;
      _videoErrorBurstStartedAt = null;
      _debug('video ended gen=$generation -> next');
      await _goToNextSlide();
      return;
    }

    final now = DateTime.now();
    final sameKey = _videoErrorBurstKey == itemKey;
    final inWindow = _videoErrorBurstStartedAt != null &&
        now.difference(_videoErrorBurstStartedAt!) <= _videoErrorBurstWindow;
    if (sameKey && inWindow) {
      _videoErrorBurstCount++;
    } else {
      _videoErrorBurstCount = 1;
      _videoErrorBurstStartedAt = now;
      _videoErrorBurstKey = itemKey;
    }

    _debug(
      'video error gen=$generation key=$itemKey burst=$_videoErrorBurstCount window=${_videoErrorBurstWindow.inSeconds}s',
    );

    if (_videoErrorBurstCount >= _videoErrorBurstThreshold) {
      _debug(
        'video error burst threshold reached; cooling down for ${_videoErrorCooldown.inSeconds}s before retry',
      );
      _cancelTimers();
      _slideTimer = Timer(_videoErrorCooldown, () {
        if (!_running) return;
        if (display.value?.generation != generation) return;
        _debug('video cooldown elapsed; retry current item');
        unawaited(_presentCurrent());
      });
      return;
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
    userPaused.dispose();
    announcementHold.dispose();
    playbackSuspended.dispose();
    display.dispose();
  }
}
