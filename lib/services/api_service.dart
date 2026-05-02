import 'package:dio/dio.dart';

/// Thin façade over HTTP — feature modules inject this and call typed APIs later.
class ApiService {
  ApiService(this._dio);

  final Dio _dio;

  Dio get client => _dio;
}
