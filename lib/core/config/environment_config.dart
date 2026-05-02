import 'app_environment.dart';

/// Parsed `--dart-define` values and defaults for local development.
class EnvironmentConfig {
  EnvironmentConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.wsUrl,
    required this.kioskLockTask,
    required this.enableRemoteLogShipping,
    required this.enableOtaInstall,
    required this.enableSafeMode,
  });

  /// --dart-define=APP_ENV=development|staging|production
  final AppEnvironment environment;

  /// REST API origin including scheme and port, no trailing slash.
  ///
  /// **Android emulator:** use `--dart-define=API_BASE_URL=http://10.0.2.2:4000`
  /// (not `localhost`). The emulator’s `localhost` is the emulator itself; `10.0.2.2`
  /// is the host loopback. Physical devices: use your machine’s LAN IP.
  ///
  /// **WebSocket:** set matching `WS_URL`, e.g. `ws://10.0.2.2:4000/ws`.
  final String apiBaseUrl;

  /// WebSocket URL including path (e.g. `ws://localhost:4000/ws`).
  /// Device JWT is appended at runtime as `?token=` by `WebSocketRealtimeClient`.
  final String wsUrl;

  /// `--dart-define=KIOSK_LOCK_TASK=true` — Android screen pinning when supported.
  final bool kioskLockTask;

  /// Ship structured logs to `/api/devices/:id/logs` (Phase 8).
  final bool enableRemoteLogShipping;

  /// Allow UPDATE_APP → download + package installer (Android).
  final bool enableOtaInstall;

  /// Enable crash counting → safe mode UI.
  final bool enableSafeMode;

  bool get isProduction => environment == AppEnvironment.production;

  bool get isDevelopment => environment == AppEnvironment.development;

  /// Reads compile-time defines with sensible emulator defaults.
  factory EnvironmentConfig.fromDartDefines() {
    const envRaw = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    final env = _parseEnv(envRaw);

    const apiDefault = 'http://localhost:4000';
    const wsDefault = 'ws://localhost:4000/ws';

    const apiRaw = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: apiDefault,
    );
    const wsRaw = String.fromEnvironment('WS_URL', defaultValue: wsDefault);

    const lockRaw = String.fromEnvironment(
      'KIOSK_LOCK_TASK',
      defaultValue: 'false',
    );

    const remoteLogsRaw = String.fromEnvironment(
      'ENABLE_REMOTE_LOGS',
      defaultValue: 'true',
    );
    const otaRaw = String.fromEnvironment(
      'ENABLE_OTA_INSTALL',
      defaultValue: 'false',
    );
    const safeModeRaw = String.fromEnvironment(
      'ENABLE_SAFE_MODE',
      defaultValue: 'true',
    );

    final api = apiRaw.trim();
    final ws = wsRaw.trim();
    final lockLower = lockRaw.trim().toLowerCase();
    bool flag(String raw) {
      final l = raw.trim().toLowerCase();
      return l == 'true' || l == '1';
    }

    return EnvironmentConfig(
      environment: env,
      apiBaseUrl: api.isEmpty ? apiDefault : api,
      wsUrl: ws.isEmpty ? wsDefault : ws,
      kioskLockTask: lockLower == 'true' || lockLower == '1',
      enableRemoteLogShipping: flag(remoteLogsRaw),
      enableOtaInstall: flag(otaRaw),
      enableSafeMode: flag(safeModeRaw),
    );
  }

  static AppEnvironment _parseEnv(String raw) {
    switch (raw.toLowerCase()) {
      case 'staging':
        return AppEnvironment.staging;
      case 'production':
      case 'prod':
        return AppEnvironment.production;
      default:
        return AppEnvironment.development;
    }
  }
}
