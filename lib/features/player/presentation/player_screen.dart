import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/di/injection.dart';
import '../data/playlist_sync_service.dart';
import 'player_controller.dart';

/// Full-screen image loop using cached files only (no network in widget layer).
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
    widget.controller.start();
  }

  @override
  void dispose() {
    widget.controller.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<PlayerDisplayState?>(
        valueListenable: widget.controller.display,
        builder: (context, state, _) {
          if (state == null) {
            return const ColoredBox(color: Colors.black);
          }

          final path = state.localPath;
          if (path == null) {
            return const ColoredBox(color: Colors.black);
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              return ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        widget.controller.onImageDisplayFailed();
                      });
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
