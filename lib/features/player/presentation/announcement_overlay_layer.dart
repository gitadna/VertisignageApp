import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/di/injection.dart';
import '../data/announcement_overlay_notifier.dart';

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
          child: _AnnouncementMediaFill(
            key: ValueKey(
              '${n.announcementId}-${n.mediaKind}-${n.mediaUrl}',
            ),
            kind: n.mediaKind,
            url: n.mediaUrl,
            title: n.title,
            body: n.body,
            untilDismissed: n.untilDismissed,
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
    required this.title,
    required this.body,
    required this.untilDismissed,
  });

  final AnnouncementMediaKind kind;
  final String? url;
  final String title;
  final String? body;
  final bool untilDismissed;

  @override
  State<_AnnouncementMediaFill> createState() => _AnnouncementMediaFillState();
}

class _AnnouncementMediaFillState extends State<_AnnouncementMediaFill> {
  VideoPlayerController? _video;
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.kind == AnnouncementMediaKind.video &&
        widget.url != null &&
        widget.url!.isNotEmpty) {
      unawaited(_initVideo());
    }
  }

  Future<void> _initVideo() async {
    final uri = Uri.tryParse(widget.url!);
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
      await c.setLooping(widget.untilDismissed);
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

  void _onVideoTick() {
    final c = _video;
    if (c == null || !mounted) return;
    final v = c.value;
    if (v.hasError) {
      c.removeListener(_onVideoTick);
      setState(() => _videoFailed = true);
      return;
    }
    if (widget.untilDismissed) return;
    if (!v.isInitialized || v.duration == Duration.zero) return;
    if (v.position >= v.duration - const Duration(milliseconds: 120)) {
      c.removeListener(_onVideoTick);
      sl<AnnouncementOverlayNotifier>().dismissManual();
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
          return _AnnouncementFallback(
            title: widget.title,
            body: widget.body,
          );
        }
        return ColoredBox(
          color: Colors.black,
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
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

    if (widget.kind == AnnouncementMediaKind.image &&
        url != null &&
        url.isNotEmpty) {
      return ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _AnnouncementFallback(
              title: widget.title,
              body: widget.body,
            ),
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

    return _AnnouncementFallback(
      title: widget.title,
      body: widget.body,
    );
  }
}

class _AnnouncementFallback extends StatelessWidget {
  const _AnnouncementFallback({
    required this.title,
    required this.body,
  });

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.campaign_outlined,
                      color: Colors.white70,
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title.trim().isEmpty ? 'Announcement' : title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (body != null && body!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        body!.trim(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 18,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
