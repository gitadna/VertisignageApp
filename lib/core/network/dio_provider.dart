import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_environment.dart';
import '../config/environment_config.dart';
import '../../services/auth_refresher.dart';
import '../../services/token_reader.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/error_mapper_interceptor.dart';
import 'interceptors/logging_interceptor.dart';
import 'interceptors/retry_interceptor.dart';

/// Builds a configured [Dio] instance for the Vertisignage API.
class DioProvider {
  DioProvider._();

  static Dio create({
    required EnvironmentConfig config,
    required TokenReader tokenReader,
    AuthRefresher? authRefresher,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: config.apiBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: const {'Content-Type': 'application/json'},
      ),
    );

    final auth = AuthInterceptor(
      dio: dio,
      tokenReader: tokenReader,
      authRefresher: authRefresher,
    );
    final retry = RetryInterceptor(dio: dio);

    // On error, Dio invokes interceptors from last to first — put [Retry] last so
    // it sees the raw [DioException] before [ErrorMapper] wraps it.
    dio.interceptors.addAll([
      auth,
      if (kDebugMode || config.environment != AppEnvironment.production)
        LoggingInterceptor(),
      ErrorMapperInterceptor(),
      retry,
    ]);

    return dio;
  }
}
