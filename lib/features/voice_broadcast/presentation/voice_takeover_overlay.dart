import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../data/voice_broadcast_player.dart';

class VoiceTakeoverOverlay extends StatefulWidget {
  const VoiceTakeoverOverlay({super.key});

  @override
  State<VoiceTakeoverOverlay> createState() => _VoiceTakeoverOverlayState();
}

class _VoiceTakeoverOverlayState extends State<VoiceTakeoverOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  VoiceBroadcastPlayer get _voice => GetIt.instance<VoiceBroadcastPlayer>();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VoiceTakeoverUiState>(
      valueListenable: _voice.takeoverState,
      builder: (context, state, _) {
        if (!state.visible) return const SizedBox.shrink();

        final isActive = state.streaming;

        return Positioned.fill(
          child: Container(
            color: Colors.black, // full solid black background
            child: SafeArea(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 32,
                  ),
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.black, // solid black card
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _GlassIcon(isActive: isActive),
                      const SizedBox(height: 20),
                      const Text(
                        'Voice Broadcast',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _WaveBars(anim: _anim, isActive: isActive),
                      const SizedBox(height: 20),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          state.message,
                          key: ValueKey(state.message),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isActive ? Colors.white : Colors.grey,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GlassIcon extends StatelessWidget {
  final bool isActive;

  const _GlassIcon({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black,
      ),
      child: Icon(
        Icons.multitrack_audio_rounded,
        color: isActive ? Colors.white : Colors.grey,
        size: 32,
      ),
    );
  }
}

class _WaveBars extends StatelessWidget {
  final Animation<double> anim;
  final bool isActive;

  const _WaveBars({required this.anim, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(10, (i) {
            final phase = (anim.value * 2 * math.pi) + (i * 0.45);
            final height = 10 + math.sin(phase).abs() * 26;

            return Container(
              width: 4,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: isActive ? Colors.white : Colors.grey,
              ),
            );
          }),
        );
      },
    );
  }
}
