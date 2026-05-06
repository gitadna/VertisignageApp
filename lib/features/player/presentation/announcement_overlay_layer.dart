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
                  title: n.title,
                  body: n.body,
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
    required this.title,
    required this.body,
  });

  final AnnouncementMediaKind kind;
  final String? url;
  final String title;
  final String? body;

  @override
  State<_AnnouncementMediaFill> createState() => _AnnouncementMediaFillState();
}

class _AnnouncementMediaFillState extends State<_AnnouncementMediaFill> {
  VideoPlayerController? _video;
  bool _videoFailed = false;
  int _retryTick = 0;

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
  }

  String _effectiveUrl(String url) {
    if (_retryTick == 0) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final qp = Map<String, String>.from(uri.queryParameters);
    qp['_retry'] = _retryTick.toString();
    return uri.replace(queryParameters: qp).toString();
  }

  void _retryMedia() {
    setState(() {
      _retryTick++;
      _videoFailed = false;
    });
    if (widget.kind == AnnouncementMediaKind.video &&
        widget.url != null &&
        widget.url!.isNotEmpty) {
      final c = _video;
      if (c != null) {
        c.removeListener(_onVideoTick);
        unawaited(c.dispose());
        _video = null;
      }
      unawaited(_initVideo());
    }
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
          return const _AnnouncementStateCard(
            icon: Icons.broken_image_outlined,
            title: 'Media unavailable',
            message: 'Video metadata is invalid or empty.',
          );
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
      return _AnnouncementStateCard(
        icon: Icons.error_outline,
        title: 'Could not play video',
        message: url,
        onRetry: _retryMedia,
      );
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
            errorBuilder: (_, _, _) => _AnnouncementStateCard(
              icon: Icons.broken_image_outlined,
              title: 'Could not load image',
              message: url,
              onRetry: _retryMedia,
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

    return _AnnouncementTextFill(title: widget.title, body: widget.body);
  }
}

class _AnnouncementTextFill extends StatelessWidget {
  const _AnnouncementTextFill({required this.title, this.body});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final effectiveTitle = title.trim().isEmpty ? 'Announcement' : title.trim();
    final effectiveBody = body?.trim();
    return ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  effectiveTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
              if (effectiveBody != null && effectiveBody.isNotEmpty) ...[
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    effectiveBody,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementStateCard extends StatelessWidget {
  const _AnnouncementStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                child: Row(
                  children: [
                    Icon(icon, color: Colors.white70, size: 32),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            message,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          if (onRetry != null) ...[
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: onRetry,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ],
                      ),
                    ),
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
