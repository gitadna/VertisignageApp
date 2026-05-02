import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Debug-oriented logging; Authorization values are never printed.
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      final headers = Map<String, dynamic>.from(options.headers);
      if (headers.containsKey('Authorization')) {
        headers['Authorization'] = 'Bearer ***';
      }
      debugPrint('--> ${options.method} ${options.uri}\nHeaders: $headers');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint(
        '<-- ${response.statusCode} ${response.requestOptions.uri}',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint(
        '*** ERROR ${err.requestOptions.method} ${err.requestOptions.uri}: ${err.message}',
      );
    }
    handler.next(err);
  }
}
