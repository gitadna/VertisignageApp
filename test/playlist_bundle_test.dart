import 'package:flutter_test/flutter_test.dart';
import 'package:vertisignage/models/playlist_bundle.dart';
import 'package:vertisignage/models/playlist_item.dart';

void main() {
  test('PlaylistBundle JSON roundtrip', () {
    const bundle = PlaylistBundle(
      version: '2025-01-01T00:00:00.000Z',
      items: [
        PlaylistItem(
          id: 'a',
          type: 'image',
          url: 'https://example.com/x.jpg',
          durationMs: 3000,
          order: 0,
        ),
      ],
    );
    final back = PlaylistBundle.fromJson(bundle.toJson());
    expect(back.version, bundle.version);
    expect(back.items.length, 1);
    expect(back.items.first.url, bundle.items.first.url);
  });
}
