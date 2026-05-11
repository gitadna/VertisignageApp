import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Minimal transport + lifecycle API shared across video backends.
abstract class KioskVideoController {
  bool get isInitialized;
  bool get hasError;
  String? get errorDescription;

  Duration get position;
  Duration get duration;

  Future<void> play();
  Future<void> pause();
  Future<void> restart();
  Future<void> setVolume(double volume0to1);

  /// Whether the backend supports reliable end-of-playback callbacks.
  bool get supportsEndedDetection;

  void dispose();
}

/// Transport target used by announcements (play/pause/restart/volume).
abstract class AnnouncementTransportTarget {
  bool get isReady;
  Future<void> play();
  Future<void> pause();
  Future<void> restart();
  Future<void> setVolume(double volume0to1);
}

/// Helper to ensure dispose calls are non-throwing.
void safeDispose(VoidCallback fn) {
  try {
    fn();
  } catch (_) {}
}

/// A lightweight controller facade that announces changes via [notifier].
class KioskVideoStatus extends ChangeNotifier {
  bool _initialized = false;
  bool _hasError = false;
  String? _error;

  bool get isInitialized => _initialized;
  bool get hasError => _hasError;
  String? get errorDescription => _error;

  void update({required bool initialized, required bool hasError, String? error}) {
    final changed =
        _initialized != initialized || _hasError != hasError || _error != error;
    _initialized = initialized;
    _hasError = hasError;
    _error = error;
    if (changed) notifyListeners();
  }
}

/// Convenience: a one-shot async init wrapper that reports errors.
Future<T?> tryInit<T>(Future<T> Function() run) async {
  try {
    return await run();
  } catch (e) {
    if (kDebugMode) {
      debugPrint('tryInit error: $e');
    }
    return null;
  }
}

