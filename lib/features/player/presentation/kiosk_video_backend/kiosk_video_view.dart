import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/di/injection.dart';
import '../../data/kiosk_video_preferences.dart';
import 'kiosk_video_controller.dart';
import 'video_player_kiosk_controller.dart';
import 'vlc_kiosk_controller.dart';

/// Renders video using VideoPlayer first, then falls back to VLC on failure.
class KioskVideoView extends StatefulWidget {
  const KioskVideoView({
    super.key,
    this.filePath,
    this.networkUri,
    required this.fit,
    required this.looping,
    required this.muted,
    this.playbackPaused,
    this.onEnded,
    this.onError,
    this.onControllerReady,
  }) : assert(
          (filePath != null && networkUri == null) ||
              (filePath == null && networkUri != null),
          'Provide exactly one of filePath or networkUri.',
        );

  final String? filePath;
  final Uri? networkUri;
  final BoxFit fit;
  final bool looping;
  final bool muted;
  final ValueListenable<bool>? playbackPaused;
  final VoidCallback? onEnded;
  final void Function(String error)? onError;
  final void Function(AnnouncementTransportTarget? target)? onControllerReady;

  @override
  State<KioskVideoView> createState() => _KioskVideoViewState();
}

class _KioskVideoViewState extends State<KioskVideoView>
    with WidgetsBindingObserver
    implements AnnouncementTransportTarget {
  KioskVideoController? _ctrl;
  bool _usingVlc = false;
  bool _notifiedEnd = false;
  VoidCallback? _pausedListener;
  StreamSubscription? _vlcEndSub;

  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attachPausedListener();
    unawaited(_init());
  }

  @override
  void didUpdateWidget(covariant KioskVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final srcChanged =
        oldWidget.filePath != widget.filePath || oldWidget.networkUri != widget.networkUri;
    if (srcChanged ||
        oldWidget.looping != widget.looping ||
        oldWidget.muted != widget.muted) {
      unawaited(_reinit());
    }
    if (oldWidget.playbackPaused != widget.playbackPaused) {
      _detachPausedListener();
      _attachPausedListener();
      _applyPaused();
    }
  }

  Future<void> _reinit() async {
    await _disposeController();
    _notifiedEnd = false;
    _error = null;
    if (mounted) setState(() {});
    await _init();
  }

  void _attachPausedListener() {
    final listenable = widget.playbackPaused;
    if (listenable == null) return;
    void listener() {
      if (!mounted) return;
      _applyPaused();
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _applyPaused();
  }

  void _applyPaused() {
    final c = _ctrl;
    if (c == null || !c.isInitialized) return;
    final paused = widget.playbackPaused?.value ?? false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final backgrounded = lifecycle != null && lifecycle != AppLifecycleState.resumed;
    if (paused || backgrounded) {
      unawaited(c.pause());
    } else {
      unawaited(c.play());
    }
  }

  Future<void> _init() async {
    final prefs = sl<KioskVideoPreferences>();
    final preferVlc = prefs.preferVlcVideo;

    // Try preferred first.
    final ok = await _tryBackend(useVlc: preferVlc);
    if (ok) return;

    // Fall back to the other backend.
    final ok2 = await _tryBackend(useVlc: !preferVlc);
    if (!ok2) {
      final err = (_error ?? 'video init failed').trim();
      widget.onError?.call(err.isEmpty ? 'video init failed' : err);
    }
  }

  Future<bool> _tryBackend({required bool useVlc}) async {
    _usingVlc = useVlc;
    final KioskVideoController? c;
    if (useVlc) {
      if (widget.filePath != null) {
        c = await VlcKioskController.fromFile(
          widget.filePath!,
          looping: widget.looping,
          muted: widget.muted,
        );
      } else {
        c = await VlcKioskController.fromNetwork(
          widget.networkUri.toString(),
          looping: widget.looping,
          muted: widget.muted,
        );
      }
    } else {
      if (widget.filePath != null) {
        c = await VideoPlayerKioskController.fromFile(
          widget.filePath!,
          looping: widget.looping,
          muted: widget.muted,
        );
      } else {
        final uri = widget.networkUri;
        if (uri == null) return false;
        c = await VideoPlayerKioskController.fromNetwork(
          uri,
          looping: widget.looping,
          muted: widget.muted,
        );
      }
    }

    if (c == null || !c.isInitialized || c.hasError) {
      _error = c?.errorDescription ?? 'init failed';
      c?.dispose();
      return false;
    }

    _ctrl = c;
    widget.onControllerReady?.call(this);
    _wireEndedDetection();
    if (mounted) setState(() {});
    await c.play();
    _applyPaused();

    // If we had to fall back to VLC, remember preference on this device.
    if (useVlc) {
      unawaited(sl<KioskVideoPreferences>().setPreferVlcVideo(true));
    }
    return true;
  }

  void _wireEndedDetection() {
    _vlcEndSub?.cancel();
    _vlcEndSub = null;

    final c = _ctrl;
    if (c == null || widget.onEnded == null) return;
    if (_usingVlc && c is VlcKioskController) {
      // flutter_vlc_player doesn't expose a stable ended event across versions.
      // Detect end from position/duration and loop/release accordingly.
      c.raw.addListener(() async {
        if (!mounted || _notifiedEnd) return;
        final v = c.raw.value;
        if (v.hasError) {
          _error = v.errorDescription ?? 'decoder error';
          unawaited(sl<KioskVideoPreferences>().setPreferVlcVideo(true));
          return;
        }
        final d = v.duration;
        final p = v.position;
        if (d == Duration.zero) return;
        if (p >= d - const Duration(milliseconds: 220)) {
          if (widget.looping) {
            await c.restart();
          } else {
            _notifiedEnd = true;
            widget.onEnded?.call();
          }
        }
      });
    } else if (!_usingVlc && c is VideoPlayerKioskController) {
      // Detect end via polling on tick is handled by callers (playlist layer) today;
      // here we add a lightweight listener for overlay looping.
      c.raw.addListener(() async {
        if (!mounted || _notifiedEnd) return;
        final v = c.raw.value;
        if (v.hasError) {
          _error = v.errorDescription ?? 'decoder error';
          // Switch to VLC next time.
          unawaited(sl<KioskVideoPreferences>().setPreferVlcVideo(true));
          return;
        }
        if (!widget.looping) {
          final d = v.duration;
          if (d != Duration.zero &&
              v.position >= d - const Duration(milliseconds: 140)) {
            _notifiedEnd = true;
            widget.onEnded?.call();
          }
        }
      });
    }
  }

  Future<void> _disposeController() async {
    widget.onControllerReady?.call(null);
    _vlcEndSub?.cancel();
    _vlcEndSub = null;
    final c = _ctrl;
    _ctrl = null;
    if (c != null) {
      c.dispose();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachPausedListener();
    unawaited(_disposeController());
    super.dispose();
  }

  // AnnouncementTransportTarget
  @override
  bool get isReady => _ctrl != null && _ctrl!.isInitialized && !_ctrl!.hasError;

  @override
  Future<void> pause() async => _ctrl?.pause();

  @override
  Future<void> play() async => _ctrl?.play();

  @override
  Future<void> restart() async => _ctrl?.restart();

  @override
  Future<void> setVolume(double volume0to1) async =>
      _ctrl?.setVolume(volume0to1);

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    if (c == null || !c.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    Widget core;
    if (_usingVlc && c is VlcKioskController) {
      core = VlcPlayer(
        controller: c.raw,
        aspectRatio: 16 / 9,
        placeholder: const ColoredBox(color: Colors.black),
      );
    } else if (!_usingVlc && c is VideoPlayerKioskController) {
      core = VideoPlayer(c.raw);
    } else {
      core = const ColoredBox(color: Colors.black);
    }

    // Fit behavior aligned with existing VideoSlideLayer.
    return ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(
        child: FittedBox(
          fit: widget.fit == BoxFit.fill ? BoxFit.fill : widget.fit,
          alignment: Alignment.center,
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width,
            height: MediaQuery.sizeOf(context).height,
            child: core,
          ),
        ),
      ),
    );
  }
}

