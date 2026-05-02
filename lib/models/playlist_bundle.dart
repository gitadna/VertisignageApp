import 'playlist_item.dart';
import 'playlist_schedule_context.dart';

/// Persisted snapshot from the server with a version string for change detection.
class PlaylistBundle {
  const PlaylistBundle({
    required this.version,
    required this.items,
    this.schedule,
    this.serverTimeUtc,
    this.nextBoundaryUtc,
  });

  final String version;
  final List<PlaylistItem> items;
  final PlaylistScheduleContext? schedule;
  final DateTime? serverTimeUtc;
  final DateTime? nextBoundaryUtc;

  Map<String, dynamic> toJson() => {
        'version': version,
        'items': items.map((e) => e.toJson()).toList(),
        if (schedule != null) 'schedule': schedule!.toJson(),
        if (serverTimeUtc != null)
          'serverTimeUtc': serverTimeUtc!.toIso8601String(),
        if (nextBoundaryUtc != null)
          'nextBoundaryUtc': nextBoundaryUtc!.toIso8601String(),
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

    PlaylistScheduleContext? schedule;
    final sch = json['schedule'];
    if (sch is Map<String, dynamic>) {
      schedule = PlaylistScheduleContext.fromJson(sch);
    }

    DateTime? parseIso(String key) {
      final s = json[key] as String?;
      if (s == null || s.isEmpty) return null;
      return DateTime.tryParse(s)?.toUtc();
    }

    return PlaylistBundle(
      version: json['version'] as String? ?? '',
      items: items,
      schedule: schedule,
      serverTimeUtc: parseIso('serverTimeUtc'),
      nextBoundaryUtc: parseIso('nextBoundaryUtc'),
    );
  }
}
