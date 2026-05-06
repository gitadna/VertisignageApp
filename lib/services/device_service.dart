import 'dart:io';

import 'package:flutter/services.dart';

import '../core/logging/kiosk_log.dart';

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
  Future<bool> restartApplication() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _device.invokeMethod<bool>('restartApp');
      return ok ?? false;
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
          'scheduleEndsAtEpochMs': ?scheduleEndsAtEpochMs,
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
