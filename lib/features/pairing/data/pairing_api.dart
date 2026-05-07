import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../models/device_identity.dart';
import 'pairing_result.dart';

/// REST pairing/register against kiosk bootstrap endpoints.
class PairingApi {
  PairingApi(this._dio);

  final Dio _dio;

  /// Completes pairing on the server; persists [PairingCompleteResult.accessToken] via [TokenStore].
  Future<PairingCompleteResult> pairDevice({
    required String licenseId,
    required String deviceName,
    String? fingerprint,
    String? orgEnrollmentCode,
  }) async {
    final normalized = licenseId.trim().toUpperCase();
    final normalizedName = deviceName.trim();
    final normalizedOrgCode = orgEnrollmentCode?.trim().toUpperCase();
    if (normalized.isEmpty) {
      throw const AppNetworkException('License ID is required');
    }
    if (normalizedName.isEmpty) {
      throw const AppNetworkException('Device name is required');
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/devices/register',
        data: <String, dynamic>{
          'licenseId': normalized,
          'pairingCode': normalized,
          'deviceName': normalizedName,
          if (fingerprint != null && fingerprint.isNotEmpty)
            'fingerprint': fingerprint,
          if (normalizedOrgCode != null && normalizedOrgCode.isNotEmpty)
            'orgEnrollmentCode': normalizedOrgCode,
        },
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

      final token = raw['accessToken'] as String?;
      if (token == null || token.isEmpty) {
        throw const AppParseException('Pairing response missing access token');
      }

      return PairingCompleteResult(
        identity: DeviceIdentity.fromApi(raw),
        accessToken: token,
      );
    } on DioException catch (e) {
      if (_isLocalhostOnDevice(e)) {
        throw const AppNetworkException(
          'This build still points at localhost. The API base URL is fixed at '
          'compile time (String.fromEnvironment), not at runtime. Stop the app, '
          'cd to the app folder, and run: flutter run --flavor kiosk '
          '--dart-define=API_BASE_URL=http://<PC_LAN_IP>:4000 '
          '--dart-define=WS_URL=ws://<PC_LAN_IP>:4000/ws — use your ipconfig '
          'IPv4. Hot reload does not change the URL. Or use USB: '
          'adb reverse tcp:4000 tcp:4000, then run with default localhost.',
        );
      }
      final mapped = _mapDioException(e);
      throw mapped;
    }
  }

  Future<PairingCompleteResult> recoverDevice({
    required String deviceName,
    required String fingerprint,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/devices/register',
        data: <String, dynamic>{
          'deviceName': deviceName.trim(),
          'fingerprint': fingerprint,
        },
      );
      final body = response.data;
      if (body == null) {
        throw const AppParseException('Empty response');
      }
      if (body['success'] != true) {
        final msg = _messageFromBody(body) ?? 'Recovery failed';
        throw AppNetworkException(msg, statusCode: response.statusCode);
      }
      final raw = body['data'];
      if (raw is! Map<String, dynamic>) {
        throw const AppParseException('Invalid device payload');
      }
      final token = raw['accessToken'] as String?;
      if (token == null || token.isEmpty) {
        throw const AppParseException('Recovery response missing access token');
      }
      return PairingCompleteResult(
        identity: DeviceIdentity.fromApi(raw),
        accessToken: token,
      );
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  /// [localhost] / [127.0.0.1] on a physical device never reaches the dev machine.
  bool _isLocalhostOnDevice(DioException e) {
    final base = _dio.options.baseUrl.toLowerCase();
    final pointsToLoopback =
        base.contains('localhost') || base.contains('127.0.0.1');
    if (!pointsToLoopback) return false;
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return true;
    }
    final msg = e.message?.toLowerCase() ?? '';
    return msg.contains('connection refused') || msg.contains('failed host lookup');
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
