import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/config/environment_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/websocket/realtime_client.dart';
import '../../../services/device_service.dart';
import '../../../services/token_store.dart';
import '../../../models/playlist_item.dart';
import '../data/emergency_overlay_notifier.dart';
import '../data/playlist_sync_service.dart';
import '../data/realtime_dispatcher.dart';
import 'playback_layers.dart';
import 'player_controller.dart';

/// Full-screen playback (images, cached video, URL WebViews) with emergency overlay.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_bootstrapThenStart());
  }

  Future<void> _bootstrapThenStart() async {
    await sl<PlaylistSyncService>().bootstrap();
    if (!mounted) return;

    sl<RealtimeDispatcher>().ensureStarted();
    unawaited(sl<RealtimeClient>().connect());

    if (!mounted) return;

    if (Platform.isAndroid &&
        sl<EnvironmentConfig>().kioskLockTask &&
        sl<TokenStore>().hasPairedDevice) {
      unawaited(sl<DeviceService>().setLockTaskEnabled(true));
    }

    widget.controller.start();
  }

  @override
  void dispose() {
    sl<RealtimeDispatcher>().dispose();
    sl<RealtimeClient>().disconnect();
    widget.controller.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Scaffold(
          backgroundColor: Colors.black,
          body: ValueListenableBuilder<PlayerDisplayState?>(
            valueListenable: widget.controller.display,
            builder: (context, state, _) {
              if (state == null) {
                return const ColoredBox(color: Colors.black);
              }

              final fade = state.item.transition == 'fade';
              final duration =
                  fade ? const Duration(milliseconds: 420) : Duration.zero;

              return AnimatedSwitcher(
                duration: duration,
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  if (!fade) return child;
                  return FadeTransition(opacity: animation, child: child);
                },
                child: KeyedSubtree(
                  key: ValueKey(
                    '${state.generation}-${state.item.id}-${state.localPath ?? state.webUri}',
                  ),
                  child: _buildSlide(state),
                ),
              );
            },
          ),
        ),
        ListenableBuilder(
          listenable: sl<EmergencyOverlayNotifier>(),
          builder: (context, _) {
            final overlay = sl<EmergencyOverlayNotifier>();
            if (!overlay.isActive) {
              return const SizedBox.shrink();
            }
            return Positioned.fill(
              child: Material(
                color: Colors.black.withOpacity(0.85),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          overlay.title ?? 'Alert',
                          style:
                              Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          overlay.message ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSlide(PlayerDisplayState state) {
    final item = state.item;
    final ctrl = widget.controller;

    if (state.isWebSlide && state.webUri != null) {
      return WebSlideLayer(
        uri: state.webUri!,
        onLoadSuccess: ctrl.onWebLoadSuccess,
        onLoadFailed: ctrl.onWebLoadFailed,
      );
    }

    final path = state.localPath;
    if (path == null) {
      return const ColoredBox(color: Colors.black);
    }

    switch (item.mediaKind) {
      case PlaylistMediaKind.url:
        return const ColoredBox(color: Colors.black);
      case PlaylistMediaKind.video:
        return VideoSlideLayer(
          path: path,
          muted: item.muted,
          generation: state.generation,
          onEnded: ctrl.onVideoEnded,
        );
      case PlaylistMediaKind.image:
        return ImageSlideLayer(
          path: path,
          onDecodeFailed: ctrl.onRasterDisplayFailed,
        );
    }
  }
}
