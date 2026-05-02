import 'app_environment.dart';

/// Parsed `--dart-define` values and defaults for local development.
class EnvironmentConfig {
  EnvironmentConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.wsUrl,
  });

  /// --dart-define=APP_ENV=development|staging|production
  final AppEnvironment environment;

  /// REST API origin including scheme and port, no trailing slash.
  /// e.g. http://localhost:4000 (Android emulator → host machine)
  final String apiBaseUrl;

  /// WebSocket URL when the backend exposes one.
  final String wsUrl;

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

    final api = apiRaw.trim();
    final ws = wsRaw.trim();

    return EnvironmentConfig(
      environment: env,
      apiBaseUrl: api.isEmpty ? apiDefault : api,
      wsUrl: ws.isEmpty ? wsDefault : ws,
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
