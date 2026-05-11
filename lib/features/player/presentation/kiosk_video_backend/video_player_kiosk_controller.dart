import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'kiosk_video_controller.dart';

class VideoPlayerKioskController implements KioskVideoController {
  VideoPlayerKioskController._(this._c, {required this.looping});

  final VideoPlayerController _c;
  final bool looping;

  static Future<VideoPlayerKioskController?> fromFile(
    String path, {
    required bool looping,
    required bool muted,
  }) async {
    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
      await c.setLooping(looping);
      await c.setVolume(muted ? 0 : 1);
      return VideoPlayerKioskController._(c, looping: looping);
    } catch (e) {
      if (kDebugMode) debugPrint('VideoPlayerKioskController init failed: $e');
      await c.dispose();
      return null;
    }
  }

  static Future<VideoPlayerKioskController?> fromNetwork(
    Uri uri, {
    required bool looping,
    required bool muted,
  }) async {
    final c = VideoPlayerController.networkUrl(uri);
    try {
      await c.initialize();
      await c.setLooping(looping);
      await c.setVolume(muted ? 0 : 1);
      return VideoPlayerKioskController._(c, looping: looping);
    } catch (e) {
      if (kDebugMode) debugPrint('VideoPlayerKioskController init failed: $e');
      await c.dispose();
      return null;
    }
  }

  VideoPlayerController get raw => _c;

  @override
  bool get isInitialized => _c.value.isInitialized;

  @override
  bool get hasError => _c.value.hasError;

  @override
  String? get errorDescription => _c.value.errorDescription;

  @override
  Duration get position => _c.value.position;

  @override
  Duration get duration => _c.value.duration;

  @override
  bool get supportsEndedDetection => true;

  @override
  Future<void> pause() => _c.pause();

  @override
  Future<void> play() => _c.play();

  @override
  Future<void> restart() async {
    await _c.pause();
    await _c.seekTo(Duration.zero);
    await _c.play();
  }

  @override
  Future<void> setVolume(double volume0to1) =>
      _c.setVolume(volume0to1.clamp(0.0, 1.0));

  @override
  void dispose() {
    safeDispose(() => _c.dispose());
  }
}

