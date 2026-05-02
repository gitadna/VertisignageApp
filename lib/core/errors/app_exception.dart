/// Domain-level failures mapped from [DioException] and parsing errors.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'AppException: $message';
}

final class AppNetworkException extends AppException {
  const AppNetworkException(super.message, {super.cause, this.statusCode});

  final int? statusCode;
}

final class AppAuthException extends AppException {
  const AppAuthException(super.message, {super.cause});
}

final class AppParseException extends AppException {
  const AppParseException(super.message, {super.cause});
}
