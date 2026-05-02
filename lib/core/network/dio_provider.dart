import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_environment.dart';
import '../config/environment_config.dart';
import '../../services/auth_refresher.dart';
import '../../services/token_reader.dart';
import '../../services/token_store.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/error_mapper_interceptor.dart';
import 'interceptors/logging_interceptor.dart';
import 'interceptors/retry_interceptor.dart';
import 'interceptors/session_invalidating_interceptor.dart';

/// Builds a configured [Dio] instance for the Vertisignage API.
class DioProvider {
  DioProvider._();

  static Dio create({
    required EnvironmentConfig config,
    required TokenReader tokenReader,
    required TokenStore tokenStore,
    AuthRefresher? authRefresher,
  }) {
    final isDev = config.environment != AppEnvironment.production;
    final dio = Dio(
      BaseOptions(
        baseUrl: config.apiBaseUrl,
        connectTimeout: Duration(seconds: isDev ? 60 : 30),
        receiveTimeout: Duration(seconds: isDev ? 90 : 30),
        sendTimeout: Duration(seconds: isDev ? 60 : 30),
        headers: const {'Content-Type': 'application/json'},
      ),
    );

    final auth = AuthInterceptor(
      dio: dio,
      tokenReader: tokenReader,
      authRefresher: authRefresher,
    );
    final sessionInvalidation = SessionInvalidatingInterceptor(tokenStore);
    final retry = RetryInterceptor(dio: dio);

    // On error, Dio invokes interceptors from last to first — put [Retry] last so
    // it sees the raw [DioException] before [ErrorMapper] wraps it.
    dio.interceptors.addAll([
      auth,
      sessionInvalidation,
      if (kDebugMode || config.environment != AppEnvironment.production)
        LoggingInterceptor(),
      ErrorMapperInterceptor(),
      retry,
    ]);

    return dio;
  }
}
