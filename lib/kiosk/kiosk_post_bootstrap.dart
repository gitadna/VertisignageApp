import 'dart:io';

import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';

import '../core/config/environment_config.dart';
import '../core/errors/global_error_handler.dart';
import '../core/logging/kiosk_log.dart';
import '../core/recovery/kiosk_recovery_store.dart';
import '../features/player/data/remote_log_uploader.dart';
import '../services/device_service.dart';
import '../services/token_store.dart';
import 'connectivity_coordinator.dart';

/// Post-DI kiosk wiring: global errors, immersive chrome, connectivity, foreground, lock task.
abstract final class KioskPostBootstrap {
  static Future<void> configure(GetIt sl) async {
    sl<KioskRecoveryStore>().restoreGateFromDisk();
    KioskLog.bindRemoteSink(sl<RemoteLogUploader>().enqueue);
    GlobalErrorHandler.install();

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (!Platform.isAndroid) return;

    final env = sl<EnvironmentConfig>();
    final tokenStore = sl<TokenStore>();
    final device = sl<DeviceService>();

    await device.startForegroundNotification();

    await sl<ConnectivityCoordinator>().start();

    if (env.kioskLockTask && tokenStore.hasPairedDevice) {
      final ok = await device.setLockTaskEnabled(true);
      KioskLog.d('Kiosk', 'lockTask=$ok');
    }
  }
}
