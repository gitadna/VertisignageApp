import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import '../config/environment_config.dart';
import '../recovery/kiosk_recovery_store.dart';
import '../recovery/safe_mode_gate.dart';
import '../storage/hive_local_storage.dart';
import '../storage/local_storage.dart';
import '../websocket/realtime_client.dart';
import '../websocket/websocket_realtime_client.dart';
import '../../services/api_service.dart';
import '../../services/auth_refresher.dart';
import '../../features/player/data/kiosk_fleet_api.dart';
import '../../features/player/data/kiosk_video_preferences.dart';
import '../../features/player/data/ota_update_service.dart';
import '../../features/player/data/player_telemetry.dart';
import '../../features/player/data/remote_log_uploader.dart';
import '../../kiosk/push_registration_coordinator.dart';
import '../../services/device_service.dart';
import '../../services/device_fingerprint_service.dart';
import '../../services/token_reader.dart';
import '../../services/token_store.dart';
import '../network/dio_provider.dart';

final GetIt sl = GetIt.instance;

bool _criticalRegistered = false;
bool _deferredRegistered = false;

/// Critical DI: synchronously required to produce a first frame and serve the player surface.
///
/// Must stay light: open Hive storage, register token/dio/api, register the small set of
/// services the player UI may dereference before [configureDeferredDependencies] completes.
/// Idempotent: safe to call multiple times. Side effects (Hive open) only run once.
Future<void> configureCriticalDependencies() async {
  if (_criticalRegistered) return;
  _criticalRegistered = true;

  final env = EnvironmentConfig.fromDartDefines();
  sl.registerSingleton<EnvironmentConfig>(env);

  final storage = HiveLocalStorage();
  await storage.init();
  sl.registerSingleton<LocalStorage>(storage);

  final tokenStore = TokenStore(storage);
  sl.registerSingleton<TokenStore>(tokenStore);
  sl.registerLazySingleton<TokenReader>(() => sl<TokenStore>());

  sl.registerLazySingleton<AuthRefresher>(() => NoOpAuthRefresher());

  final dio = DioProvider.create(
    config: env,
    tokenReader: tokenStore,
    tokenStore: tokenStore,
    authRefresher: sl<AuthRefresher>(),
  );
  sl.registerSingleton<Dio>(dio);

  sl.registerLazySingleton<ApiService>(() => ApiService(sl<Dio>()));

  sl.registerLazySingleton<SafeModeGate>(() => SafeModeGate());
  sl.registerLazySingleton<KioskRecoveryStore>(
    () => KioskRecoveryStore(sl<LocalStorage>(), sl<SafeModeGate>()),
  );

  sl.registerLazySingleton<PlayerTelemetry>(PlayerTelemetry.new);
  sl.registerLazySingleton<KioskVideoPreferences>(
    () => KioskVideoPreferences(sl<LocalStorage>()),
  );

  sl.registerLazySingleton<KioskFleetApi>(
    () => KioskFleetApi(dio: sl<Dio>(), tokenStore: tokenStore),
  );

  sl.registerLazySingleton<DeviceService>(DeviceService.new);
  sl.registerLazySingleton<DeviceFingerprintService>(
    () => DeviceFingerprintService(sl<LocalStorage>()),
  );
}

/// Deferred DI: heavier services that don't block first frame.
///
/// All registrations are still `LazySingleton`s, so they only construct on first access. The
/// real win is that the corresponding coordinators in [KioskPostBootstrap.configureDeferred]
/// only `.start()` AFTER the first frame is on screen.
///
/// Idempotent: safe to call multiple times.
Future<void> configureDeferredDependencies() async {
  if (_deferredRegistered) return;
  _deferredRegistered = true;

  final env = sl<EnvironmentConfig>();
  final tokenStore = sl<TokenStore>();

  sl.registerLazySingleton<RemoteLogUploader>(
    () => RemoteLogUploader(
      api: sl<KioskFleetApi>(),
      env: env,
      storage: sl<LocalStorage>(),
    ),
  );

  sl.registerLazySingleton<PushRegistrationCoordinator>(
    () => PushRegistrationCoordinator(
      tokenStore: sl<TokenStore>(),
      fleetApi: sl<KioskFleetApi>(),
      device: sl<DeviceService>(),
      env: env,
    ),
  );

  sl.registerLazySingleton<OtaUpdateService>(
    () => OtaUpdateService(
      env: env,
      fleetApi: sl<KioskFleetApi>(),
      device: sl<DeviceService>(),
    ),
  );

  sl.registerLazySingleton<RealtimeClient>(
    () => WebSocketRealtimeClient(
      wsBaseUrl: env.wsUrl,
      tokenStore: tokenStore,
    ),
  );
}

/// Backwards-compatible wrapper that runs both phases sequentially. Existing call sites that
/// expect a single `configureDependencies()` continue to work unchanged.
Future<void> configureDependencies() async {
  await configureCriticalDependencies();
  await configureDeferredDependencies();
}
