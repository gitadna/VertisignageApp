import 'package:dio/dio.dart';

import '../../../services/auth_refresher.dart';
import '../../../services/token_reader.dart';

/// Attaches `Authorization: Bearer` when [TokenReader] returns a token.
///
/// On 401, optionally invokes [AuthRefresher] once and retries the request.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required Dio dio,
    required TokenReader tokenReader,
    AuthRefresher? authRefresher,
  })  : _dio = dio,
        _tokenReader = tokenReader,
        _authRefresher = authRefresher;

  final Dio _dio;
  final TokenReader _tokenReader;
  final AuthRefresher? _authRefresher;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _tokenReader.accessToken;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final refresher = _authRefresher;
    if (response?.statusCode == 401 &&
        refresher != null &&
        err.requestOptions.extra['_authRetry'] != true) {
      final ok = await refresher.refreshIfNeeded();
      if (ok) {
        final opts = err.requestOptions.copyWith(
          extra: {...err.requestOptions.extra, '_authRetry': true},
        );
        try {
          final clone = await _dio.fetch<dynamic>(opts);
          return handler.resolve(clone);
        } on DioException catch (e) {
          return handler.next(e);
        }
      }
    }
    handler.next(err);
  }
}
