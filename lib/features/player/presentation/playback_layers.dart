import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../data/playback_perf_telemetry.dart';

/// Maps playlist `fitMode` strings to [BoxFit] (aligned with admin CMS).
BoxFit boxFitFromPlaylistMode(String mode) {
  switch (mode.toLowerCase()) {
    case 'fit':
      return BoxFit.contain;
    case 'stretch':
      return BoxFit.fill;
    case 'fill':
    default:
      return BoxFit.cover;
  }
}

/// Cached image slide (local file path).
class ImageSlideLayer extends StatelessWidget {
  const ImageSlideLayer({
    super.key,
    required this.path,
    required this.fit,
    required this.onDecodeFailed,
  });

  final String path;
  final BoxFit fit;
  final VoidCallback onDecodeFailed;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(
        child: Image.file(
          File(path),
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              onDecodeFailed();
            });
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

/// Full-screen video from a cached file; notifies when playback completes or errors.
class VideoSlideLayer extends StatefulWidget {
  const VideoSlideLayer({
    super.key,
    this.path,
    this.networkUri,
    required this.fit,
    required this.muted,
    required this.generation,
    required this.onEnded,
    this.playbackPaused,
  }) : assert(
         (path != null && networkUri == null) ||
             (path == null && networkUri != null),
         'Provide exactly one of path or networkUri.',
       );

  final String? path;
  final Uri? networkUri;
  final BoxFit fit;
  final bool muted;
  final int generation;
  final Future<void> Function(int generation, {bool hadError}) onEnded;

  /// When true, the decoder should stay paused (kiosk manual pause).
  final ValueListenable<bool>? playbackPaused;

  @override
  State<VideoSlideLayer> createState() => _VideoSlideLayerState();
}

class _VideoSlideLayerState extends State<VideoSlideLayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _notified = false;
  VoidCallback? _pausedListener;
  bool _handlingError = false;
  bool _firstFrameSeen = false;
  int _restartAttempts = 0;
  DateTime? _playStartedAt;
  Stopwatch? _profileFromInit;
  int? _profileInitDoneMs;
  bool _perfEmitted = false;

  static const int _maxDecoderRestarts = 1;
  static const Duration _earlyFailureWindow = Duration(milliseconds: 1800);
  static const Duration _minPlaybackBeforeEnd = Duration(milliseconds: 700);
  static const Duration _endEpsilon = Duration(milliseconds: 140);

  void _log(String message) {
    if (!kDebugMode) return;
    debugPrint('VideoSlideLayer[g=${widget.generation}]: $message');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attachPausedListener();
    unawaited(_init());
  }

  @override
  void didUpdateWidget(VideoSlideLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackPaused != widget.playbackPaused) {
      final oldL = oldWidget.playbackPaused;
      final fn = _pausedListener;
      if (oldL != null && fn != null) {
        oldL.removeListener(fn);
      }
      _pausedListener = null;
      _attachPausedListener();
      _applyPausedFromNotifier();
    }
  }

  void _attachPausedListener() {
    final listenable = widget.playbackPaused;
    if (listenable == null) return;
    void listener() {
      if (!mounted) return;
      _applyPausedFromNotifier();
    }

    _pausedListener = listener;
    listenable.addListener(listener);
  }

  void _detachPausedListener() {
    final listenable = widget.playbackPaused;
    final fn = _pausedListener;
    if (listenable != null && fn != null) {
      listenable.removeListener(fn);
    }
    _pausedListener = null;
  }

  void _applyPausedFromNotifier() {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _notified) return;
    final paused = widget.playbackPaused?.value ?? false;
    if (paused) {
      unawaited(c.pause());
    } else {
      unawaited(c.play());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _notified) return;
    if (state == AppLifecycleState.resumed) {
      if (!(widget.playbackPaused?.value ?? false)) {
        unawaited(c.play());
      }
    } else {
      unawaited(c.pause());
    }
  }

  Future<void> _init() async {
    _log('init start source=${widget.path ?? widget.networkUri}');
    _profileFromInit = Stopwatch()..start();
    _profileInitDoneMs = null;
    _perfEmitted = false;
    final c = widget.path != null
        ? VideoPlayerController.file(File(widget.path!))
        : VideoPlayerController.networkUrl(widget.networkUri!);
    try {
      await c.initialize();
      _profileInitDoneMs = _profileFromInit?.elapsedMilliseconds;
      if (!mounted) {
        await c.dispose();
        return;
      }
      await c.setLooping(false);
      await c.setVolume(widget.muted ? 0 : 1);
      _controller = c;
      c.addListener(_onTick);
      setState(() {});
      await c.play();
      _playStartedAt = DateTime.now();
      _firstFrameSeen = false;
      _handlingError = false;
      _log(
        'init ok durationMs=${c.value.duration.inMilliseconds} size=${c.value.size.width}x${c.value.size.height}',
      );
      _applyPausedFromNotifier();
    } catch (e) {
      await c.dispose();
      if (!mounted || _notified) return;
      _log('init failed error=$e');
      await _retryOrFinishOnError();
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || _notified || !mounted) return;
    final v = c.value;
    if (v.hasError) {
      _log('tick hasError desc=${v.errorDescription}');
      unawaited(_retryOrFinishOnError());
      return;
    }
    if (!v.isInitialized || v.duration == Duration.zero) return;

    if (!_firstFrameSeen && v.position > const Duration(milliseconds: 50)) {
      _firstFrameSeen = true;
      _log('first frame at ${v.position.inMilliseconds}ms');
      _emitPerfOnce();
    }

    final elapsedEnough = _playStartedAt != null &&
        DateTime.now().difference(_playStartedAt!) >= _minPlaybackBeforeEnd;
    final nearEnd = v.position >= (v.duration - _endEpsilon);
    if (elapsedEnough && nearEnd) {
      _log(
        'natural end reached position=${v.position.inMilliseconds} duration=${v.duration.inMilliseconds}',
      );
      _finish(hadError: false);
    }
  }

  void _emitPerfOnce() {
    if (_perfEmitted) return;
    final sw = _profileFromInit;
    final initMs = _profileInitDoneMs;
    if (sw == null || initMs == null) return;
    _perfEmitted = true;
    PlaybackPerfTelemetry.videoLayerInit(
      initMs: initMs,
      firstFrameMs: sw.elapsedMilliseconds,
      networkSource: widget.networkUri != null,
    );
  }

  Future<void> _retryOrFinishOnError() async {
    if (!mounted || _notified || _handlingError) return;
    _handlingError = true;
    final startedAt = _playStartedAt;
    final earlyFailure = startedAt != null &&
        DateTime.now().difference(startedAt) < _earlyFailureWindow;
    if (earlyFailure && _restartAttempts < _maxDecoderRestarts) {
      _restartAttempts++;
      _log(
        'early failure; restart attempt $_restartAttempts/$_maxDecoderRestarts',
      );
      final old = _controller;
      if (old != null) {
        old.removeListener(_onTick);
        await old.dispose();
      }
      _controller = null;
      if (mounted) {
        setState(() {});
      }
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted || _notified) return;
      _handlingError = false;
      await _init();
      return;
    }
    _log('error not recoverable; finishing with hadError=true');
    _handlingError = false;
    _finish(hadError: true);
  }

  void _finish({required bool hadError}) {
    if (_notified) return;
    _notified = true;
    if (!_perfEmitted &&
        _profileInitDoneMs != null &&
        _profileFromInit != null) {
      _perfEmitted = true;
      PlaybackPerfTelemetry.videoLayerInit(
        initMs: _profileInitDoneMs!,
        firstFrameMs: _profileFromInit!.elapsedMilliseconds,
        networkSource: widget.networkUri != null,
      );
    }
    final c = _controller;
    if (c != null) {
      c.removeListener(_onTick);
      unawaited(c.pause());
    }
    _log('finish callback hadError=$hadError');
    unawaited(widget.onEnded(widget.generation, hadError: hadError));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachPausedListener();
    final c = _controller;
    if (c != null) {
      c.removeListener(_onTick);
      unawaited(c.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    final size = c.value.size;
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) {
      return const ColoredBox(color: Colors.black);
    }
    final ar = w / h;

    Widget core() => VideoPlayer(c);

    final Widget framed;
    if (widget.fit == BoxFit.contain) {
      framed = Center(
        child: AspectRatio(
          aspectRatio: ar == 0 ? 16 / 9 : ar,
          child: core(),
        ),
      );
    } else if (widget.fit == BoxFit.cover) {
      framed = ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            child: SizedBox(width: w, height: h, child: core()),
          ),
        ),
      );
    } else if (widget.fit == BoxFit.fill) {
      framed = SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(width: w, height: h, child: core()),
        ),
      );
    } else {
      framed = Center(
        child: AspectRatio(
          aspectRatio: ar == 0 ? 16 / 9 : ar,
          child: core(),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: framed,
    );
  }
}

/// URL slide using WebView (strict load handling via controller callbacks).
class WebSlideLayer extends StatefulWidget {
  const WebSlideLayer({
    super.key,
    required this.uri,
    required this.onLoadSuccess,
    required this.onLoadFailed,
  });

  final Uri uri;
  final VoidCallback onLoadSuccess;
  final VoidCallback onLoadFailed;

  @override
  State<WebSlideLayer> createState() => _WebSlideLayerState();
}

class _WebSlideLayerState extends State<WebSlideLayer> {
  WebViewController? _controller;
  bool _successSent = false;
  bool _failSent = false;
  Timer? _watchdog;
  int _reloadAttempts = 0;
  static const int _maxReloads = 1;

  @override
  void initState() {
    super.initState();
    _createController();
    _armWatchdog();
  }

  @override
  void didUpdateWidget(WebSlideLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) {
      _reloadAttempts = 0;
      _successSent = false;
      _failSent = false;
      _watchdog?.cancel();
      final c = _controller;
      if (c != null) {
        unawaited(c.loadRequest(widget.uri));
      }
      _armWatchdog();
    }
  }

  void _createController() {
    final wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _deliverSuccess(),
          onWebResourceError: (_) => _maybeReloadOrFail(),
        ),
      );
    _controller = wc;
    unawaited(wc.loadRequest(widget.uri));
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 15), () {
      if (!mounted || _successSent || _failSent) return;
      _maybeReloadOrFail();
    });
  }

  void _maybeReloadOrFail() {
    if (!mounted || _successSent || _failSent) return;
    if (_reloadAttempts < _maxReloads) {
      _reloadAttempts++;
      final c = _controller;
      if (c != null) {
        unawaited(c.reload());
      }
      _armWatchdog();
      return;
    }
    _deliverFailure();
  }

  void _deliverSuccess() {
    if (_successSent || _failSent || !mounted) return;
    _successSent = true;
    _watchdog?.cancel();
    widget.onLoadSuccess();
  }

  void _deliverFailure() {
    if (_successSent || _failSent || !mounted) return;
    _failSent = true;
    _watchdog?.cancel();
    widget.onLoadFailed();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) {
      return const ColoredBox(color: Colors.black);
    }
    return ColoredBox(
      color: Colors.black,
      child: WebViewWidget(controller: c),
    );
  }
}
