import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Cached image slide (local file path).
class ImageSlideLayer extends StatelessWidget {
  const ImageSlideLayer({
    super.key,
    required this.path,
    required this.onDecodeFailed,
  });

  final String path;
  final VoidCallback onDecodeFailed;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  onDecodeFailed();
                });
                return const SizedBox.shrink();
              },
            ),
          );
        },
      ),
    );
  }
}

/// Full-screen video from a cached file; notifies when playback completes or errors.
class VideoSlideLayer extends StatefulWidget {
  const VideoSlideLayer({
    super.key,
    required this.path,
    required this.muted,
    required this.generation,
    required this.onEnded,
  });

  final String path;
  final bool muted;
  final int generation;
  final Future<void> Function(int generation, {bool hadError}) onEnded;

  @override
  State<VideoSlideLayer> createState() => _VideoSlideLayerState();
}

class _VideoSlideLayerState extends State<VideoSlideLayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _notified = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_init());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _notified) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(c.play());
    } else {
      unawaited(c.pause());
    }
  }

  Future<void> _init() async {
    final c = VideoPlayerController.file(File(widget.path));
    try {
      await c.initialize();
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
    } catch (_) {
      await c.dispose();
      if (!mounted || _notified) return;
      _notified = true;
      unawaited(widget.onEnded(widget.generation, hadError: true));
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || _notified || !mounted) return;
    final v = c.value;
    if (v.hasError) {
      _finish(hadError: true);
      return;
    }
    if (!v.isInitialized || v.duration == Duration.zero) return;
    if (v.position >= v.duration - const Duration(milliseconds: 120)) {
      _finish(hadError: false);
    }
  }

  void _finish({required bool hadError}) {
    if (_notified) return;
    _notified = true;
    final c = _controller;
    if (c != null) {
      c.removeListener(_onTick);
      unawaited(c.pause());
    }
    unawaited(widget.onEnded(widget.generation, hadError: hadError));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio:
              c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
      ),
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
