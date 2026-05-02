/// Extension point for refresh-token flows (pairing / login modules).
///
/// Return `true` if credentials were refreshed and the original request may retry.
abstract class AuthRefresher {
  Future<bool> refreshIfNeeded();
}

/// Default no-op until a real refresh pipeline is registered.
class NoOpAuthRefresher implements AuthRefresher {
  @override
  Future<bool> refreshIfNeeded() async => false;
}
