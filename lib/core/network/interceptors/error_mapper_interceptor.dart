import 'package:dio/dio.dart';

import '../../errors/app_exception.dart';

/// Maps [DioException] into [AppException] on the error slot for callers.
class ErrorMapperInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final mapped = _map(err);
    handler.next(err.copyWith(error: mapped));
  }

  AppException _map(DioException err) {
    final response = err.response;
    final code = response?.statusCode;

    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return AppNetworkException(
          'Connection timed out',
          cause: err,
          statusCode: code,
        );
      case DioExceptionType.badCertificate:
        return AppNetworkException(
          'Invalid TLS certificate',
          cause: err,
          statusCode: code,
        );
      case DioExceptionType.badResponse:
        if (code == 401 || code == 403) {
          return AppAuthException(
            response?.statusMessage ?? 'Unauthorized',
            cause: err,
          );
        }
        return AppNetworkException(
          response?.statusMessage ?? 'HTTP ${code ?? '?'}',
          cause: err,
          statusCode: code,
        );
      case DioExceptionType.cancel:
        return AppNetworkException('Request cancelled', cause: err);
      case DioExceptionType.connectionError:
        return AppNetworkException(
          'No network connection',
          cause: err,
          statusCode: code,
        );
      case DioExceptionType.unknown:
        final underlying = err.error;
        if (underlying is AppException) return underlying;
        return AppNetworkException(
          err.message ?? 'Network error',
          cause: err,
          statusCode: code,
        );
    }
  }
}
