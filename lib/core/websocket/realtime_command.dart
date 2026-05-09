import 'dart:convert';

/// Parsed server push (`{ "type", "payload" }`).
sealed class RealtimeCommand {
  const RealtimeCommand();
}

class PlaylistUpdatedCommand extends RealtimeCommand {
  const PlaylistUpdatedCommand({
    this.playlistId,
    this.forceImmediate = false,
    this.reason,
  });

  final String? playlistId;

  /// When true, the kiosk should swap to the freshly fetched playlist immediately, bypassing the
  /// normal slide-boundary commit. Set by the backend on content replacement / schedule edits so
  /// long videos do not delay live changes by their full duration.
  final bool forceImmediate;

  final String? reason;
}

class SyncRequestCommand extends RealtimeCommand {
  const SyncRequestCommand({this.forceImmediate = false, this.reason});

  final bool forceImmediate;
  final String? reason;
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
    this.resumePreviousPlayback = false,
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
  final bool resumePreviousPlayback;
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
    this.pushedAtUtc,
    this.resumePreviousPlayback = false,
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
  /// Last push time from server — used for overlap resolution (latest wins).
  final DateTime? pushedAtUtc;
  final bool resumePreviousPlayback;
}

class AnnouncementTransportCommand extends RealtimeCommand {
  const AnnouncementTransportCommand({
    required this.announcementId,
    required this.action,
    this.volume,
  });

  final String announcementId;
  final String action;
  final double? volume;
}

class AnnouncementClearCommand extends RealtimeCommand {
  const AnnouncementClearCommand({this.announcementId});
  final String? announcementId;
}

/// Ephemeral, fire-and-forget realtime content push from the admin console.
///
/// On receive, the kiosk pauses its current playlist, plays the pushed item
/// full-screen for [durationSec], then resumes the playlist. There is no
/// reconnect re-dispatch — if the device misses the window, it is missed.
class RealtimePushCommand extends RealtimeCommand {
  const RealtimePushCommand({
    required this.pushId,
    required this.contentKind,
    this.mediaUrl,
    this.mediaKind,
    this.text,
    this.caption,
    required this.durationSec,
    this.fitMode,
    this.muted = true,
    this.issuedAtUtc,
  });

  final String pushId;
  /// One of `image`, `video`, `url`, `text`.
  final String contentKind;
  final String? mediaUrl;
  final String? mediaKind;
  final String? text;
  final String? caption;
  final int durationSec;
  final String? fitMode;
  final bool muted;
  final DateTime? issuedAtUtc;
}

class RealtimePushClearCommand extends RealtimeCommand {
  const RealtimePushClearCommand({this.pushId});
  final String? pushId;
}

/// Remote control for the active realtime push (pause / resume / restart).
class RealtimePushControlCommand extends RealtimeCommand {
  const RealtimePushControlCommand({
    this.pushId,
    required this.action,
  });

  final String? pushId;
  /// One of `pause`, `resume`, `restart`.
  final String action;
}

String? _coerceNonEmptyString(dynamic raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _firstNonEmptyString(Iterable<dynamic> values) {
  for (final value in values) {
    final normalized = _coerceNonEmptyString(value);
    if (normalized != null) return normalized;
  }
  return null;
}

String _inferMediaKindFromUrl(String url) {
  final lower = url.toLowerCase();
  if (RegExp(r'\.(mp4|webm|m3u8|mov)(\?|$)').hasMatch(lower)) {
    return 'video';
  }
  if (RegExp(r'\.(png|jpe?g|gif|bmp|webp|svg)(\?|$)').hasMatch(lower)) {
    return 'image';
  }
  return 'url';
}

({String? mediaUrl, String? mediaKind}) _resolveIncomingMedia(
  Map<String, dynamic> payload,
) {
  final hintedKind = _coerceNonEmptyString(payload['mediaKind'])?.toLowerCase();
  final videoUrl = _coerceNonEmptyString(payload['videoUrl']);
  final imageUrl = _coerceNonEmptyString(payload['imageUrl']);
  final canonicalMediaUrl = _coerceNonEmptyString(payload['mediaUrl']);
  final directUrl = _coerceNonEmptyString(
    payload['url'] ??
        payload['pageUrl'] ??
        payload['targetUrl'] ??
        payload['linkUrl'] ??
        payload['contentUrl'],
  );

  if (hintedKind == 'video') {
    final mediaUrl = _firstNonEmptyString([
      videoUrl,
      canonicalMediaUrl,
      imageUrl,
      directUrl,
    ]);
    return (mediaUrl: mediaUrl, mediaKind: mediaUrl == null ? null : 'video');
  }
  if (hintedKind == 'image') {
    final mediaUrl = _firstNonEmptyString([
      imageUrl,
      canonicalMediaUrl,
      videoUrl,
      directUrl,
    ]);
    return (mediaUrl: mediaUrl, mediaKind: mediaUrl == null ? null : 'image');
  }
  if (hintedKind == 'url') {
    final mediaUrl = _firstNonEmptyString([
      directUrl,
      canonicalMediaUrl,
      videoUrl,
      imageUrl,
    ]);
    return (mediaUrl: mediaUrl, mediaKind: mediaUrl == null ? null : 'url');
  }

  // No trusted hint: enforce priority video > image > url > content.
  if (videoUrl != null) return (mediaUrl: videoUrl, mediaKind: 'video');
  if (imageUrl != null) return (mediaUrl: imageUrl, mediaKind: 'image');
  if (directUrl != null) return (mediaUrl: directUrl, mediaKind: 'url');
  if (canonicalMediaUrl != null) {
    return (
      mediaUrl: canonicalMediaUrl,
      mediaKind: _inferMediaKindFromUrl(canonicalMediaUrl),
    );
  }
  return (mediaUrl: null, mediaKind: null);
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
        final force = m?['forceImmediate'];
        return PlaylistUpdatedCommand(
          playlistId: m?['playlistId'] as String?,
          forceImmediate: force is bool ? force : force == true,
          reason: m?['reason'] as String?,
        );
      case 'SYNC_REQUEST':
      case 'SCHEDULE_UPDATED':
        final m = payload is Map<String, dynamic> ? payload : null;
        final force = m?['forceImmediate'];
        return SyncRequestCommand(
          forceImmediate: force is bool ? force : true,
          reason: m?['reason'] as String?,
        );
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
        final resolvedMedia = _resolveIncomingMedia(payload);
        final mediaUrl = resolvedMedia.mediaUrl;
        final mediaKind = resolvedMedia.mediaKind;
        final untilDismissed = payload['untilDismissed'] == null
            ? true
            : payload['untilDismissed'] == true;
        final durationRaw = payload['durationSec'];
        final durationSec = durationRaw is num ? durationRaw.round() : 10;
        final opacityRaw = payload['opacity'];
        final opacity = opacityRaw is num ? opacityRaw.toDouble() : 0.9;
        final createdAtRaw = payload['createdAt'] as String?;
        final resumePreviousPlayback = payload['resumePreviousPlayback'] == true;
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
          resumePreviousPlayback: resumePreviousPlayback,
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
        final resolvedMedia = _resolveIncomingMedia(payload);
        final mediaUrl = resolvedMedia.mediaUrl;
        final mediaKind = resolvedMedia.mediaKind;
        final mode = payload['mode'] as String?;
        final untilDismissed = payload['untilDismissed'] == true;
        final createdAtRaw = payload['createdAt'] as String?;
        final scheduleEndsRaw = payload['scheduleEndsAt'] as String?;
        final pushedAtRaw = payload['pushedAt'] as String?;
        final resumePreviousPlayback = payload['resumePreviousPlayback'] == true;
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
          pushedAtUtc: pushedAtRaw != null ? DateTime.tryParse(pushedAtRaw)?.toUtc() : null,
          resumePreviousPlayback: resumePreviousPlayback,
        );
      case 'ANNOUNCEMENT_TRANSPORT':
        if (payload is! Map<String, dynamic>) return null;
        final aid = payload['announcementId'] as String?;
        final action = (payload['action'] as String?)?.trim().toLowerCase();
        if (aid == null || aid.isEmpty || action == null || action.isEmpty) return null;
        final volRaw = payload['volume'];
        final volume = volRaw is num ? volRaw.toDouble() : null;
        return AnnouncementTransportCommand(
          announcementId: aid,
          action: action,
          volume: volume,
        );
      case 'ANNOUNCEMENT_CLEAR':
        if (payload is! Map<String, dynamic>) return const AnnouncementClearCommand();
        return AnnouncementClearCommand(
          announcementId: payload['announcementId'] as String?,
        );
      case 'REALTIME_PUSH':
        if (payload is! Map<String, dynamic>) return null;
        final pushId = _coerceNonEmptyString(payload['pushId']);
        final kind = _coerceNonEmptyString(payload['contentKind'])?.toLowerCase();
        if (pushId == null || kind == null) return null;
        if (kind != 'image' && kind != 'video' && kind != 'url' && kind != 'text') {
          return null;
        }
        final ds = payload['durationSec'];
        final durationSec = ds is num ? ds.round() : 30;
        final issuedAtRaw = _coerceNonEmptyString(payload['issuedAt']);
        final mutedRaw = payload['muted'];
        final muted = mutedRaw is bool ? mutedRaw : true;
        if (kind == 'text') {
          final text = _coerceNonEmptyString(payload['text']);
          if (text == null) return null;
          return RealtimePushCommand(
            pushId: pushId,
            contentKind: kind,
            text: text,
            caption: _coerceNonEmptyString(payload['caption']),
            durationSec: durationSec.clamp(5, 600),
            fitMode: _coerceNonEmptyString(payload['fitMode'])?.toLowerCase(),
            muted: muted,
            issuedAtUtc: issuedAtRaw != null
                ? DateTime.tryParse(issuedAtRaw)?.toUtc()
                : null,
          );
        }
        final resolvedMedia = _resolveIncomingMedia(payload);
        final mediaUrl = resolvedMedia.mediaUrl;
        if (mediaUrl == null) return null;
        return RealtimePushCommand(
          pushId: pushId,
          contentKind: kind,
          mediaUrl: mediaUrl,
          mediaKind: resolvedMedia.mediaKind ?? (kind == 'video'
              ? 'video'
              : kind == 'image'
                  ? 'image'
                  : 'url'),
          caption: _coerceNonEmptyString(payload['caption']),
          durationSec: durationSec.clamp(5, 600),
          fitMode: _coerceNonEmptyString(payload['fitMode'])?.toLowerCase(),
          muted: muted,
          issuedAtUtc: issuedAtRaw != null
              ? DateTime.tryParse(issuedAtRaw)?.toUtc()
              : null,
        );
      case 'REALTIME_PUSH_CLEAR':
        if (payload is! Map<String, dynamic>) {
          return const RealtimePushClearCommand();
        }
        return RealtimePushClearCommand(
          pushId: payload['pushId'] as String?,
        );
      case 'REALTIME_PUSH_CONTROL':
        if (payload is! Map<String, dynamic>) return null;
        final actionRaw = (payload['action'] as String?)?.trim().toLowerCase();
        final String action;
        switch (actionRaw) {
          case 'pause':
            action = 'pause';
          case 'resume':
            action = 'resume';
          case 'restart':
            action = 'restart';
          default:
            return null;
        }
        return RealtimePushControlCommand(
          pushId: _coerceNonEmptyString(payload['pushId']),
          action: action,
        );
      default:
        return null;
    }
  } on FormatException {
    return null;
  }
}
