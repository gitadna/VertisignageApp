import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import '../../../core/config/environment_config.dart';
import '../../../core/storage/local_storage.dart';
import '../../../kiosk/fleet_realtime_coordinator.dart';
import '../../../core/websocket/realtime_client.dart';
import '../../../kiosk/connectivity_coordinator.dart';
import '../../../services/device_service.dart';
import '../../../services/token_store.dart';
import '../data/device_heartbeat_service.dart';
import '../data/announcement_overlay_notifier.dart';
import '../data/emergency_overlay_notifier.dart';
import '../data/kiosk_fleet_api.dart';
import '../data/media_cache_service.dart';
import '../data/ota_update_service.dart';
import '../data/player_telemetry.dart';
import '../data/playlist_api.dart';
import '../data/playlist_storage.dart';
import '../data/playlist_sync_service.dart';
import '../data/realtime_dispatcher.dart';
import '../presentation/player_controller.dart';

/// Player feature wiring (does not alter core DI).
void registerPlayerModule(GetIt getIt) {
  getIt.registerLazySingleton<MediaCacheService>(
    () => MediaCacheService(
      persistentStorage: getIt<LocalStorage>(),
      maxCacheMb: getIt<EnvironmentConfig>().maxMediaCacheMb,
    ),
  );

  getIt.registerLazySingleton<PlaylistStorage>(
    () => PlaylistStorage(getIt<LocalStorage>()),
  );

  getIt.registerLazySingleton<PlaylistApi>(() => PlaylistApi(getIt<Dio>()));

  getIt.registerLazySingleton<DeviceHeartbeatService>(
    () => DeviceHeartbeatService(
      dio: getIt<Dio>(),
      tokenStore: getIt<TokenStore>(),
      telemetry: getIt<PlayerTelemetry>(),
      cache: getIt<MediaCacheService>(),
      device: getIt<DeviceService>(),
      storage: getIt<LocalStorage>(),
    ),
  );

  getIt.registerLazySingleton<PlaylistSyncService>(
    () => PlaylistSyncService(
      storage: getIt<PlaylistStorage>(),
      api: getIt<PlaylistApi>(),
      cache: getIt<MediaCacheService>(),
      tokenStore: getIt<TokenStore>(),
      heartbeat: getIt<DeviceHeartbeatService>(),
      telemetry: getIt<PlayerTelemetry>(),
    ),
  );

  getIt.registerLazySingleton<PlayerController>(
    () => PlayerController(
      cache: getIt<MediaCacheService>(),
      sync: getIt<PlaylistSyncService>(),
    ),
  );

  getIt.registerLazySingleton<EmergencyOverlayNotifier>(
    EmergencyOverlayNotifier.new,
  );

  getIt.registerLazySingleton<AnnouncementOverlayNotifier>(
    AnnouncementOverlayNotifier.new,
  );

  getIt.registerLazySingleton<ConnectivityCoordinator>(
    () => ConnectivityCoordinator(getIt<PlaylistSyncService>()),
  );

  getIt.registerLazySingleton<RealtimeDispatcher>(
    () => RealtimeDispatcher(
      realtime: getIt<RealtimeClient>(),
      playlistSync: getIt<PlaylistSyncService>(),
      emergencyOverlay: getIt<EmergencyOverlayNotifier>(),
      announcementOverlay: getIt<AnnouncementOverlayNotifier>(),
      player: getIt<PlayerController>(),
      tokenStore: getIt<TokenStore>(),
      device: getIt<DeviceService>(),
      fleetApi: getIt<KioskFleetApi>(),
      cache: getIt<MediaCacheService>(),
      ota: getIt<OtaUpdateService>(),
      telemetry: getIt<PlayerTelemetry>(),
    ),
  );

  getIt.registerLazySingleton<FleetRealtimeCoordinator>(
    () => FleetRealtimeCoordinator(
      tokenStore: getIt<TokenStore>(),
      dispatcher: getIt<RealtimeDispatcher>(),
      realtime: getIt<RealtimeClient>(),
    ),
  );
}
