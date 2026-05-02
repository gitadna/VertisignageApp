import 'dart:async';

import 'package:dio/dio.dart';

import '../../../services/token_store.dart';

/// Clears kiosk session on 401 from authenticated device routes (not pairing).
class SessionInvalidatingInterceptor extends Interceptor {
  SessionInvalidatingInterceptor(this._tokenStore);

  final TokenStore _tokenStore;

  static bool _shouldInvalidate(RequestOptions o) {
    final p = o.uri.path;
    if (p == '/api/devices/pair') return false;
    return p.startsWith('/api/devices/');
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401 && _shouldInvalidate(err.requestOptions)) {
      unawaited(_tokenStore.invalidateDeviceSession());
    }
    handler.next(err);
  }
}
