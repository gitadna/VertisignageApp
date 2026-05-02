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

class AnnouncementCommand extends RealtimeCommand {
  const AnnouncementCommand({
    required this.announcementId,
    required this.title,
    // Optional: kiosk overlay is media-only; uncomment usage if we show body text.
    this.body,
    required this.durationSec,
    this.mediaUrl,
    this.mediaKind,
  });

  final String announcementId;
  final String title;
  final String? body;
  final int durationSec;
  /// Resolved playback URL (legacy payloads used `imageUrl` only).
  final String? mediaUrl;
  /// Server hint: `image` or `video`.
  final String? mediaKind;
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
        final mediaKind = payload['mediaKind'] as String?;
        return AnnouncementCommand(
          announcementId: aid,
          title: (title == null || title.isEmpty) ? 'Announcement' : title,
          body: (bodyRaw != null && bodyRaw.isNotEmpty) ? bodyRaw : null,
          durationSec: durationSec,
          mediaUrl: mediaUrl,
          mediaKind: mediaKind,
        );
      default:
        return null;
    }
  } on FormatException {
    return null;
  }
}
