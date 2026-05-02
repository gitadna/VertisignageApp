/// Server-resolved schedule metadata for time-aware playback (Phase 7).
class PlaylistScheduleContext {
  const PlaylistScheduleContext({
    required this.source,
    required this.playlistId,
    this.scheduleId,
    this.name,
    this.priority,
    this.timezone,
    this.windowStartUtc,
    this.windowEndUtc,
  });

  /// `schedule`, `fallback_org`, or `none` (strict: no active schedule window).
  final String source;
  final String playlistId;
  final String? scheduleId;
  final String? name;
  final String? priority;
  final String? timezone;
  final DateTime? windowStartUtc;
  final DateTime? windowEndUtc;

  Map<String, dynamic> toJson() => {
        'source': source,
        'playlistId': playlistId,
        if (scheduleId != null) 'scheduleId': scheduleId,
        if (name != null) 'name': name,
        if (priority != null) 'priority': priority,
        if (timezone != null) 'timezone': timezone,
        if (windowStartUtc != null)
          'windowStartUtc': windowStartUtc!.toIso8601String(),
        if (windowEndUtc != null)
          'windowEndUtc': windowEndUtc!.toIso8601String(),
      };

  factory PlaylistScheduleContext.fromJson(Map<String, dynamic> json) {
    DateTime? parseIso(String? key) {
      final s = json[key] as String?;
      if (s == null || s.isEmpty) return null;
      return DateTime.tryParse(s)?.toUtc();
    }

    return PlaylistScheduleContext(
      source: json['source'] as String? ?? 'fallback_org',
      playlistId: json['playlistId'] as String? ?? '',
      scheduleId: json['scheduleId'] as String?,
      name: json['name'] as String?,
      priority: json['priority'] as String?,
      timezone: json['timezone'] as String?,
      windowStartUtc: parseIso('windowStartUtc'),
      windowEndUtc: parseIso('windowEndUtc'),
    );
  }
}
