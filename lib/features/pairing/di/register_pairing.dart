import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import '../../../services/token_store.dart';
import '../data/pairing_api.dart';
import '../presentation/pairing_controller.dart';

/// Feature wiring for pairing (core DI stays in [core/di/injection.dart]).
void registerPairingModule(GetIt getIt) {
  getIt.registerLazySingleton<PairingApi>(() => PairingApi(getIt<Dio>()));

  getIt.registerFactory<PairingController>(
    () => PairingController(
      pairingApi: getIt<PairingApi>(),
      tokenStore: getIt<TokenStore>(),
    ),
  );
}
