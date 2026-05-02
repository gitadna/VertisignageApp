/// Hive box names and key strings for persisted state.
abstract final class StorageKeys {
  static const String authBox = 'auth';
  static const String deviceBox = 'device';

  static const String accessToken = 'access_token';
  static const String refreshToken = 'refresh_token';
  static const String accessTokenExpiresAt = 'access_token_expires_at';

  static const String deviceId = 'device_id';
  static const String orgId = 'org_id';

  /// Full paired device record as JSON (see [DeviceIdentity]).
  static const String pairedDeviceJson = 'paired_device_json';

  /// Cached playlist snapshot `{ version, items }` from sync.
  static const String playlistBundleJson = 'playlist_bundle_json';
}
