import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import '../../../core/storage/local_storage.dart';
import '../../../services/token_store.dart';
import '../data/image_cache_service.dart';
import '../data/playlist_api.dart';
import '../data/playlist_storage.dart';
import '../data/playlist_sync_service.dart';
import '../presentation/player_controller.dart';

/// Player feature wiring (does not alter core DI).
void registerPlayerModule(GetIt getIt) {
  getIt.registerLazySingleton<ImageCacheService>(ImageCacheService.new);

  getIt.registerLazySingleton<PlaylistStorage>(
    () => PlaylistStorage(getIt<LocalStorage>()),
  );

  getIt.registerLazySingleton<PlaylistApi>(() => PlaylistApi(getIt<Dio>()));

  getIt.registerLazySingleton<PlaylistSyncService>(
    () => PlaylistSyncService(
      storage: getIt<PlaylistStorage>(),
      api: getIt<PlaylistApi>(),
      cache: getIt<ImageCacheService>(),
      tokenStore: getIt<TokenStore>(),
    ),
  );

  getIt.registerLazySingleton<PlayerController>(
    () => PlayerController(
      cache: getIt<ImageCacheService>(),
      sync: getIt<PlaylistSyncService>(),
    ),
  );
}
