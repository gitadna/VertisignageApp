import 'package:flutter/material.dart';

import '../../../core/di/injection.dart';
import '../../player/presentation/playback_layers.dart';
import '../../player/presentation/kiosk_video_backend/kiosk_video_view.dart';
import '../data/realtime_push_notifier.dart';

/// Full-screen takeover for an active realtime content push.
///
/// Sits above the playlist and announcement layers in `PlayerScreen`. While
/// active, it covers everything beneath it; when the underlying notifier
/// reports no active push, this widget renders an empty `SizedBox` and the
/// playlist becomes visible again.
class RealtimePushLayer extends StatelessWidget {
  const RealtimePushLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sl<RealtimePushNotifier>(),
      builder: (context, _) {
        final state = sl<RealtimePushNotifier>().active;
        if (state == null) return const SizedBox.shrink();

        return Positioned.fill(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            removeLeft: true,
            removeRight: true,
            child: _RealtimePushFill(
              key: ValueKey(
                  'realtime-push-${state.pushId}-${state.restartTick}'),
              state: state,
            ),
          ),
        );
      },
    );
  }
}

class _RealtimePushFill extends StatefulWidget {
  const _RealtimePushFill({super.key, required this.state});

  final RealtimePushState state;

  @override
  State<_RealtimePushFill> createState() => _RealtimePushFillState();
}

class _RealtimePushFillState extends State<_RealtimePushFill> {
  bool _videoFailed = false;
  bool _webFailed = false;
  String? _videoError;
  final ValueNotifier<bool> _paused = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    // Video initialization happens inside [KioskVideoView].
    _paused.value = widget.state.isPaused;
  }

  @override
  void didUpdateWidget(covariant _RealtimePushFill oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged = oldWidget.state.pushId != widget.state.pushId ||
        oldWidget.state.mediaUrl != widget.state.mediaUrl ||
        oldWidget.state.contentKind != widget.state.contentKind;
    if (identityChanged) {
      _videoFailed = false;
      _webFailed = false;
      _videoError = null;
    }

    if (oldWidget.state.isPaused != widget.state.isPaused &&
        widget.state.contentKind == RealtimePushContentKind.video) {
      // Handled by [KioskVideoView] via playbackPaused.
      _paused.value = widget.state.isPaused;
    }

    if (!identityChanged &&
        oldWidget.state.restartTick != widget.state.restartTick &&
        widget.state.contentKind == RealtimePushContentKind.video) {
      // Restart is handled by rebuilding with a new key.
    }
  }

  @override
  void dispose() {
    _paused.dispose();
    super.dispose();
  }

  BoxFit _boxFit() {
    switch (widget.state.fitMode) {
      case RealtimePushFitMode.fill:
        return BoxFit.cover;
      case RealtimePushFitMode.stretch:
        return BoxFit.fill;
      case RealtimePushFitMode.fit:
        return BoxFit.contain;
    }
  }

  Widget _captionStrip() {
    final caption = widget.state.caption?.trim();
    if (caption == null || caption.isEmpty) return const SizedBox.shrink();
    return Material(
      color: Colors.black,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Text(
          caption,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ),
    );
  }

  Widget _wrapWithCaption(Widget media) {
    final caption = widget.state.caption?.trim();
    final hasCaption = caption != null && caption.isNotEmpty;
    return ColoredBox(
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: media),
          if (hasCaption) _captionStrip(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (widget.state.contentKind) {
      RealtimePushContentKind.text => _buildTextSlide(),
      RealtimePushContentKind.image => _buildImageSlide(),
      RealtimePushContentKind.video => _buildVideoSlide(),
      RealtimePushContentKind.url => _buildUrlSlide(),
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        body,
        if (widget.state.isPaused)
          Positioned(
            right: 20,
            bottom: 20,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(
                  'Paused',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTextSlide() {
    final text = widget.state.text?.trim() ?? '';
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
          child: Text(
            text.isEmpty ? 'Realtime push' : text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageSlide() {
    final url = widget.state.mediaUrl;
    if (url == null || url.isEmpty) return _buildErrorFallback();
    return _wrapWithCaption(
      ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(
          child: Image.network(
            url,
            fit: _boxFit(),
            alignment: Alignment.center,
            errorBuilder: (_, _, _) => _buildErrorFallback(),
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
      ),
    );
  }

  Widget _buildVideoSlide() {
    final url = widget.state.mediaUrl;
    if (url == null || url.isEmpty || _videoFailed) {
      return _buildErrorFallback();
    }
    return _wrapWithCaption(
      KioskVideoView(
        key: ValueKey('push-video-${widget.state.pushId}-${widget.state.restartTick}'),
        networkUri: Uri.parse(url),
        fit: _boxFit(),
        looping: true,
        muted: widget.state.muted,
        playbackPaused: _paused,
        onError: (e) {
          if (!mounted) return;
          _videoError = e;
          setState(() => _videoFailed = true);
        },
      ),
    );
  }

  Widget _buildUrlSlide() {
    final url = widget.state.mediaUrl;
    if (url == null || url.isEmpty || _webFailed) {
      return _buildErrorFallback();
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return _buildErrorFallback();
    }
    return _wrapWithCaption(
      ColoredBox(
        color: Colors.black,
        child: WebSlideLayer(
          uri: uri,
          onLoadSuccess: () {},
          onLoadFailed: () {
            if (!mounted) return;
            setState(() => _webFailed = true);
          },
        ),
      ),
    );
  }

  Widget _buildErrorFallback() {
    final caption = widget.state.caption?.trim();
    final fallback = (caption != null && caption.isNotEmpty)
        ? caption
        : 'Realtime push';
    final err = _videoError?.trim();
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined,
                  color: Colors.white70, size: 64),
              const SizedBox(height: 16),
              Text(
                (err == null || err.isEmpty) ? fallback : '$fallback\n\n[$err]',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
