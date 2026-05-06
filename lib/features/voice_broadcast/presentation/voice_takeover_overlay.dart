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
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

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
        return Positioned.fill(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.78),
            child: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.campaign_rounded, color: Colors.redAccent, size: 72),
                    const SizedBox(height: 12),
                    const Text(
                      'LIVE VOICE BROADCAST',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    AnimatedBuilder(
                      animation: _anim,
                      builder: (context, _) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: List.generate(8, (idx) {
                            final phase = (_anim.value * math.pi * 2) + (idx * 0.5);
                            final h = 12 + (math.sin(phase).abs() * 28);
                            return Container(
                              width: 7,
                              height: h,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: (state.streaming
                                        ? Colors.redAccent
                                        : Colors.orangeAccent)
                                    .withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      state.message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: state.streaming ? Colors.white : Colors.orangeAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
