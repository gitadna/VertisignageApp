import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/config/environment_config.dart';
import '../core/errors/global_error_handler.dart';
import '../core/logging/kiosk_log.dart';
import '../core/recovery/kiosk_recovery_store.dart';
import '../core/telemetry/fleet_telemetry.dart';
import '../features/player/data/playlist_sync_service.dart';
import '../features/player/data/remote_log_uploader.dart';
import '../features/player/presentation/player_controller.dart';
import '../features/voice_broadcast/data/voice_broadcast_coordinator.dart';
import '../services/device_service.dart';
import '../services/token_store.dart';
import 'connectivity_coordinator.dart';
import 'fleet_realtime_coordinator.dart';
import 'foreground_presentation_coordinator.dart';
import 'presentation_runtime_heartbeat.dart';
import 'push_registration_coordinator.dart';
import 'recovery_analytics_from_native.dart';
import 'runtime_mode_coordinator.dart';

/// Post-DI kiosk wiring, split into critical (pre-first-frame) and deferred (post-first-frame).
abstract final class KioskPostBootstrap {
  static bool _notificationDeniedLogged = false;
  static bool _criticalConfigured = false;
  static bool _deferredConfigured = false;

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

  /// Critical wiring: only the lightweight bits required before the player surface can render.
  ///
  /// Must NOT start websocket, push, OTA, connectivity, voice, or foreground coordinators —
  /// those live in [configureDeferred]. Failures here must not block the UI: catch and log.
  static Future<void> configureCritical(GetIt sl) async {
    if (_criticalConfigured) {
      KioskLog.d('Kiosk', 'post-bootstrap critical already configured; skipping');
      return;
    }
    _criticalConfigured = true;

    try {
      sl<KioskRecoveryStore>().restoreGateFromDisk();
    } catch (e) {
      KioskLog.w('Kiosk', 'restoreGateFromDisk failed', e);
    }
    try {
      final crashMarker = await sl<DeviceService>().consumeNativeCrashMarker();
      if (crashMarker['crashed'] == true) {
        await sl<KioskRecoveryStore>().recordCrashMarker();
      }
    } catch (e) {
      KioskLog.w('Kiosk', 'consumeNativeCrashMarker failed', e);
    }

    GlobalErrorHandler.install();

    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (e) {
      KioskLog.w('Kiosk', 'setEnabledSystemUIMode failed', e);
    }
  }

  /// Deferred wiring: heavy I/O coordinators, websocket, push, OTA, connectivity, foreground.
  ///
  /// Idempotent; safe to call multiple times. Designed to run after the first frame paints so
  /// the splash dismisses immediately. Per-step exceptions are caught so a partial failure
  /// never blocks UI; the GlobalErrorHandler still records them.
  static Future<void> configureDeferred(GetIt sl) async {
    if (_deferredConfigured) {
      KioskLog.d('Kiosk', 'post-bootstrap deferred already configured; skipping');
      return;
    }
    _deferredConfigured = true;

    try {
      await sl<RemoteLogUploader>().restoreFromDisk();
      KioskLog.bindRemoteSink(sl<RemoteLogUploader>().enqueue);
    } catch (e) {
      KioskLog.w('Kiosk', 'RemoteLogUploader wiring failed', e);
    }

    try {
      RecoveryAnalyticsFromNative.start();
      RecoveryAnalyticsFromNative.onEvent = (message, meta) {
        sl<RuntimeModeCoordinator>().onNativeRecoveryAnalytics(message, meta);
      };
      sl<RuntimeModeCoordinator>().start();
    } catch (e) {
      KioskLog.w('Kiosk', 'RecoveryAnalyticsFromNative.start failed', e);
    }

    try {
      sl<FleetRealtimeCoordinator>().start();
      FleetTelemetry.event('boot', 'websocket_coordinator_started');
    } catch (e) {
      KioskLog.w('Kiosk', 'FleetRealtimeCoordinator.start failed', e);
    }
    try {
      sl<VoiceBroadcastCoordinator>().start();
      KioskLog.event('voice_signal', 'voice_coordinator_started');
    } catch (e) {
      KioskLog.w('Kiosk', 'VoiceBroadcastCoordinator.start failed', e);
    }
    try {
      sl<PushRegistrationCoordinator>().start();
    } catch (e) {
      KioskLog.w('Kiosk', 'PushRegistrationCoordinator.start failed', e);
    }

    _wireFirstFrameAfterBoundaryLogger(sl);

    if (!Platform.isAndroid) return;

    final env = sl<EnvironmentConfig>();
    final tokenStore = sl<TokenStore>();
    final device = sl<DeviceService>();

    try {
      await device.setFirstLaunchCompleted(completed: true);
      await device.recoveryEnsurePeriodic('post_bootstrap');
    } catch (e) {
      KioskLog.w('Kiosk', 'first_launch / periodic recovery failed', e);
    }

    try {
      await device.startForegroundNotification();
    } catch (e) {
      KioskLog.w('Kiosk', 'startForegroundNotification failed', e);
    }
    await _maybeLogNotificationDeniedOnce();

    try {
      await sl<ConnectivityCoordinator>().start();
    } catch (e) {
      KioskLog.w('Kiosk', 'ConnectivityCoordinator.start failed', e);
    }
    try {
      sl<ForegroundPresentationCoordinator>().start();
    } catch (e) {
      KioskLog.w('Kiosk', 'ForegroundPresentationCoordinator.start failed', e);
    }
    try {
      sl<PresentationRuntimeHeartbeat>().start();
    } catch (e) {
      KioskLog.w('Kiosk', 'PresentationRuntimeHeartbeat.start failed', e);
    }

    try {
      final owner = await device.isDeviceOwner();
      if (owner && !env.kioskLockTask) {
        final cleared = await device.prepareManagedClassroomMode();
        KioskLog.d('Kiosk', 'managedClassroomPolicies=$cleared');
      }
      if (env.kioskLockTask && tokenStore.hasPairedDevice) {
        final ok = owner ? await device.applyKioskPoliciesAndEnter() : false;
        KioskLog.d('Kiosk', 'deviceOwner=$owner lockTask=$ok');
      }
    } catch (e) {
      KioskLog.w('Kiosk', 'lock task / managed classroom setup failed', e);
    }
  }

  /// Backwards-compatible single entrypoint. Internally runs critical then deferred.
  static Future<void> configure(GetIt sl) async {
    await configureCritical(sl);
    await configureDeferred(sl);
  }

  /// Emits a [FleetTelemetry] `first_frame_after_boundary` event the first time the player
  /// surfaces a display state after each new schedule boundary. Read-only listener; no playback
  /// behavior changes here, this only measures wake-to-render latency for diagnostics.
  static void _wireFirstFrameAfterBoundaryLogger(GetIt sl) {
    final player = sl<PlayerController>();
    final playlistSync = sl<PlaylistSyncService>();
    DateTime? lastLoggedBoundary;
    void listener() {
      final boundary = playlistSync.currentBoundaryUtc;
      if (boundary == null) return;
      if (lastLoggedBoundary == boundary) return;
      if (player.display.value == null) return;
      final now = DateTime.now().toUtc();
      if (now.isBefore(boundary)) return;
      final deltaMs = now.difference(boundary).inMilliseconds;
      if (deltaMs > 60000) return;
      lastLoggedBoundary = boundary;
      FleetTelemetry.event(
        'playlist_schedule',
        'first_frame_after_boundary deltaMs=$deltaMs',
      );
    }

    player.display.addListener(listener);
  }
}
