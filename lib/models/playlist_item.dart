/// Typed kiosk playlist row (`image` | `video` | `url` from API `type`).
enum PlaylistMediaKind {
  image,
  video,
  url;

  static PlaylistMediaKind parse(String? raw) {
    switch ((raw ?? 'image').toLowerCase()) {
      case 'video':
        return PlaylistMediaKind.video;
      case 'url':
        return PlaylistMediaKind.url;
      default:
        return PlaylistMediaKind.image;
    }
  }

  /// Serialized `type` field for JSON bodies.
  String get wireValue => switch (this) {
        PlaylistMediaKind.image => 'image',
        PlaylistMediaKind.video => 'video',
        PlaylistMediaKind.url => 'url',
      };
}

/// Playlist entry from `GET /api/devices/:id/playlist`.
class PlaylistItem {
  const PlaylistItem({
    required this.id,
    required this.mediaKind,
    required this.url,
    required this.durationMs,
    required this.order,
    this.muted = false,
    this.transition = 'fade',
    this.fitMode = 'fill',
  });

  final String id;
  final PlaylistMediaKind mediaKind;
  final String url;
  final int durationMs;
  final int order;

  /// Applies to video playback (playlist row default from CMS).
  final bool muted;

  /// CMS transition id: `fade`, `slideUp`, `slideDown`, `slideLeft`, `slideRight`, `zoom`.
  final String transition;

  /// CMS fit mode: `fill` (cover), `fit` (contain), `stretch`.
  final String fitMode;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': mediaKind.wireValue,
        'url': url,
        'durationMs': durationMs,
        'order': order,
        'muted': muted,
        'transition': transition,
        'fitMode': fitMode,
      };

  factory PlaylistItem.fromJson(Map<String, dynamic> json) {
    return PlaylistItem(
      id: json['id'] as String? ?? '',
      mediaKind: PlaylistMediaKind.parse(json['type'] as String?),
      url: json['url'] as String? ?? '',
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 10000,
      order: (json['order'] as num?)?.toInt() ?? 0,
      muted: json['muted'] as bool? ?? false,
      transition: (json['transition'] as String?)?.toLowerCase() ?? 'fade',
      fitMode: (json['fitMode'] as String?)?.toLowerCase() ?? 'fill',
    );
  }
}
