import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../logging/kiosk_log.dart';

/// Debug-oriented logging; Authorization values are never printed.
class LoggingInterceptor extends Interceptor {
  static const bool _httpVerbose =
      bool.fromEnvironment('KIOSK_HTTP_LOG_VERBOSE', defaultValue: false);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode && _httpVerbose) {
      final headers = Map<String, dynamic>.from(options.headers);
      if (headers.containsKey('Authorization')) {
        headers['Authorization'] = 'Bearer ***';
      }
      KioskLog.d('http', '--> ${options.method} ${options.uri}\nHeaders: $headers');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode && _httpVerbose) {
      KioskLog.d(
        'http',
        '<-- ${response.statusCode} ${response.requestOptions.uri}',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Always keep errors visible in debug.
    KioskLog.w(
      'http',
      'request_failed ${err.requestOptions.method} ${err.requestOptions.uri}',
      err.message,
      err.stackTrace,
    );
    handler.next(err);
  }
}
