import 'package:hive_flutter/hive_flutter.dart';

import '../core/di/injection.dart';
import '../features/pairing/di/register_pairing.dart';
import '../features/player/di/register_player.dart';
import '../kiosk/kiosk_post_bootstrap.dart';

/// Ordered startup: Hive, dependency injection, kiosk runtime.
class AppBootstrap {
  AppBootstrap._();

  static Future<void> init() async {
    await Hive.initFlutter();
    await configureDependencies();
    registerPairingModule(sl);
    registerPlayerModule(sl);
    await KioskPostBootstrap.configure(sl);
  }
}
