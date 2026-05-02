import 'dart:async';

import 'package:flutter/foundation.dart';

/// Kiosk treats announcements as full-screen media only (image or video URL).
enum AnnouncementMediaKind {
  none,
  image,
  video,
}

/// Full-screen announcement from realtime `ANNOUNCEMENT`; auto-dismiss calls [onDismiss].
///
/// If a new announcement replaces an active one, the timer resets without invoking the prior
/// [onDismiss] so playback stays frozen until the latest finishes.
class AnnouncementOverlayNotifier extends ChangeNotifier {
  Timer? _timer;
  VoidCallback? _onDismiss;

  String? _id;
  AnnouncementMediaKind _mediaKind = AnnouncementMediaKind.none;
  String? _mediaUrl;

  String? get announcementId => _id;
  AnnouncementMediaKind get mediaKind => _mediaKind;
  String? get mediaUrl => _mediaUrl;

  bool get isActive => _id != null;

  void show({
    required String announcementId,
    required int durationSec,
    AnnouncementMediaKind mediaKind = AnnouncementMediaKind.none,
    String? mediaUrl,
    required VoidCallback onDismiss,
  }) {
    _timer?.cancel();
    _timer = null;

    _id = announcementId;
    final trimmed = mediaUrl?.trim();
    _mediaUrl = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    _mediaKind =
        _mediaUrl == null
            ? AnnouncementMediaKind.none
            : mediaKind == AnnouncementMediaKind.video
            ? AnnouncementMediaKind.video
            : AnnouncementMediaKind.image;

    _onDismiss = onDismiss;

    notifyListeners();

    final ms = (durationSec.clamp(3, 600) * 1000).toInt();
    _timer = Timer(Duration(milliseconds: ms), _finishFromTimer);
  }

  void dismissManual() => _finishFromTimer();

  void _finishFromTimer() {
    _timer?.cancel();
    _timer = null;
    if (_id == null) return;

    _id = null;
    _mediaUrl = null;
    _mediaKind = AnnouncementMediaKind.none;

    final cb = _onDismiss;
    _onDismiss = null;
    notifyListeners();
    cb?.call();
  }
}
