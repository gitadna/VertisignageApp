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

  Future<void> postLogs(List<Map<String, dynamic>> logs) async {
    final device = _tokenStore.loadPairedDevice();
    final token = _tokenStore.accessToken;
    if (device == null || token == null || token.isEmpty || logs.isEmpty) {
      return;
    }
    try {
      await _dio.post<void>(
        '/api/devices/${device.deviceId}/logs',
        data: <String, dynamic>{'logs': logs},
      );
    } catch (_) {}
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
