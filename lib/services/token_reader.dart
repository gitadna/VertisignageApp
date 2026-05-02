/// Minimal surface for attaching Bearer tokens without coupling to storage.
abstract class TokenReader {
  String? get accessToken;
}
