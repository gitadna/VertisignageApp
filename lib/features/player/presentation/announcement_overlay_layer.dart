import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/di/injection.dart';
import '../data/announcement_overlay_notifier.dart';
import 'playback_layers.dart';

/// Full-screen announcement media only (no titles or footer chrome).
class AnnouncementOverlayLayer extends StatelessWidget {
  const AnnouncementOverlayLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sl<AnnouncementOverlayNotifier>(),
      builder: (context, _) {
        final n = sl<AnnouncementOverlayNotifier>();
        if (!n.isActive || n.mode != AnnouncementRenderMode.overlay) {
          return const SizedBox.shrink();
        }

        return Positioned.fill(
          child: Builder(
            builder: (ctx) {
              return MediaQuery.removePadding(
                context: ctx,
                removeTop: true,
                removeBottom: true,
                removeLeft: true,
                removeRight: true,
                child: _AnnouncementMediaFill(
                  key: ValueKey(
                    '${n.announcementId}-${n.mediaKind}-${n.mediaUrl}',
                  ),
                  kind: n.mediaKind,
                  url: n.mediaUrl,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _AnnouncementMediaFill extends StatefulWidget {
  const _AnnouncementMediaFill({
    super.key,
    required this.kind,
    required this.url,
  });

  final AnnouncementMediaKind kind;
  final String? url;

  @override
  State<_AnnouncementMediaFill> createState() => _AnnouncementMediaFillState();
}

class _AnnouncementMediaFillState extends State<_AnnouncementMediaFill> {
  VideoPlayerController? _video;
  bool _videoFailed = false;
  bool _webFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.kind == AnnouncementMediaKind.video &&
        widget.url != null &&
        widget.url!.isNotEmpty) {
      unawaited(_initVideo());
    }
    if (widget.kind == AnnouncementMediaKind.url &&
        widget.url != null &&
        widget.url!.isNotEmpty) {
      // WebView widget is built directly; no async init required here.
    }
  }

  Future<void> _initVideo() async {
    final effectiveUrl = _effectiveUrl(widget.url!);
    final uri = Uri.tryParse(effectiveUrl);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      if (mounted) {
        setState(() => _videoFailed = true);
      }
      return;
    }
    final c = VideoPlayerController.networkUrl(uri);
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      await c.setLooping(true);
      await c.setVolume(1);
      _video = c;
      c.addListener(_onVideoTick);
      setState(() {});
      await c.play();
    } catch (_) {
      await c.dispose();
      if (mounted) {
        setState(() => _videoFailed = true);
      }
    }
  }

  @override
  void didUpdateWidget(covariant _AnnouncementMediaFill oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged = oldWidget.url != widget.url || oldWidget.kind != widget.kind;
    if (!sourceChanged) return;
    _videoFailed = false;
    _webFailed = false;
    final c = _video;
    if (c != null) {
      c.removeListener(_onVideoTick);
      unawaited(c.dispose());
      _video = null;
    }
    if (widget.kind == AnnouncementMediaKind.video &&
        widget.url != null &&
        widget.url!.isNotEmpty) {
      unawaited(_initVideo());
    }
    if (widget.kind == AnnouncementMediaKind.url &&
        widget.url != null &&
        widget.url!.isNotEmpty) {
      // WebView widget is built directly; no async init required.
    }
  }

  String _effectiveUrl(String url) {
    return url;
  }

  void _onVideoTick() {
    final c = _video;
    if (c == null || !mounted) return;
    final v = c.value;
    if (v.hasError) {
      c.removeListener(_onVideoTick);
      setState(() => _videoFailed = true);
    }
  }

  @override
  void dispose() {
    final c = _video;
    if (c != null) {
      c.removeListener(_onVideoTick);
      unawaited(c.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;

    if (widget.kind == AnnouncementMediaKind.video &&
        url != null &&
        url.isNotEmpty &&
        !_videoFailed) {
      final c = _video;
      if (c != null && c.value.isInitialized) {
        final sz = c.value.size;
        final w = sz.width;
        final h = sz.height;
        if (w <= 0 || h <= 0) {
          return const ColoredBox(color: Colors.black);
        }
        return ColoredBox(
          color: Colors.black,
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.center,
              child: SizedBox(
                width: w,
                height: h,
                child: VideoPlayer(c),
              ),
            ),
          ),
        );
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      );
    }
    if (widget.kind == AnnouncementMediaKind.video &&
        url != null &&
        url.isNotEmpty &&
        _videoFailed) {
      return const ColoredBox(color: Colors.black);
    }

    if (widget.kind == AnnouncementMediaKind.image &&
        url != null &&
        url.isNotEmpty) {
      final effectiveUrl = _effectiveUrl(url);
      return ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(
          child: Image.network(
            effectiveUrl,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  color: Theme.of(ctx).colorScheme.primary,
                ),
              );
            },
          ),
        ),
      );
    }

    if (widget.kind == AnnouncementMediaKind.url &&
        url != null &&
        url.isNotEmpty &&
        !_webFailed) {
      final uri = Uri.tryParse(_effectiveUrl(url));
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
        return const ColoredBox(color: Colors.black);
      }
      return WebSlideLayer(
        uri: uri,
        onLoadSuccess: () {},
        onLoadFailed: () {
          if (!mounted) return;
          setState(() => _webFailed = true);
        },
      );
    }

    return const ColoredBox(color: Colors.black);
  }
}
