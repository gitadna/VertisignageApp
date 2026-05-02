/// Minimal playlist entry for kiosk playback (single-type assets for now).
class PlaylistItem {
  const PlaylistItem({
    required this.id,
    required this.type,
    required this.url,
    required this.durationMs,
    required this.order,
  });

  final String id;
  final String type;
  final String url;
  final int durationMs;
  final int order;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'url': url,
        'durationMs': durationMs,
        'order': order,
      };

  factory PlaylistItem.fromJson(Map<String, dynamic> json) {
    return PlaylistItem(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'image',
      url: json['url'] as String? ?? '',
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 10000,
      order: (json['order'] as num?)?.toInt() ?? 0,
    );
  }
}
