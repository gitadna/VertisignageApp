import 'package:flutter/foundation.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'dart:io';

import 'kiosk_video_controller.dart';

class VlcKioskController implements KioskVideoController {
  VlcKioskController._(this._c);

  final VlcPlayerController _c;

  static Future<VlcKioskController?> fromNetwork(
    String url, {
    required bool looping,
    required bool muted,
  }) async {
    try {
      final c = VlcPlayerController.network(
        url,
        hwAcc: HwAcc.auto,
        autoPlay: false,
        options: VlcPlayerOptions(
          advanced: VlcAdvancedOptions([
            VlcAdvancedOptions.networkCaching(800),
            VlcAdvancedOptions.fileCaching(800),
            VlcAdvancedOptions.clockJitter(0),
            VlcAdvancedOptions.clockSynchronization(0),
          ]),
        ),
      );
      // No reliable awaitable initialize; wait for first value update.
      if (muted) {
        // Best-effort; VLC volume is 0..100.
        await c.setVolume(0);
      } else {
        await c.setVolume(100);
      }
      if (looping) {
        // Looping is handled in the widget (seek to 0 on end).
      }
      return VlcKioskController._(c);
    } catch (e) {
      if (kDebugMode) debugPrint('VlcKioskController init failed: $e');
      return null;
    }
  }

  static Future<VlcKioskController?> fromFile(
    String path, {
    required bool looping,
    required bool muted,
  }) async {
    try {
      final c = VlcPlayerController.file(
        File(path),
        hwAcc: HwAcc.auto,
        autoPlay: false,
        options: VlcPlayerOptions(
          advanced: VlcAdvancedOptions([
            VlcAdvancedOptions.fileCaching(800),
          ]),
        ),
      );
      if (muted) {
        await c.setVolume(0);
      } else {
        await c.setVolume(100);
      }
      if (looping) {
        // Looping handled by listener in view.
      }
      return VlcKioskController._(c);
    } catch (e) {
      if (kDebugMode) debugPrint('VlcKioskController init failed: $e');
      return null;
    }
  }

  VlcPlayerController get raw => _c;

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
    await _c.setTime(0);
    await _c.play();
  }

  @override
  Future<void> setVolume(double volume0to1) async {
    final v = (volume0to1.clamp(0.0, 1.0) * 100).round();
    await _c.setVolume(v);
  }

  @override
  void dispose() {
    safeDispose(() => _c.dispose());
  }
}

