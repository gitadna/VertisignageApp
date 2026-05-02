import 'package:dio/dio.dart';

import '../../constants/app_constants.dart';
import '../../utils/exponential_backoff.dart';

/// Retries GET and other safe/idempotent requests on transient failures.
class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    required Dio dio,
    this.maxRetries = AppConstants.httpMaxRetries,
  }) : _dio = dio;

  final Dio _dio;
  final int maxRetries;

  bool _isIdempotent(RequestOptions options) {
    final m = options.method.toUpperCase();
    if (m == 'GET' || m == 'HEAD' || m == 'OPTIONS') return true;
    final extra = options.extra['idempotent'];
    return extra == true;
  }

  bool _isTransient(DioException err) {
    final code = err.response?.statusCode;
    if (code == 502 || code == 503 || code == 504) return true;
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      default:
        return false;
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final req = err.requestOptions;
    final attempt = (req.extra['_retry_attempt'] as int?) ?? 0;

    if (!_isIdempotent(req) ||
        !_isTransient(err) ||
        attempt >= maxRetries) {
      handler.next(err);
      return;
    }

    final delay = computeBackoffDelay(attemptIndex: attempt);
    await Future<void>.delayed(delay);

    final next = req.copyWith(
      extra: {...req.extra, '_retry_attempt': attempt + 1},
    );

    try {
      final response = await _dio.fetch<dynamic>(next);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
