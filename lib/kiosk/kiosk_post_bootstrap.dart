import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/config/environment_config.dart';
import '../core/errors/global_error_handler.dart';
import '../core/logging/kiosk_log.dart';
import '../core/recovery/kiosk_recovery_store.dart';
import '../features/player/data/remote_log_uploader.dart';
import '../services/device_service.dart';
import '../services/token_store.dart';
import 'connectivity_coordinator.dart';
import 'fleet_realtime_coordinator.dart';
import 'push_registration_coordinator.dart';

/// Post-DI kiosk wiring: global errors, immersive chrome, connectivity, foreground, lock task.
abstract final class KioskPostBootstrap {
  static bool _notificationDeniedLogged = false;

  static Future<void> _maybeLogNotificationDeniedOnce() async {
    if (_notificationDeniedLogged) return;
    try {
      final android = await DeviceInfoPlugin().androidInfo;
      if (android.version.sdkInt < 33) return;
      if (await Permission.notification.isGranted) return;
      _notificationDeniedLogged = true;
      KioskLog.d(
        'Kiosk',
        'POST_NOTIFICATIONS denied on API ${android.version.sdkInt}; '
            'foreground notification / tap-to-return may be limited until onboarding grants it',
      );
    } catch (_) {
      /* ignore */
    }
  }

  static Future<void> configure(GetIt sl) async {
    sl<KioskRecoveryStore>().restoreGateFromDisk();
    await sl<RemoteLogUploader>().restoreFromDisk();
    KioskLog.bindRemoteSink(sl<RemoteLogUploader>().enqueue);
    GlobalErrorHandler.install();

    sl<FleetRealtimeCoordinator>().start();
    sl<PushRegistrationCoordinator>().start();

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (!Platform.isAndroid) return;

    final env = sl<EnvironmentConfig>();
    final tokenStore = sl<TokenStore>();
    final device = sl<DeviceService>();

    await device.startForegroundNotification();
    await _maybeLogNotificationDeniedOnce();

    await sl<ConnectivityCoordinator>().start();

    if (env.kioskLockTask && tokenStore.hasPairedDevice) {
      final owner = await device.isDeviceOwner();
      final ok = owner ? await device.applyKioskPoliciesAndEnter() : false;
      KioskLog.d('Kiosk', 'deviceOwner=$owner lockTask=$ok');
    }
  }
}
