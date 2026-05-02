import 'package:flutter_test/flutter_test.dart';
import 'package:vertisignage/models/playlist_bundle.dart';
import 'package:vertisignage/models/playlist_item.dart';
import 'package:vertisignage/models/playlist_schedule_context.dart';

void main() {
  test('PlaylistBundle JSON roundtrip', () {
    const bundle = PlaylistBundle(
      version: '2025-01-01T00:00:00.000Z',
      items: [
        PlaylistItem(
          id: 'a',
          mediaKind: PlaylistMediaKind.image,
          url: 'https://example.com/x.jpg',
          durationMs: 3000,
          order: 0,
          muted: false,
          transition: 'fade',
          fitMode: 'fit',
        ),
      ],
    );
    final back = PlaylistBundle.fromJson(bundle.toJson());
    expect(back.version, bundle.version);
    expect(back.items.length, 1);
    expect(back.items.first.url, bundle.items.first.url);
    expect(back.items.first.mediaKind, PlaylistMediaKind.image);
    expect(back.items.first.fitMode, 'fit');
  });

  test('PlaylistBundle JSON roundtrip with schedule metadata', () {
    final t = DateTime.utc(2026, 5, 2, 12, 0);
    final bundle = PlaylistBundle(
      version: 'v1',
      items: const [],
      schedule: const PlaylistScheduleContext(
        source: 'schedule',
        playlistId: 'pl1',
        scheduleId: 'sch1',
        priority: 'high',
      ),
      serverTimeUtc: t,
      nextBoundaryUtc: t.add(const Duration(hours: 1)),
    );
    final back = PlaylistBundle.fromJson(bundle.toJson());
    expect(back.schedule?.playlistId, 'pl1');
    expect(back.schedule?.scheduleId, 'sch1');
    expect(back.nextBoundaryUtc?.hour, 13);
  });

  test('PlaylistBundle roundtrip with schedule source none (strict)', () {
    final bundle = PlaylistBundle(
      version: 'none|boundary|org',
      items: const [],
      schedule: const PlaylistScheduleContext(
        source: 'none',
        playlistId: '',
      ),
    );
    final back = PlaylistBundle.fromJson(bundle.toJson());
    expect(back.schedule?.source, 'none');
    expect(back.schedule?.playlistId, '');
    expect(back.items, isEmpty);
  });
}
