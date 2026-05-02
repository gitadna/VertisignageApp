import 'playlist_item.dart';

/// Persisted snapshot from the server with a version string for change detection.
class PlaylistBundle {
  const PlaylistBundle({
    required this.version,
    required this.items,
  });

  final String version;
  final List<PlaylistItem> items;

  Map<String, dynamic> toJson() => {
        'version': version,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory PlaylistBundle.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = <PlaylistItem>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          items.add(PlaylistItem.fromJson(e));
        }
      }
    }
    return PlaylistBundle(
      version: json['version'] as String? ?? '',
      items: items,
    );
  }
}
