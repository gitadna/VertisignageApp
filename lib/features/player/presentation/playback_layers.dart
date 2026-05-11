import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/logging/kiosk_log.dart';
import 'kiosk_video_backend/kiosk_video_view.dart';

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
  bool _notified = false;

  void _log(String message) {
    if (!kDebugMode) return;
    debugPrint('VideoSlideLayer[g=${widget.generation}]: $message');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(VideoSlideLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  void _finish({required bool hadError}) {
    if (_notified) return;
    _notified = true;
    _log('finish callback hadError=$hadError');
    unawaited(widget.onEnded(widget.generation, hadError: hadError));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KioskVideoView(
      filePath: widget.path,
      networkUri: widget.networkUri,
      fit: widget.fit,
      looping: false,
      muted: widget.muted,
      playbackPaused: widget.playbackPaused,
      onEnded: () => _finish(hadError: false),
      onError: (_) => _finish(hadError: true),
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
      KioskLog.event(
        'player_web',
        'web_slide_reload',
        level: 'warn',
        meta: <String, Object?>{
          'attempt': _reloadAttempts,
          'host': widget.uri.host,
          'scheme': widget.uri.scheme,
        },
      );
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
    KioskLog.event(
      'player_web',
      'web_slide_failed',
      level: 'warn',
      meta: <String, Object?>{
        'host': widget.uri.host,
        'scheme': widget.uri.scheme,
        'reloads': _reloadAttempts,
      },
    );
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
