import 'dart:async';

import 'package:flutter/foundation.dart';

/// Kinds of content a realtime push can carry.
enum RealtimePushContentKind { image, video, url, text }

RealtimePushContentKind? realtimePushContentKindFromString(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'image':
      return RealtimePushContentKind.image;
    case 'video':
      return RealtimePushContentKind.video;
    case 'url':
      return RealtimePushContentKind.url;
    case 'text':
      return RealtimePushContentKind.text;
  }
  return null;
}

enum RealtimePushFitMode { fill, fit, stretch }

RealtimePushFitMode realtimePushFitModeFromString(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'fill':
      return RealtimePushFitMode.fill;
    case 'stretch':
      return RealtimePushFitMode.stretch;
    case 'fit':
    default:
      return RealtimePushFitMode.fit;
  }
}

/// Snapshot of an active realtime push the player should render full-screen.
@immutable
class RealtimePushState {
  const RealtimePushState({
    required this.pushId,
    required this.contentKind,
    required this.durationSec,
    required this.startedAtUtc,
    required this.fitMode,
    required this.muted,
    this.mediaUrl,
    this.text,
    this.caption,
    this.issuedAtUtc,
    this.isPaused = false,
    this.restartTick = 0,
  });

  final String pushId;
  final RealtimePushContentKind contentKind;
  final String? mediaUrl;
  final String? text;
  final String? caption;
  final int durationSec;
  final RealtimePushFitMode fitMode;
  final bool muted;
  final DateTime startedAtUtc;
  final DateTime? issuedAtUtc;
  final bool isPaused;
  /// Incremented on admin "restart" so the UI layer can re-seek / remount media.
  final int restartTick;

  RealtimePushState copyWith({
    String? pushId,
    RealtimePushContentKind? contentKind,
    String? mediaUrl,
    String? text,
    String? caption,
    int? durationSec,
    RealtimePushFitMode? fitMode,
    bool? muted,
    DateTime? startedAtUtc,
    DateTime? issuedAtUtc,
    bool? isPaused,
    int? restartTick,
  }) {
    return RealtimePushState(
      pushId: pushId ?? this.pushId,
      contentKind: contentKind ?? this.contentKind,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      text: text ?? this.text,
      caption: caption ?? this.caption,
      durationSec: durationSec ?? this.durationSec,
      fitMode: fitMode ?? this.fitMode,
      muted: muted ?? this.muted,
      startedAtUtc: startedAtUtc ?? this.startedAtUtc,
      issuedAtUtc: issuedAtUtc ?? this.issuedAtUtc,
      isPaused: isPaused ?? this.isPaused,
      restartTick: restartTick ?? this.restartTick,
    );
  }
}

/// Holds the active realtime push and auto-clears after [durationSec].
///
/// A new push always replaces an in-flight one (latest wins). [clear] is the
/// kill-switch invoked from the dispatcher on a `REALTIME_PUSH_CLEAR` frame
/// or on timer expiry.
class RealtimePushNotifier extends ChangeNotifier {
  RealtimePushState? _active;
  Timer? _timer;
  VoidCallback? _onCleared;
  DateTime? _endsAtUtc;
  Duration? _pausedRemaining;

  RealtimePushState? get active => _active;
  bool get isActive => _active != null;

  void _scheduleDeadlineTimer() {
    _timer?.cancel();
    _timer = null;
    final end = _endsAtUtc;
    if (end == null) return;
    final now = DateTime.now().toUtc();
    final rem = end.difference(now);
    if (rem <= Duration.zero) {
      _finish();
      return;
    }
    _timer = Timer(rem, _finish);
  }

  /// Show a new push, cancelling any in-flight one. [onCleared] fires once
  /// when this push ends (timer or manual clear) so the dispatcher can
  /// resume the playlist.
  void show(RealtimePushState push, {required VoidCallback onCleared}) {
    _timer?.cancel();
    _timer = null;
    _pausedRemaining = null;

    _onCleared = onCleared;
    _endsAtUtc = DateTime.now().toUtc().add(Duration(seconds: push.durationSec));
    _active = push.copyWith(isPaused: false, restartTick: push.restartTick);
    notifyListeners();

    if (push.durationSec <= 0) {
      _finish();
      return;
    }
    _scheduleDeadlineTimer();
  }

  void pause({String? pushId}) {
    final a = _active;
    if (a == null || a.isPaused) return;
    if (pushId != null && pushId.isNotEmpty && pushId != a.pushId) return;
    final end = _endsAtUtc;
    if (end == null) return;

    _timer?.cancel();
    _timer = null;
    final rem = end.difference(DateTime.now().toUtc());
    if (rem <= Duration.zero) return;
    _pausedRemaining = rem;
    _active = a.copyWith(isPaused: true);
    notifyListeners();
  }

  void resume({String? pushId}) {
    final a = _active;
    if (a == null || !a.isPaused) return;
    if (pushId != null && pushId.isNotEmpty && pushId != a.pushId) return;
    final rem = _pausedRemaining;
    if (rem == null || rem <= Duration.zero) return;

    _endsAtUtc = DateTime.now().toUtc().add(rem);
    _pausedRemaining = null;
    _active = a.copyWith(isPaused: false);
    notifyListeners();
    _scheduleDeadlineTimer();
  }

  void restart({String? pushId}) {
    final a = _active;
    if (a == null) return;
    if (pushId != null && pushId.isNotEmpty && pushId != a.pushId) return;

    _timer?.cancel();
    _timer = null;
    _pausedRemaining = null;
    _endsAtUtc =
        DateTime.now().toUtc().add(Duration(seconds: a.durationSec));
    _active = a.copyWith(isPaused: false, restartTick: a.restartTick + 1);
    notifyListeners();
    _scheduleDeadlineTimer();
  }

  /// Manually clear the active push. If [pushId] is provided, only clears
  /// when it matches the active push (so a stale Clear can't kill a newer push).
  void clear({String? pushId}) {
    final active = _active;
    if (active == null) return;
    if (pushId != null && pushId.isNotEmpty && pushId != active.pushId) return;
    _finish();
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
    _endsAtUtc = null;
    _pausedRemaining = null;
    if (_active == null) return;
    _active = null;
    final cb = _onCleared;
    _onCleared = null;
    notifyListeners();
    cb?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
