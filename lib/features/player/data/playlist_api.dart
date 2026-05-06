import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../models/playlist_bundle.dart';
import '../../../models/playlist_item.dart';
import '../../../models/playlist_schedule_context.dart';

/// Fetches device playlist from `GET /api/devices/:id/playlist` (requires Bearer).
class PlaylistApi {
  PlaylistApi(this._dio);

  final Dio _dio;

  /// Returns `null` on transport/parse failure; throws [AppAuthException] on 401.
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

      PlaylistScheduleContext? schedule;
      final sch = data['schedule'];
      if (sch is Map<String, dynamic>) {
        schedule = PlaylistScheduleContext.fromJson(sch);
      }

      PlaylistOrganizationContext? organization;
      final org = data['organization'];
      if (org is Map<String, dynamic>) {
        organization = PlaylistOrganizationContext.fromJson(org);
      }

      DateTime? parseIso(String key) {
        final s = data[key] as String?;
        if (s == null || s.isEmpty) return null;
        return DateTime.tryParse(s)?.toUtc();
      }

      return PlaylistBundle(
        version: version,
        items: items,
        schedule: schedule,
        organization: organization,
        serverTimeUtc: parseIso('serverTimeUtc'),
        nextBoundaryUtc: parseIso('nextBoundaryUtc'),
      );
    } on DioException catch (e) {
      final inner = e.error;
      if (inner is AppAuthException) {
        throw inner;
      }
      if (e.response?.statusCode == 401) {
        final msg = _serverMessage(e) ?? 'Unauthorized';
        throw AppAuthException(msg, cause: e);
      }
      return null;
    } catch (e) {
      if (e is AppAuthException) rethrow;
      return null;
    }
  }

  String? _serverMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return null;
  }
}
