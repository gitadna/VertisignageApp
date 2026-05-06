import 'dart:convert';

/// Parsed server push (`{ "type", "payload" }`).
sealed class RealtimeCommand {
  const RealtimeCommand();
}

class PlaylistUpdatedCommand extends RealtimeCommand {
  const PlaylistUpdatedCommand({this.playlistId});

  final String? playlistId;
}

class SyncRequestCommand extends RealtimeCommand {
  const SyncRequestCommand();
}

class EmergencyAlertCommand extends RealtimeCommand {
  const EmergencyAlertCommand({
    required this.alertId,
    required this.alertType,
    required this.title,
    required this.message,
  });

  final String alertId;
  final String alertType;
  final String title;
  final String message;
}

class AlertResolvedCommand extends RealtimeCommand {
  const AlertResolvedCommand({required this.alertId});

  final String alertId;
}

class VolumeSetCommand extends RealtimeCommand {
  const VolumeSetCommand({required this.volume});

  final int volume;
}

class MuteSetCommand extends RealtimeCommand {
  const MuteSetCommand({required this.muted});

  final bool muted;
}

class BrightnessSetCommand extends RealtimeCommand {
  const BrightnessSetCommand({required this.brightness});

  final int brightness;
}

class PlaybackPauseCommand extends RealtimeCommand {
  const PlaybackPauseCommand({required this.paused});

  final bool paused;
}

class PlaybackSkipCommand extends RealtimeCommand {
  const PlaybackSkipCommand({required this.direction});

  final String direction;
}

class WakeAppCommand extends RealtimeCommand {
  const WakeAppCommand({required this.messageId, this.reason});

  final String messageId;
  final String? reason;
}

class RestartAppCommand extends RealtimeCommand {
  const RestartAppCommand({this.reason});

  final String? reason;
}

class PingCommand extends RealtimeCommand {
  const PingCommand({required this.messageId});

  final String messageId;
}

class GetStatusCommand extends RealtimeCommand {
  const GetStatusCommand({required this.messageId});

  final String messageId;
}

class UpdateAppCommand extends RealtimeCommand {
  const UpdateAppCommand({
    required this.messageId,
    required this.url,
    required this.sha256,
    required this.version,
  });

  final String messageId;
  final String url;
  final String sha256;
  final String version;
}

class ClearCacheCommand extends RealtimeCommand {
  const ClearCacheCommand({required this.messageId});

  final String messageId;
}

class OverlayShowCommand extends RealtimeCommand {
  const OverlayShowCommand({
    required this.messageId,
    required this.text,
    this.mediaUrl,
    this.mediaKind,
    this.untilDismissed = true,
    this.durationSec = 10,
    this.opacity = 0.9,
    this.commandType,
    this.contentType,
    this.createdAt,
  });

  final String messageId;
  final String text;
  final String? mediaUrl;
  final String? mediaKind;
  final bool untilDismissed;
  final int durationSec;
  final double opacity;
  final String? commandType;
  final String? contentType;
  final DateTime? createdAt;
}

class OverlayHideCommand extends RealtimeCommand {
  const OverlayHideCommand({required this.messageId});

  final String messageId;
}

class AnnouncementCommand extends RealtimeCommand {
  const AnnouncementCommand({
    required this.announcementId,
    required this.title,
    // Optional: kiosk overlay is media-only; uncomment usage if we show body text.
    this.body,
    required this.durationSec,
    this.mediaUrl,
    this.mediaKind,
    this.mode,
    this.untilDismissed = false,
    this.commandType,
    this.contentType,
    this.createdAt,
    this.scheduleEndsAtUtc,
  });

  final String announcementId;
  final String title;
  final String? body;
  final int durationSec;
  /// Resolved playback URL (legacy payloads used `imageUrl` only).
  final String? mediaUrl;
  /// Server hint: `image` or `video`.
  final String? mediaKind;
  final String? mode;
  final bool untilDismissed;
  final String? commandType;
  final String? contentType;
  final DateTime? createdAt;
  /// When set, kiosk loops announcement media until this instant (UTC).
  final DateTime? scheduleEndsAtUtc;
}

class AnnouncementClearCommand extends RealtimeCommand {
  const AnnouncementClearCommand({this.announcementId});
  final String? announcementId;
}

/// JSON → typed command; unknown types return null (ignored).
RealtimeCommand? parseRealtimeCommand(String raw) {
  try {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final decodedMap = Map<String, dynamic>.from(decoded);
    final type = decodedMap['type'] as String?;
    final payload = decodedMap['payload'];
    if (type == null) return null;

    switch (type) {
      case 'PLAYLIST_UPDATED':
        final m = payload is Map<String, dynamic> ? payload : null;
        return PlaylistUpdatedCommand(
          playlistId: m?['playlistId'] as String?,
        );
      case 'SYNC_REQUEST':
      case 'SCHEDULE_UPDATED':
        return const SyncRequestCommand();
      case 'EMERGENCY_ALERT':
        if (payload is! Map<String, dynamic>) return null;
        final aid = payload['alertId'] as String?;
        final at = payload['alertType'] as String?;
        final title = payload['title'] as String?;
        final message = payload['message'] as String?;
        if (aid == null || at == null || title == null || message == null) {
          return null;
        }
        return EmergencyAlertCommand(
          alertId: aid,
          alertType: at,
          title: title,
          message: message,
        );
      case 'ALERT_RESOLVED':
        if (payload is! Map<String, dynamic>) return null;
        final aid = payload['alertId'] as String?;
        if (aid == null) return null;
        return AlertResolvedCommand(alertId: aid);
      case 'VOLUME_SET':
        if (payload is! Map<String, dynamic>) return null;
        final v = payload['volume'];
        if (v is! num) return null;
        return VolumeSetCommand(volume: v.round().clamp(0, 100));
      case 'MUTE_SET':
        if (payload is! Map<String, dynamic>) return null;
        final muted = payload['muted'];
        if (muted is! bool) return null;
        return MuteSetCommand(muted: muted);
      case 'BRIGHTNESS_SET':
        if (payload is! Map<String, dynamic>) return null;
        final b = payload['brightness'];
        if (b is! num) return null;
        return BrightnessSetCommand(brightness: b.round().clamp(1, 100));
      case 'PLAYBACK_PAUSE':
        if (payload is! Map<String, dynamic>) return null;
        final paused = payload['paused'];
        if (paused is! bool) return null;
        return PlaybackPauseCommand(paused: paused);
      case 'PLAYBACK_SKIP':
        if (payload is! Map<String, dynamic>) return null;
        final direction = payload['direction'] as String?;
        if (direction == null) return null;
        return PlaybackSkipCommand(direction: direction);
      case 'WAKE_APP':
        if (payload is! Map<String, dynamic>) return null;
        final mid = payload['messageId'] as String?;
        if (mid == null) return null;
        return WakeAppCommand(
          messageId: mid,
          reason: payload['reason'] as String?,
        );
      case 'RESTART_APP':
        String? reason;
        if (payload is Map<String, dynamic>) {
          reason = payload['reason'] as String?;
        }
        return RestartAppCommand(reason: reason);
      case 'PING':
        if (payload is! Map<String, dynamic>) return null;
        final mid = payload['messageId'] as String?;
        if (mid == null) return null;
        return PingCommand(messageId: mid);
      case 'GET_STATUS':
        if (payload is! Map<String, dynamic>) return null;
        final mid = payload['messageId'] as String?;
        if (mid == null) return null;
        return GetStatusCommand(messageId: mid);
      case 'UPDATE_APP':
        if (payload is! Map<String, dynamic>) return null;
        final mid = payload['messageId'] as String?;
        final url = payload['url'] as String?;
        final sha = payload['sha256'] as String?;
        final ver = payload['version'] as String?;
        if (mid == null || url == null || sha == null || ver == null) {
          return null;
        }
        return UpdateAppCommand(
          messageId: mid,
          url: url,
          sha256: sha,
          version: ver,
        );
      case 'CLEAR_CACHE':
        if (payload is! Map<String, dynamic>) return null;
        final mid = payload['messageId'] as String?;
        if (mid == null) return null;
        return ClearCacheCommand(messageId: mid);
      case 'OVERLAY_SHOW':
        if (payload is! Map<String, dynamic>) return null;
        final mid = payload['messageId'] as String?;
        final text = (payload['text'] as String?)?.trim() ?? '';
        if (mid == null) return null;
        final rawMedia = payload['mediaUrl'] ?? payload['imageUrl'];
        final mediaUrl = rawMedia is String && rawMedia.trim().isNotEmpty
            ? rawMedia.trim()
            : null;
        final mediaKindRaw = payload['mediaKind'] as String?;
        final mediaKind = mediaKindRaw?.trim().toLowerCase();
        final untilDismissed = payload['untilDismissed'] == null
            ? true
            : payload['untilDismissed'] == true;
        final durationRaw = payload['durationSec'];
        final durationSec = durationRaw is num ? durationRaw.round() : 10;
        final opacityRaw = payload['opacity'];
        final opacity = opacityRaw is num ? opacityRaw.toDouble() : 0.9;
        final createdAtRaw = payload['createdAt'] as String?;
        return OverlayShowCommand(
          messageId: mid,
          text: text,
          mediaUrl: mediaUrl,
          mediaKind: mediaKind,
          untilDismissed: untilDismissed,
          durationSec: durationSec.clamp(3, 1200),
          opacity: opacity.clamp(0.5, 1).toDouble(),
          commandType: payload['commandType'] as String?,
          contentType: payload['contentType'] as String?,
          createdAt: createdAtRaw != null ? DateTime.tryParse(createdAtRaw) : null,
        );
      case 'OVERLAY_HIDE':
        if (payload is! Map<String, dynamic>) return null;
        final mid = payload['messageId'] as String?;
        if (mid == null) return null;
        return OverlayHideCommand(messageId: mid);
      case 'ANNOUNCEMENT':
        if (payload is! Map<String, dynamic>) return null;
        final aid = payload['announcementId'] as String?;
        if (aid == null || aid.isEmpty) return null;
        final title = (payload['title'] as String?)?.trim();
        final bodyRaw = (payload['body'] as String?)?.trim();
        final ds = payload['durationSec'];
        final durationSec = ds is num ? ds.round() : 15;
        final rawMedia = payload['mediaUrl'] ?? payload['imageUrl'];
        final mediaUrl = rawMedia is String && rawMedia.trim().isNotEmpty
            ? rawMedia.trim()
            : null;
        final mediaKindRaw = payload['mediaKind'] as String?;
        final mediaKind = mediaKindRaw?.trim().toLowerCase();
        final mode = payload['mode'] as String?;
        final untilDismissed = payload['untilDismissed'] == true;
        final createdAtRaw = payload['createdAt'] as String?;
        final scheduleEndsRaw = payload['scheduleEndsAt'] as String?;
        return AnnouncementCommand(
          announcementId: aid,
          title: (title == null || title.isEmpty) ? 'Announcement' : title,
          body: (bodyRaw != null && bodyRaw.isNotEmpty) ? bodyRaw : null,
          durationSec: durationSec,
          mediaUrl: mediaUrl,
          mediaKind: mediaKind,
          mode: mode,
          untilDismissed: untilDismissed,
          commandType: payload['commandType'] as String?,
          contentType: payload['contentType'] as String?,
          createdAt: createdAtRaw != null ? DateTime.tryParse(createdAtRaw)?.toUtc() : null,
          scheduleEndsAtUtc:
              scheduleEndsRaw != null ? DateTime.tryParse(scheduleEndsRaw)?.toUtc() : null,
        );
      case 'ANNOUNCEMENT_CLEAR':
        if (payload is! Map<String, dynamic>) return const AnnouncementClearCommand();
        return AnnouncementClearCommand(
          announcementId: payload['announcementId'] as String?,
        );
      default:
        return null;
    }
  } on FormatException {
    return null;
  }
}
