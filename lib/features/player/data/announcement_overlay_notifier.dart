import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Kiosk treats announcements as full-screen media only (image or video URL).
enum AnnouncementMediaKind {
  none,
  image,
  video,
  url,
}

enum AnnouncementRenderMode { overlay, ticker }

/// Full-screen announcement from realtime `ANNOUNCEMENT`; auto-dismiss calls [onDismiss].
///
/// Content loops until [presentationEndsAtUtc], until wall-clock [durationSec] elapses (when not
/// [untilDismissed]), or until [AnnouncementClearCommand] / hide clears it while [untilDismissed].
///
/// If a new announcement replaces an active one, timers reset without invoking the prior
/// [onDismiss] so playback stays frozen until the latest finishes.
class AnnouncementOverlayNotifier extends ChangeNotifier {
  Timer? _deadlineTicker;

  VoidCallback? _onDismiss;

  String? _id;
  AnnouncementMediaKind _mediaKind = AnnouncementMediaKind.none;
  String? _mediaUrl;
  AnnouncementRenderMode _mode = AnnouncementRenderMode.overlay;
  String _title = 'Announcement';
  String? _body;
  bool _untilDismissed = false;
  int _wallClockDurationSec = 15;
  DateTime? _shownAtUtc;
  DateTime? _presentationEndsAtUtc;
  VideoPlayerController? _videoController;

  String? get announcementId => _id;
  AnnouncementMediaKind get mediaKind => _mediaKind;
  String? get mediaUrl => _mediaUrl;
  AnnouncementRenderMode get mode => _mode;
  String get title => _title;
  String? get body => _body;
  bool get untilDismissed => _untilDismissed;

  bool get isActive => _id != null;

  void show({
    required String announcementId,
    required int durationSec,
    required AnnouncementRenderMode mode,
    required String title,
    String? body,
    required bool untilDismissed,
    AnnouncementMediaKind mediaKind = AnnouncementMediaKind.none,
    String? mediaUrl,
    DateTime? presentationEndsAtUtc,
    required VoidCallback onDismiss,
  }) {
    _deadlineTicker?.cancel();
    _deadlineTicker = null;

    _id = announcementId;
    final trimmed = mediaUrl?.trim();
    _mediaUrl = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    _mediaKind =
        _mediaUrl == null
            ? AnnouncementMediaKind.none
            : mediaKind == AnnouncementMediaKind.video
            ? AnnouncementMediaKind.video
            : mediaKind == AnnouncementMediaKind.url
            ? AnnouncementMediaKind.url
            : AnnouncementMediaKind.image;
    _mode = mode;
    _title = title;
    _body = body;
    _untilDismissed = untilDismissed;
    _wallClockDurationSec = durationSec.clamp(3, 600);
    _shownAtUtc = DateTime.now().toUtc();
    _presentationEndsAtUtc = presentationEndsAtUtc;

    _onDismiss = onDismiss;

    notifyListeners();
    _startDeadlineTicker();
    _maybeExpiredImmediately();
  }

  /// Bound when overlay plays announcement video (see [_AnnouncementMediaFill]).
  void bindVideoController(VideoPlayerController? controller) {
    _videoController = controller;
  }

  void applyTransportCommand({
    required String announcementId,
    required String action,
    double? volume,
  }) {
    if (_id == null || _id != announcementId) return;
    final v = _videoController;
    if (v == null || !v.value.isInitialized) return;
    if (volume != null) {
      unawaited(v.setVolume(volume.clamp(0.0, 1.0)));
    }
    final a = action.toLowerCase();
    if (a == 'pause') {
      unawaited(v.pause());
    } else if (a == 'play') {
      unawaited(v.play());
    } else if (a == 'restart') {
      unawaited(v.pause());
      unawaited(v.seekTo(Duration.zero));
      unawaited(v.play());
    }
  }

  void dismissManual() => _finishFromTimer();

  DateTime? _resolveDeadlineUtc() {
    if (_presentationEndsAtUtc != null) return _presentationEndsAtUtc;
    if (_untilDismissed) return null;
    final start = _shownAtUtc;
    if (start == null) return null;
    return start.add(Duration(seconds: _wallClockDurationSec));
  }

  void _maybeExpiredImmediately() {
    final end = _resolveDeadlineUtc();
    if (end == null) return;
    if (!DateTime.now().toUtc().isBefore(end)) {
      _finishFromTimer();
    }
  }

  void _startDeadlineTicker() {
    _deadlineTicker?.cancel();
    if (_resolveDeadlineUtc() == null) return;

    _deadlineTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_id == null) return;
      final deadline = _resolveDeadlineUtc();
      if (deadline == null) return;
      if (!DateTime.now().toUtc().isBefore(deadline)) {
        _finishFromTimer();
      }
    });
  }

  void _finishFromTimer() {
    _deadlineTicker?.cancel();
    _deadlineTicker = null;
    if (_id == null) return;

    _id = null;
    _mediaUrl = null;
    _mediaKind = AnnouncementMediaKind.none;
    _mode = AnnouncementRenderMode.overlay;
    _title = 'Announcement';
    _body = null;
    _untilDismissed = false;
    _wallClockDurationSec = 15;
    _shownAtUtc = null;
    _presentationEndsAtUtc = null;
    _videoController = null;

    final cb = _onDismiss;
    _onDismiss = null;
    notifyListeners();
    cb?.call();
  }
}
