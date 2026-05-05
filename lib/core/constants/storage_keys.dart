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
  static const String licenseId = 'license_id';
  static const String deviceName = 'device_name';

  /// Cached playlist snapshot `{ version, items }` from sync.
  static const String playlistBundleJson = 'playlist_bundle_json';

  /// ISO timestamps of recent fatal reports (for safe mode).
  static const String fatalCrashLogJson = 'fatal_crash_log_json';

  /// When true, UI stays in minimal recovery mode until cleared.
  static const String safeMode = 'safe_mode';

  /// JSON map of cache file path → last-access epoch ms (media LRU).
  static const String mediaCacheLruJson = 'media_cache_lru_json';

  /// JSON array of pending structured log entries (offline / retry).
  static const String remoteLogQueueJson = 'remote_log_queue_json';

  /// JSON array of serialized heartbeat payloads awaiting retry.
  static const String heartbeatRetryQueueJson = 'heartbeat_retry_queue_json';

  /// `'1'` once Android overlay + battery onboarding finished ([KioskPermissionsGate]).
  static const String kioskPowerSetupComplete = 'kiosk_power_setup_complete';
}
