import 'dart:io';

import 'package:flutter/services.dart';

import '../core/logging/kiosk_log.dart';
import '../core/telemetry/fleet_telemetry.dart';

/// Android/iOS platform hooks for volume, restart, reboot, lock-task (Android).
/// Failures are swallowed so realtime dispatch never breaks playback.
class DeviceService {
  DeviceService()
      : _device = const MethodChannel('vertisignage/device'),
        _kiosk = const MethodChannel('vertisignage/kiosk'),
        _pushBridge = const MethodChannel('vertisignage/push_bridge');

  final MethodChannel _device;
  final MethodChannel _kiosk;
  final MethodChannel _pushBridge;

  /// Diagnostic snapshot of native watchdog state (no side effects).
  Future<Map<String, dynamic>> getHealthSnapshot() async {
    if (!Platform.isAndroid) return <String, dynamic>{'unsupported': true};
    try {
      final m = await _device.invokeMethod<dynamic>('getHealthSnapshot');
      if (m is Map) return Map<String, dynamic>.from(m);
    } catch (e, st) {
      KioskLog.e('DeviceService.getHealthSnapshot', e, st);
    }
    return <String, dynamic>{'error': true};
  }

  /// Module 4: push runtime visibility / player truth to native (throttled in [PresentationRuntimeHeartbeat]).
  Future<void> reportPresentationRuntimeHeartbeat(
    Map<String, Object?> payload,
  ) async {
    if (!Platform.isAndroid) return;
    try {
      await _device.invokeMethod<void>(
        'reportPresentationRuntimeHeartbeat',
        payload,
      );
    } catch (e, st) {
      KioskLog.e('DeviceService.reportPresentationRuntimeHeartbeat', e, st);
    }
  }

  /// Module 4 feature flags in native prefs (kill-switch without reinstall).
  Future<void> setM4FeatureFlags({
    bool? m4WatchdogEnabled,
    bool? m4SurfaceRecoveryEnabled,
    bool? m4OemProfileEnabled,
    bool? m4VisibilityEnforcementEnabled,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      final args = <String, dynamic>{};
      if (m4WatchdogEnabled != null) {
        args['m4WatchdogEnabled'] = m4WatchdogEnabled;
      }
      if (m4SurfaceRecoveryEnabled != null) {
        args['m4SurfaceRecoveryEnabled'] = m4SurfaceRecoveryEnabled;
      }
      if (m4OemProfileEnabled != null) {
        args['m4OemProfileEnabled'] = m4OemProfileEnabled;
      }
      if (m4VisibilityEnforcementEnabled != null) {
        args['m4VisibilityEnforcementEnabled'] = m4VisibilityEnforcementEnabled;
      }
      await _device.invokeMethod<void>('setM4FeatureFlags', args);
    } catch (e, st) {
      KioskLog.e('DeviceService.setM4FeatureFlags', e, st);
    }
  }

  /// Enables boot recovery only after first user launch.
  Future<bool> setFirstLaunchCompleted({bool completed = true}) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _device.invokeMethod<bool>(
        'setFirstLaunchCompleted',
        <String, dynamic>{'completed': completed},
      );
      return ok ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.setFirstLaunchCompleted', e, st);
      return false;
    }
  }

  /// Diagnostic: boot recovery pending marker set by native boot path.
  Future<Map<String, dynamic>> getPendingBootRecovery() async {
    if (!Platform.isAndroid) {
      return <String, dynamic>{
        'pending': false,
        'reason': null,
        'firstLaunchCompleted': true,
      };
    }
    try {
      final m = await _device.invokeMethod<dynamic>('getPendingBootRecovery');
      if (m is Map) {
        return Map<String, dynamic>.from(m);
      }
      return <String, dynamic>{
        'pending': false,
        'reason': 'unexpected_response',
        'firstLaunchCompleted': false,
      };
    } catch (e, st) {
      KioskLog.e('DeviceService.getPendingBootRecovery', e, st);
      return <String, dynamic>{
        'pending': false,
        'reason': 'error',
        'firstLaunchCompleted': false,
      };
    }
  }

  Future<bool> clearPendingBootRecovery() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _device.invokeMethod<bool>('clearPendingBootRecovery');
      return ok ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.clearPendingBootRecovery', e, st);
      return false;
    }
  }

  Future<Map<String, dynamic>> consumeNativeCrashMarker() async {
    if (!Platform.isAndroid) {
      return <String, dynamic>{'crashed': false, 'atMs': 0, 'reason': null};
    }
    try {
      final m = await _device.invokeMethod<dynamic>('consumeNativeCrashMarker');
      if (m is Map) {
        return Map<String, dynamic>.from(m);
      }
    } catch (e, st) {
      KioskLog.e('DeviceService.consumeNativeCrashMarker', e, st);
    }
    return <String, dynamic>{'crashed': false, 'atMs': 0, 'reason': null};
  }

  /// Explicitly kick native recovery scheduling (safe to call on resume).
  Future<void> recoveryEnqueueNow(String reason) async {
    if (!Platform.isAndroid) return;
    try {
      await _device.invokeMethod<void>('recoveryEnqueueNow', <String, dynamic>{'reason': reason});
    } catch (e, st) {
      KioskLog.e('DeviceService.recoveryEnqueueNow', e, st);
    }
  }

  Future<void> recoveryEnsurePeriodic(String reason) async {
    if (!Platform.isAndroid) return;
    try {
      await _device.invokeMethod<void>(
        'recoveryEnsurePeriodic',
        <String, dynamic>{'reason': reason},
      );
    } catch (e, st) {
      KioskLog.e('DeviceService.recoveryEnsurePeriodic', e, st);
    }
  }

  /// Music stream volume 0–100.
  Future<void> setVolumePercent(int percent) async {
    final p = percent.clamp(0, 100);
    if (!Platform.isAndroid) return;
    try {
      await _device.invokeMethod<void>('setVolume', <String, dynamic>{
        'percent': p,
      });
    } catch (e, st) {
      KioskLog.e('DeviceService.setVolume', e, st);
    }
  }

  Future<void> setMuted(bool muted) async {
    if (!Platform.isAndroid) return;
    try {
      await _device.invokeMethod<void>('setMuted', <String, dynamic>{
        'muted': muted,
      });
    } catch (e, st) {
      KioskLog.e('DeviceService.setMuted', e, st);
    }
  }

  Future<void> setBrightnessPercent(int percent) async {
    if (!Platform.isAndroid) return;
    final p = percent.clamp(1, 100);
    try {
      await _device.invokeMethod<void>('setBrightness', <String, dynamic>{
        'percent': p,
      });
    } catch (e, st) {
      KioskLog.e('DeviceService.setBrightness', e, st);
    }
  }

  /// Relaunch the app via Android launcher intent (same fix as admin “Restart screen”).
  ///
  /// Native side may return `false` when the call succeeds but the launch was deliberately
  /// suppressed by `RecoveryLoopGuard` (restart-storm dampening). The native layer already
  /// emits `recovery_restart_suppressed` telemetry; we mirror it on the Flutter side so the
  /// caller's intent ("we asked for a restart, native declined") is visible in remote logs
  /// alongside the rest of the kiosk event stream.
  Future<bool> restartApplication() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _device.invokeMethod<bool>('restartApp');
      final granted = ok ?? false;
      if (!granted) {
        FleetTelemetry.event(
          'recovery_loop',
          'restart_request_declined_by_native',
        );
      }
      return granted;
    } catch (e, st) {
      KioskLog.e('DeviceService.restartApp', e, st);
      return false;
    }
  }

  /// Device reboot — rarely permitted on retail builds; returns false if unavailable.
  Future<bool> rebootDevice() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _device.invokeMethod<bool>('rebootDevice');
      return ok ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.reboot', e, st);
      return false;
    }
  }

  /// Legacy lock-task toggle preserved for compatibility.
  /// Prefer [applyKioskPoliciesAndEnter] and [exitKioskAndClearPolicies].
  Future<bool> setLockTaskEnabled(bool enabled) async {
    if (enabled) return applyKioskPoliciesAndEnter();
    return exitKioskAndClearPolicies();
  }

  Future<bool> isDeviceOwner() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _device.invokeMethod<bool>('isDeviceOwner');
      return ok ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.isDeviceOwner', e, st);
      return false;
    }
  }

  Future<bool> applyKioskPoliciesAndEnter() async {
    if (!Platform.isAndroid) return false;
    try {
      final applied = await _device.invokeMethod<bool>('applyKioskPolicies');
      if (applied != true) return false;
      final entered = await _device.invokeMethod<bool>('startLockTask');
      return entered ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.applyKiosk', e, st);
      return false;
    }
  }

  Future<bool> exitKioskAndClearPolicies() async {
    if (!Platform.isAndroid) return false;
    try {
      final exited = await _device.invokeMethod<bool>('stopLockTask');
      final cleared = await _device.invokeMethod<bool>('clearKioskPolicies');
      return (exited ?? false) && (cleared ?? false);
    } catch (e, st) {
      KioskLog.e('DeviceService.exitKiosk', e, st);
      return false;
    }
  }

  Future<bool> isInLockTask() async {
    if (!Platform.isAndroid) return false;
    try {
      final inLockTask = await _device.invokeMethod<bool>('isInLockTask');
      return inLockTask ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.isInLockTask', e, st);
      return false;
    }
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final ok = await _device.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return ok ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.isIgnoringBatteryOptimizations', e, st);
      return false;
    }
  }

  Future<bool> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final opened = await _device.invokeMethod<bool>('openBatteryOptimizationSettings');
      return opened ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.openBatteryOptimizationSettings', e, st);
      return false;
    }
  }

  /// Opens Android **App info** for VertiSignage (permissions, battery, notifications, autostart on some OEMs).
  /// Manual trigger only; returns `false` if the activity cannot be resolved or launch fails.
  Future<bool> openAppSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final opened = await _device.invokeMethod<bool>('openAppSettings');
      final ok = opened ?? false;
      if (ok) {
        KioskLog.event('android_settings', 'app_info_opened');
      }
      return ok;
    } catch (e, st) {
      KioskLog.e('DeviceService.openAppSettings', e, st);
      return false;
    }
  }

  Future<bool> openAutoStartSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final opened = await _device.invokeMethod<bool>('openAutoStartSettings');
      return opened ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.openAutoStartSettings', e, st);
      return false;
    }
  }

  /// Starts native foreground service (notification) — Android only.
  Future<void> startForegroundNotification() async {
    if (!Platform.isAndroid) return;
    try {
      await _kiosk.invokeMethod<void>('startForeground');
    } catch (e, st) {
      KioskLog.e('DeviceService.foreground.start', e, st);
    }
  }

  Future<bool> wakeAppToForeground() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _device.invokeMethod<bool>('wakeApp');
      return ok ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.wakeApp', e, st);
      return false;
    }
  }

  /// Relaxed tablets (teacher mode): watchdog / alarms may skip bringing VertiSignage to the front.
  Future<void> configureForegroundWake({required bool relaxedTeacherMode}) async {
    if (!Platform.isAndroid) return;
    try {
      await _device.invokeMethod<void>(
        'configureForegroundWake',
        <String, dynamic>{'relaxedTeacherMode': relaxedTeacherMode},
      );
    } catch (e, st) {
      KioskLog.e('DeviceService.configureForegroundWake', e, st);
    }
  }

  /// Native recovery uses this together with backdrop hint (onUserLeaveHint) to decide wakes.
  Future<void> syncForegroundPresentationState({
    required bool presentationWantsForeground,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _device.invokeMethod<void>(
        'syncForegroundPresentationState',
        <String, dynamic>{
          'presentationWantsForeground': presentationWantsForeground,
        },
      );
    } catch (e, st) {
      KioskLog.e('DeviceService.syncForegroundPresentationState', e, st);
    }
  }

  Future<bool> moveTaskToBack() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _device.invokeMethod<bool>('moveTaskToBack');
      return ok ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.moveTaskToBack', e, st);
      return false;
    }
  }

  /// Native exact alarm as a belt-and-suspenders complement to the in-process boundary [Timer].
  ///
  /// [prewarmLeadMs] arms an additional prewarm alarm at `target - prewarmLeadMs` so the activity
  /// can be foregrounded *before* the boundary fires; [postcheckGraceMs] arms a verification alarm
  /// at `target + postcheckGraceMs` that escalates to a full restart if the UI heartbeat is stale.
  /// Defaults preserve native-side fallbacks when callers omit them.
  Future<bool> schedulePlaylistBoundaryAlarm({
    required int epochMs,
    int prewarmLeadMs = 10000,
    int postcheckGraceMs = 3000,
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _device.invokeMethod<bool>(
        'schedulePlaylistBoundaryAlarm',
        <String, dynamic>{
          'epochMs': epochMs,
          'prewarmLeadMs': prewarmLeadMs,
          'postcheckGraceMs': postcheckGraceMs,
        },
      );
      return ok ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.schedulePlaylistBoundaryAlarm', e, st);
      return false;
    }
  }

  Future<void> cancelPlaylistBoundaryAlarm() async {
    if (!Platform.isAndroid) return;
    try {
      await _device.invokeMethod<void>('cancelPlaylistBoundaryAlarm');
    } catch (e, st) {
      KioskLog.e('DeviceService.cancelPlaylistBoundaryAlarm', e, st);
    }
  }

  Future<bool> canScheduleExactAlarms() async {
    if (!Platform.isAndroid) return true;
    try {
      final ok = await _device.invokeMethod<bool>('canScheduleExactAlarms');
      return ok ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.canScheduleExactAlarms', e, st);
      return false;
    }
  }

  Future<bool> openExactAlarmSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _device.invokeMethod<bool>('openExactAlarmSettings');
      return ok ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.openExactAlarmSettings', e, st);
      return false;
    }
  }

  /// Device Owner only: clear strict kiosk policies so other apps remain usable (classroom mode).
  Future<bool> prepareManagedClassroomMode() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _device.invokeMethod<bool>('prepareManagedClassroomMode');
      return ok ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.prepareManagedClassroomMode', e, st);
      return false;
    }
  }

  /// Persist API base URL + device JWT for native FCM fallback (overlay when Flutter is dead).
  Future<void> syncPushContextForNative({
    required String apiBaseUrl,
    required String accessToken,
    required String deviceId,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _pushBridge.invokeMethod<void>(
        'syncPushContext',
        <String, dynamic>{
          'apiBaseUrl': apiBaseUrl.trim(),
          'accessToken': accessToken.trim(),
          'deviceId': deviceId.trim(),
        },
      );
    } catch (e, st) {
      KioskLog.e('DeviceService.syncPushContextForNative', e, st);
    }
  }

  /// Shared with native [PushDedupe]: returns false if this announcement was already consumed (FCM/native).
  Future<bool> pushDedupeTryConsume(String announcementId) async {
    if (!Platform.isAndroid) return true;
    final id = announcementId.trim();
    if (id.isEmpty) return true;
    try {
      final ok = await _pushBridge.invokeMethod<bool>(
        'pushDedupeTryConsume',
        <String, dynamic>{'announcementId': id},
      );
      return ok ?? true;
    } catch (e, st) {
      KioskLog.e('DeviceService.pushDedupeTryConsume', e, st);
      return true;
    }
  }

  Future<bool> canDrawOverlays() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _device.invokeMethod<bool>('canDrawOverlays');
      return ok ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.canDrawOverlays', e, st);
      return false;
    }
  }

  Future<bool> showOverlay({
    required String text,
    String? mediaUrl,
    String? mediaKind,
    bool untilDismissed = true,
    int durationSec = 10,
    double opacity = 0.9,
    int? scheduleEndsAtEpochMs,
    bool alarmPresentation = false,
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _device.invokeMethod<bool>(
        'showOverlay',
        <String, dynamic>{
          'text': text,
          if (mediaUrl != null && mediaUrl.trim().isNotEmpty) 'mediaUrl': mediaUrl.trim(),
          if (mediaKind?.isNotEmpty ?? false) 'mediaKind': mediaKind,
          'untilDismissed': untilDismissed,
          'durationSec': durationSec,
          'opacity': opacity,
          if (alarmPresentation) 'alarmPresentation': true,
          'scheduleEndsAtEpochMs': scheduleEndsAtEpochMs ?? 0,
        },
      );
      return ok ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.showOverlay', e, st);
      return false;
    }
  }

  Future<void> hideOverlay() async {
    if (!Platform.isAndroid) return;
    try {
      await _device.invokeMethod<void>('hideOverlay');
    } catch (e, st) {
      KioskLog.e('DeviceService.hideOverlay', e, st);
    }
  }

  Future<void> stopForegroundNotification() async {
    if (!Platform.isAndroid) return;
    try {
      await _kiosk.invokeMethod<void>('stopForeground');
    } catch (_) {
      /* ignore */
    }
  }

  /// Launch package installer for a local APK path (Android). Returns false if channel fails.
  Future<bool> installApk(String filePath) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _device.invokeMethod<bool>(
        'installApk',
        <String, dynamic>{'path': filePath},
      );
      return ok ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.installApk', e, st);
      return false;
    }
  }
}
