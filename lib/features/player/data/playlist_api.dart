import 'package:dio/dio.dart';

import '../../../models/playlist_bundle.dart';
import '../../../models/playlist_item.dart';

/// Fetches device playlist from `GET /api/devices/:id/playlist`.
class PlaylistApi {
  PlaylistApi(this._dio);

  final Dio _dio;

  /// Returns `null` when the request fails (caller treats as silent offline).
  Future<PlaylistBundle?> fetchPlaylist(String deviceId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/devices/$deviceId/playlist',
      );
      final body = response.data;
      if (body == null || body['success'] != true) return null;
      final data = body['data'];
      if (data is! Map<String, dynamic>) return null;

      final version = data['version'] as String? ?? '';
      final rawItems = data['items'];
      final items = <PlaylistItem>[];
      if (rawItems is List) {
        for (final e in rawItems) {
          if (e is Map<String, dynamic>) {
            items.add(PlaylistItem.fromJson(e));
          }
        }
      }
      return PlaylistBundle(version: version, items: items);
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
