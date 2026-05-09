import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/config/environment_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/vertisignage_theme_extension.dart';
import '../../../services/device_service.dart';
import '../../../services/token_store.dart';
import '../../../models/playlist_item.dart';
import '../data/media_cache_service.dart';
import '../data/playlist_sync_service.dart';
import 'announcement_overlay_layer.dart';
import 'announcement_ticker_layer.dart';
import 'emergency_overlay_layer.dart';
import 'playback_layers.dart';
import 'player_controller.dart';
import 'player_kiosk_overlay.dart';
import '../../realtime_push/presentation/realtime_push_layer.dart';
import '../../voice_broadcast/presentation/voice_takeover_overlay.dart';

const Duration _kPlaylistSwitchDuration = Duration(milliseconds: 450);

Widget _playlistSlideTransition({
  required String transition,
  required Animation<double> animation,
  required Widget child,
}) {
  switch (transition.toLowerCase()) {
    case 'fade':
      return FadeTransition(opacity: animation, child: child);
    case 'slideup':
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      );
    case 'slidedown':
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      );
    case 'slideleft':
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      );
    case 'slideright':
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      );
    case 'zoom':
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1).animate(animation),
          alignment: Alignment.center,
          child: child,
        ),
      );
    default:
      return FadeTransition(opacity: animation, child: child);
  }
}

/// Full-screen playback (images, cached video, URL WebViews) with emergency overlay.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const Duration _overlayHideDelay = Duration(milliseconds: 3500);

  bool _overlayVisible = false;
  Timer? _overlayHideTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrapThenStart());
  }

  Future<void> _bootstrapThenStart() async {
    await sl<PlaylistSyncService>().bootstrap();
    if (!mounted) return;

    if (Platform.isAndroid &&
        sl<EnvironmentConfig>().kioskLockTask &&
        sl<TokenStore>().hasPairedDevice) {
      final device = sl<DeviceService>();
      if (await device.isDeviceOwner()) {
        unawaited(device.applyKioskPoliciesAndEnter());
      }
    }

    widget.controller.start();
  }

  @override
  void dispose() {
    _overlayHideTimer?.cancel();
    // Fleet WebSocket lifecycle is owned by [FleetRealtimeCoordinator], not this route.
    widget.controller.stop();
    super.dispose();
  }

  void _onSurfacePointer() {
    if (!mounted) return;
    if (!_overlayVisible) {
      setState(() => _overlayVisible = true);
    }
    _scheduleOverlayHide();
  }

  void _scheduleOverlayHide() {
    _overlayHideTimer?.cancel();
    _overlayHideTimer = Timer(_overlayHideDelay, () {
      if (!mounted) return;
      setState(() => _overlayVisible = false);
    });
  }

  void _onOverlayInteraction() {
    _scheduleOverlayHide();
  }

  Future<void> _clearCache() async {
    final sync = sl<PlaylistSyncService>();
    await sl<MediaCacheService>().clearDiskCache();
    if (!mounted) return;
    unawaited(sync.sync());
  }

  Future<void> _pairAgain() async {
    final env = sl<EnvironmentConfig>();
    if (Platform.isAndroid && env.kioskLockTask) {
      final device = sl<DeviceService>();
      if (await device.isDeviceOwner()) {
        unawaited(device.exitKioskAndClearPolicies());
      }
    }
    await sl<TokenStore>().invalidateDeviceSession();
  }

  Future<void> _resetApp() async {
    final env = sl<EnvironmentConfig>();
    if (Platform.isAndroid && env.kioskLockTask) {
      final device = sl<DeviceService>();
      if (await device.isDeviceOwner()) {
        unawaited(device.exitKioskAndClearPolicies());
      }
    }
    await sl<MediaCacheService>().clearDiskCache();
    await sl<TokenStore>().invalidateDeviceSession();
    if (!mounted) return;
    if (Platform.isAndroid) {
      await sl<DeviceService>().restartApplication();
    }
  }

  Future<void> _showStartupDiagnostics() async {
    if (!Platform.isAndroid) return;
    final device = sl<DeviceService>();
    final ignoringBatteryOptimization = await device
        .isIgnoringBatteryOptimizations();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Startup diagnostics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusLine(
              label: 'Boot auto-start receiver',
              ok: true,
              okText: 'Configured',
              failText: 'Missing',
            ),
            const SizedBox(height: 8),
            _StatusLine(
              label: 'Battery optimization',
              ok: ignoringBatteryOptimization,
              okText: 'Disabled for VertiSignage',
              failText: 'Enabled (can block auto-start)',
            ),
            const SizedBox(height: 12),
            const Text(
              'Tip: On some brands (Xiaomi/Oppo/Vivo/Realme), also allow Auto-start in system settings.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () async {
              final opened = await device.openAutoStartSettings();
              if (!mounted) return;
              if (!opened) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not open Auto-start settings.'),
                  ),
                );
              }
            },
            child: const Text('Auto-start settings'),
          ),
          FilledButton(
            onPressed: () async {
              final opened = await device.openBatteryOptimizationSettings();
              if (!mounted) return;
              if (!opened) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Could not open Battery optimization settings.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Battery settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndRun({
    required String title,
    required String body,
    required String confirmLabel,
    required Future<void> Function() run,
  }) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await run();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dark,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                ValueListenableBuilder<PlayerDisplayState?>(
                  valueListenable: widget.controller.display,
                  builder: (context, state, _) {
                    if (state == null) {
                      return const ColoredBox(color: Colors.black);
                    }

                    return AnimatedSwitcher(
                      duration: _kPlaylistSwitchDuration,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return ClipRect(
                          child: _playlistSlideTransition(
                            transition: state.item.transition,
                            animation: animation,
                            child: child,
                          ),
                        );
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
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => _onSurfacePointer(),
                    onPointerSignal: (_) => _onSurfacePointer(),
                  ),
                ),
                ListenableBuilder(
                  listenable: sl<PlaylistSyncService>(),
                  builder: (context, _) {
                    return _PlaylistIdleOverlay(
                      sync: sl<PlaylistSyncService>(),
                    );
                  },
                ),
                if (_overlayVisible)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: widget.controller.userPaused,
                      builder: (context, paused, _) {
                        return PlayerKioskOverlay(
                          isPaused: paused,
                          onInteract: _onOverlayInteraction,
                          onPlayPause: widget.controller.togglePause,
                          onPrevious: () =>
                              unawaited(widget.controller.goToPrevious()),
                          onNext: () => unawaited(widget.controller.goToNext()),
                          onClearCache: () => unawaited(
                            _confirmAndRun(
                              title: 'Clear cached media?',
                              body:
                                  'Downloaded images and videos will be removed. '
                                  'Content will re-fetch on the next sync.',
                              confirmLabel: 'Clear',
                              run: _clearCache,
                            ),
                          ),
                          onRepair: () => unawaited(
                            _confirmAndRun(
                              title: 'Pair this device again?',
                              body:
                                  'The device unlinks from the current account. '
                                  'You will enter a new pairing code.',
                              confirmLabel: 'Continue',
                              run: _pairAgain,
                            ),
                          ),
                          onResetApp: () => unawaited(
                            _confirmAndRun(
                              title: 'Reset application?',
                              body:
                                  'Clears cache, ends this session, and restarts '
                                  'the app when supported. You can pair again afterward.',
                              confirmLabel: 'Reset',
                              run: _resetApp,
                            ),
                          ),
                          onStartupDiagnostics: () =>
                              unawaited(_showStartupDiagnostics()),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          const AnnouncementOverlayLayer(),
          const AnnouncementTickerLayer(),
          const RealtimePushLayer(),
          const EmergencyOverlayLayer(),
          const VoiceTakeoverOverlay(),
        ],
      ),
    );
  }

  Widget _buildSlide(PlayerDisplayState state) {
    final item = state.item;
    final ctrl = widget.controller;
    final boxFit = boxFitFromPlaylistMode(item.fitMode);

    if (state.isWebSlide && state.webUri != null) {
      if (item.mediaKind == PlaylistMediaKind.url &&
          state.urlRenderMode == UrlRenderMode.video) {
        return VideoSlideLayer(
          networkUri: state.webUri,
          fit: boxFit,
          muted: item.muted,
          generation: state.generation,
          onEnded: ctrl.onVideoEnded,
          playbackPaused: ctrl.playbackSuspended,
        );
      }
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
          fit: boxFit,
          muted: item.muted,
          generation: state.generation,
          onEnded: ctrl.onVideoEnded,
          playbackPaused: ctrl.playbackSuspended,
        );
      case PlaylistMediaKind.image:
        return ImageSlideLayer(
          path: path,
          fit: boxFit,
          onDecodeFailed: ctrl.onRasterDisplayFailed,
        );
    }
  }
}

/// Full-screen feedback while there is nothing playable yet (sync, errors, empty playlist).
class _PlaylistIdleOverlay extends StatelessWidget {
  const _PlaylistIdleOverlay({required this.sync});

  final PlaylistSyncService sync;

  @override
  Widget build(BuildContext context) {
    if (sync.activeItems.isNotEmpty) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<VertisignageColors>();
    final muted = tokens?.textMuted ?? cs.onSurfaceVariant;
    final titleStyle = Theme.of(
      context,
    ).textTheme.headlineSmall?.copyWith(color: cs.onSurface);
    final bodyStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant);
    final captionStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: muted);

    late final Widget body;
    if (sync.isSyncing) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: AppSpacing.s10,
            height: AppSpacing.s10,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(
            'Loading playlist',
            style: titleStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            'Fetching schedule and preparing media…',
            style: bodyStyle,
            textAlign: TextAlign.center,
          ),
        ],
      );
    } else if (sync.lastSyncError != null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, color: muted, size: AppSpacing.s12),
          const SizedBox(height: AppSpacing.s6),
          Text(
            'Could not load content',
            style: titleStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            sync.lastSyncError!,
            style: bodyStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s8),
          FilledButton.icon(
            onPressed: () => unawaited(sync.sync()),
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      );
    } else if (sync.serverPlaylistEmpty) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.s6),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12.0),
                child: Image.asset(
                  'assets/verti_signage_logo.png',
                  height: AppSpacing.s12,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
              Text(
                'powered by vertilinks',
                style: titleStyle,
                textAlign: TextAlign.center,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            'Assign images or video to this device’s playlist in the admin console, '
            'then tap refresh.',
            style: bodyStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s8),
          OutlinedButton.icon(
            onPressed: () => unawaited(sync.sync()),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: AppSpacing.s10,
            height: AppSpacing.s10,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(
            'Preparing playback',
            style: titleStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            'Waiting for the playlist…',
            style: captionStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s8),
          TextButton.icon(
            onPressed: () => unawaited(sync.sync()),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Sync now'),
          ),
        ],
      );
    }

    return Material(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s6),
            child: body,
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.ok,
    required this.okText,
    required this.failText,
  });

  final String label;
  final bool ok;
  final String okText;
  final String failText;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = ok ? Colors.green.shade400 : cs.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ok ? Icons.check_circle_outline : Icons.error_outline,
          color: color,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label: ${ok ? okText : failText}',
            style: TextStyle(color: cs.onSurface),
          ),
        ),
      ],
    );
  }
}
