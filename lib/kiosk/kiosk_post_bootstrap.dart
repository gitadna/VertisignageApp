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
import '../features/voice_broadcast/data/voice_broadcast_coordinator.dart';
import '../services/device_service.dart';
import '../services/token_store.dart';
import 'connectivity_coordinator.dart';
import 'fleet_realtime_coordinator.dart';
import 'foreground_presentation_coordinator.dart';
import 'push_registration_coordinator.dart';

/// Post-DI kiosk wiring: global errors, immersive chrome, connectivity, foreground, lock task.
abstract final class KioskPostBootstrap {
  static bool _notificationDeniedLogged = false;
  static bool _configured = false;

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
    if (_configured) {
      KioskLog.d('Kiosk', 'post-bootstrap already configured; skipping duplicate wiring');
      return;
    }
    _configured = true;
    sl<KioskRecoveryStore>().restoreGateFromDisk();
    final crashMarker = await sl<DeviceService>().consumeNativeCrashMarker();
    if (crashMarker['crashed'] == true) {
      await sl<KioskRecoveryStore>().recordCrashMarker();
    }
    await sl<RemoteLogUploader>().restoreFromDisk();
    KioskLog.bindRemoteSink(sl<RemoteLogUploader>().enqueue);
    GlobalErrorHandler.install();

    sl<FleetRealtimeCoordinator>().start();
    sl<VoiceBroadcastCoordinator>().start();
    KioskLog.event('voice_signal', 'voice_coordinator_started');
    sl<PushRegistrationCoordinator>().start();

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (!Platform.isAndroid) return;

    final env = sl<EnvironmentConfig>();
    final tokenStore = sl<TokenStore>();
    final device = sl<DeviceService>();

    // Enable boot recovery only after the first successful app launch.
    await device.setFirstLaunchCompleted(completed: true);
    await device.recoveryEnsurePeriodic('post_bootstrap');

    await device.startForegroundNotification();
    await _maybeLogNotificationDeniedOnce();

    await sl<ConnectivityCoordinator>().start();

    sl<ForegroundPresentationCoordinator>().start();

    final owner = await device.isDeviceOwner();
    if (owner && !env.kioskLockTask) {
      final cleared = await device.prepareManagedClassroomMode();
      KioskLog.d('Kiosk', 'managedClassroomPolicies=$cleared');
    }
    if (env.kioskLockTask && tokenStore.hasPairedDevice) {
      final ok = owner ? await device.applyKioskPoliciesAndEnter() : false;
      KioskLog.d('Kiosk', 'deviceOwner=$owner lockTask=$ok');
    }
  }
}
