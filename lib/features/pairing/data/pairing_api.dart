import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../models/device_identity.dart';

/// REST pairing against `POST /api/devices/pair`.
class PairingApi {
  PairingApi(this._dio);

  final Dio _dio;

  /// Completes pairing on the server and returns the persisted device record.
  Future<DeviceIdentity> pairDevice(String pairingCode) async {
    final normalized = pairingCode.trim().toUpperCase();
    if (normalized.isEmpty) {
      throw const AppNetworkException('Pairing code is required');
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/devices/pair',
        data: <String, dynamic>{'pairingCode': normalized},
      );

      final body = response.data;
      if (body == null) {
        throw const AppParseException('Empty response');
      }

      if (body['success'] != true) {
        final msg = _messageFromBody(body) ?? 'Pairing failed';
        throw AppNetworkException(
          msg,
          statusCode: response.statusCode,
        );
      }

      final raw = body['data'];
      if (raw is! Map<String, dynamic>) {
        throw const AppParseException('Invalid device payload');
      }

      return DeviceIdentity.fromApi(raw);
    } on DioException catch (e) {
      final mapped = _mapDioException(e);
      throw mapped;
    }
  }

  AppException _mapDioException(DioException e) {
    final serverMsg = _serverMessage(e);
    final mapped = e.error;
    if (mapped is AppException) {
      if (serverMsg != null && serverMsg.isNotEmpty) {
        return _withMessage(mapped, serverMsg, e.response?.statusCode);
      }
      return mapped;
    }
    return AppNetworkException(
      serverMsg ?? e.message ?? 'Network error',
      cause: e,
      statusCode: e.response?.statusCode,
    );
  }

  AppException _withMessage(
    AppException source,
    String message,
    int? httpStatus,
  ) {
    if (source is AppNetworkException) {
      return AppNetworkException(
        message,
        cause: source.cause,
        statusCode: httpStatus ?? source.statusCode,
      );
    }
    if (source is AppAuthException) {
      return AppAuthException(message, cause: source.cause);
    }
    if (source is AppParseException) {
      return AppParseException(message, cause: source.cause);
    }
    return AppNetworkException(message, statusCode: httpStatus);
  }

  String? _serverMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return null;
  }

  String? _messageFromBody(Map<String, dynamic> body) {
    final m = body['message'];
    return m is String ? m : null;
  }
}
