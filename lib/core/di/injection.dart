import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import '../config/environment_config.dart';
import '../storage/hive_local_storage.dart';
import '../storage/local_storage.dart';
import '../websocket/realtime_client.dart';
import '../websocket/websocket_realtime_client.dart';
import '../../services/api_service.dart';
import '../../services/auth_refresher.dart';
import '../../services/device_service.dart';
import '../../services/token_reader.dart';
import '../../services/token_store.dart';
import '../network/dio_provider.dart';

final GetIt sl = GetIt.instance;

/// Registers app-wide singletons. Call after [Hive.initFlutter] and storage init.
Future<void> configureDependencies() async {
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

  sl.registerLazySingleton<DeviceService>(DeviceService.new);

  sl.registerLazySingleton<RealtimeClient>(
    () => WebSocketRealtimeClient(
      wsBaseUrl: env.wsUrl,
      tokenStore: tokenStore,
    ),
  );
}
