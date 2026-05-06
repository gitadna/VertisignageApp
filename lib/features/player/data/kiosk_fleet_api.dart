import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../services/token_store.dart';

/// Device-authenticated fleet endpoints (logs + command acks). Never throws to callers of enqueue paths.
class KioskFleetApi {
  KioskFleetApi({
    required Dio dio,
    required TokenStore tokenStore,
  })  : _dio = dio,
        _tokenStore = tokenStore;

  final Dio _dio;
  final TokenStore _tokenStore;

  /// Returns `true` if the batch was accepted (2xx).
  Future<bool> postLogs(List<Map<String, dynamic>> logs) async {
    final device = _tokenStore.loadPairedDevice();
    final token = _tokenStore.accessToken;
    if (device == null || token == null || token.isEmpty || logs.isEmpty) {
      return false;
    }
    try {
      final res = await _dio.post<void>(
        '/api/devices/${device.deviceId}/logs',
        data: <String, dynamic>{'logs': logs},
      );
      final code = res.statusCode ?? 0;
      return code >= 200 && code < 300;
    } catch (_) {
      return false;
    }
  }

  Future<bool> postPushToken({
    required String token,
    String platform = 'android',
  }) async {
    final device = _tokenStore.loadPairedDevice();
    final access = _tokenStore.accessToken;
    if (device == null || access == null || access.isEmpty || token.isEmpty) {
      return false;
    }
    try {
      final res = await _dio.post<void>(
        '/api/devices/${device.deviceId}/push-token',
        data: <String, dynamic>{
          'token': token,
          'platform': platform,
        },
      );
      final code = res.statusCode ?? 0;
      return code >= 200 && code < 300;
    } catch (_) {
      return false;
    }
  }

  /// Fetches `{ type, payload }` envelope for FCM `ANNOUNCEMENT_REF` (paired device JWT).
  Future<String?> fetchAnnouncementWireJson(String announcementId) async {
    final device = _tokenStore.loadPairedDevice();
    final token = _tokenStore.accessToken;
    if (device == null || token == null || token.isEmpty || announcementId.isEmpty) {
      return null;
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/devices/${device.deviceId}/announcement-push/$announcementId',
      );
      final code = res.statusCode ?? 0;
      if (code < 200 || code >= 300) return null;
      final envelope = res.data?['data'];
      if (envelope is Map<String, dynamic>) {
        return jsonEncode(envelope);
      }
    } catch (_) {}
    return null;
  }

  Future<void> postCommandAck({
    required String messageId,
    required String commandType,
    required bool ok,
    Map<String, dynamic>? detail,
  }) async {
    final device = _tokenStore.loadPairedDevice();
    final token = _tokenStore.accessToken;
    if (device == null || token == null || token.isEmpty) return;
    try {
      await _dio.post<void>(
        '/api/devices/${device.deviceId}/command-ack',
        data: <String, dynamic>{
          'messageId': messageId,
          'commandType': commandType,
          'ok': ok,
          if (detail != null && detail.isNotEmpty) 'detail': detail,
        },
      );
    } catch (_) {}
  }
}
