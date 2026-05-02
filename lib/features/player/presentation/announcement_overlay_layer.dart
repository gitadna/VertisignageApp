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
        if (!n.isActive) {
          return const SizedBox.shrink();
        }

        return Positioned.fill(
          child: _AnnouncementMediaFill(
            key: ValueKey(
              '${n.announcementId}-${n.mediaKind}-${n.mediaUrl}',
            ),
            kind: n.mediaKind,
            url: n.mediaUrl,
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
      if (mounted) sl<AnnouncementOverlayNotifier>().dismissManual();
      return;
    }
    final c = VideoPlayerController.networkUrl(uri);
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      await c.setLooping(false);
      await c.setVolume(1);
      _video = c;
      c.addListener(_onVideoTick);
      setState(() {});
      await c.play();
    } catch (_) {
      await c.dispose();
      if (mounted) sl<AnnouncementOverlayNotifier>().dismissManual();
    }
  }

  void _onVideoTick() {
    final c = _video;
    if (c == null || !mounted) return;
    final v = c.value;
    if (v.hasError) {
      c.removeListener(_onVideoTick);
      sl<AnnouncementOverlayNotifier>().dismissManual();
      return;
    }
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
        url.isNotEmpty) {
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
              child: SizedBox(
                width: w,
                height: h,
                child: VideoPlayer(c),
              ),
            ),
          ),
        );
      }
      return const ColoredBox(color: Colors.black);
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

    return const ColoredBox(color: Colors.black);
  }
}
