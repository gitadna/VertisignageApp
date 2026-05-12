import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/logging/kiosk_log.dart';
import '../../../core/telemetry/fleet_telemetry.dart';

/// Lightweight Flutter shell that paints immediately, kicks off [deferredInit] after the first
/// frame, and then swaps in [child]. Splash dismisses on first frame regardless of whether the
/// deferred bootstrap has finished — failures there must never block the UI.
///
/// Rendered ahead of [child] so the [AppShell] does not need to know anything about the staged
/// bootstrap; it sees a normal `BuildContext` and a guaranteed-non-null `child` tree underneath.
class BootSplash extends StatefulWidget {
  const BootSplash({
    super.key,
    required this.deferredInit,
    required this.child,
    this.backgroundColor = const Color(0xFF0F1419),
    this.minimumSplashDuration = const Duration(milliseconds: 250),
    this.deferredKickoffFallback = const Duration(seconds: 5),
  });

  /// Future returned by `AppBootstrap.initDeferred`. Triggered via `addPostFrameCallback` so the
  /// first frame has already painted before the heavy I/O begins.
  final Future<void> Function() deferredInit;

  /// Tree to render once the splash dismisses (typically `AppShell`).
  final Widget child;

  final Color backgroundColor;

  /// Smallest amount of time the splash stays visible to avoid flicker on warm starts where
  /// deferredInit completes synchronously-fast. Best-effort UX guard only.
  final Duration minimumSplashDuration;

  /// Fallback timer in case `addPostFrameCallback` never fires (e.g. process started in pure
  /// background from a boot receiver before any FlutterView attaches). After this delay the
  /// deferred bootstrap is kicked off anyway so websocket/push come up even while we wait for
  /// the activity to attach.
  final Duration deferredKickoffFallback;

  @override
  State<BootSplash> createState() => _BootSplashState();
}

class _BootSplashState extends State<BootSplash> {
  bool _firstFramePainted = false;
  bool _deferredKickedOff = false;
  bool _deferredComplete = false;
  bool _deferredFailed = false;
  DateTime? _splashStartedAt;
  Timer? _minimumSplashTimer;
  Timer? _deferredKickoffFallbackTimer;

  @override
  void initState() {
    super.initState();
    _splashStartedAt = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _firstFramePainted = true;
      FleetTelemetry.event('boot', 'first_frame_painted');
      _scheduleDeferredKickoff('first_frame');
      _scheduleMinimumSplashGate();
    });
    // Boot-receiver-triggered headless launches may never paint a first frame until the
    // activity actually attaches, which can be many seconds later. Use a bounded fallback
    // so the deferred bootstrap still fires and websocket/push reconnects don't wait on UI.
    _deferredKickoffFallbackTimer = Timer(widget.deferredKickoffFallback, () {
      if (!mounted) return;
      if (_deferredKickedOff) return;
      _scheduleDeferredKickoff('fallback_timer');
    });
  }

  void _scheduleDeferredKickoff(String source) {
    if (_deferredKickedOff) return;
    _deferredKickedOff = true;
    FleetTelemetry.event('boot', 'deferred_kickoff source=$source');
    _deferredKickoffFallbackTimer?.cancel();
    _deferredKickoffFallbackTimer = null;
    // Run after the current frame so any platform-thread work the post-frame triggered finishes.
    scheduleMicrotask(() async {
      try {
        await widget.deferredInit();
      } catch (error, stackTrace) {
        _deferredFailed = true;
        KioskLog.e('Kiosk', 'deferred_init_failed error=$error stack=$stackTrace');
        FleetTelemetry.event('boot', 'deferred_init_failed error=${error.runtimeType}');
      } finally {
        if (mounted) {
          setState(() {
            _deferredComplete = true;
          });
          _maybeDismissSplash();
        }
      }
    });
  }

  void _scheduleMinimumSplashGate() {
    final start = _splashStartedAt ?? DateTime.now();
    final elapsed = DateTime.now().difference(start);
    final remaining = widget.minimumSplashDuration - elapsed;
    if (remaining <= Duration.zero) {
      _maybeDismissSplash();
      return;
    }
    _minimumSplashTimer = Timer(remaining, () {
      if (!mounted) return;
      _maybeDismissSplash();
    });
  }

  void _maybeDismissSplash() {
    if (!mounted) return;
    if (!_firstFramePainted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _minimumSplashTimer?.cancel();
    _deferredKickoffFallbackTimer?.cancel();
    super.dispose();
  }

  bool get _splashStillVisible {
    final minPassed = _minimumSplashTimer == null
        ? true
        : !(_minimumSplashTimer!.isActive);
    if (!_firstFramePainted) return true;
    if (!minPassed) return true;
    // Once minimum has passed, dismiss even if deferred is still running. The downstream tree
    // already renders its own loading states (e.g. PlayerScreen placeholders).
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Always include the child so its own state is constructed early; overlay the splash on top
    // while it's still visible. This avoids a late `initState` cascade in AppShell when the
    // splash dismisses, which would otherwise cost another frame.
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_splashStillVisible)
          _SplashSurface(
            backgroundColor: widget.backgroundColor,
            deferredComplete: _deferredComplete,
            deferredFailed: _deferredFailed,
          ),
      ],
    );
  }
}

class _SplashSurface extends StatelessWidget {
  const _SplashSurface({
    required this.backgroundColor,
    required this.deferredComplete,
    required this.deferredFailed,
  });

  final Color backgroundColor;
  final bool deferredComplete;
  final bool deferredFailed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cast_connected,
                size: 72,
                color: Colors.white,
              ),
              const SizedBox(height: 24),
              const Text(
                'VertiSignage',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 32,
                height: 32,
                child: deferredComplete
                    ? Icon(
                        deferredFailed ? Icons.error_outline : Icons.check,
                        color: deferredFailed ? Colors.orangeAccent : Colors.white70,
                        size: 24,
                      )
                    : const CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
