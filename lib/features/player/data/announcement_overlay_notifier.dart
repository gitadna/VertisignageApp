import 'dart:async';

import 'package:flutter/foundation.dart';

/// Kiosk treats announcements as full-screen media only (image or video URL).
enum AnnouncementMediaKind {
  none,
  image,
  video,
}

enum AnnouncementRenderMode { overlay, ticker }

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
  AnnouncementRenderMode _mode = AnnouncementRenderMode.overlay;
  String _title = 'Announcement';
  String? _body;
  bool _untilDismissed = false;

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
    _mode = mode;
    _title = title;
    _body = body;
    _untilDismissed = untilDismissed;

    _onDismiss = onDismiss;

    notifyListeners();

    if (!untilDismissed) {
      final ms = (durationSec.clamp(3, 600) * 1000).toInt();
      _timer = Timer(Duration(milliseconds: ms), _finishFromTimer);
    }
  }

  void dismissManual() => _finishFromTimer();

  void _finishFromTimer() {
    _timer?.cancel();
    _timer = null;
    if (_id == null) return;

    _id = null;
    _mediaUrl = null;
    _mediaKind = AnnouncementMediaKind.none;
    _mode = AnnouncementRenderMode.overlay;
    _title = 'Announcement';
    _body = null;
    _untilDismissed = false;

    final cb = _onDismiss;
    _onDismiss = null;
    notifyListeners();
    cb?.call();
  }
}
