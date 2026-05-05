import 'dart:io';

import 'package:flutter/services.dart';

import '../core/logging/kiosk_log.dart';

/// Android/iOS platform hooks for volume, restart, reboot, lock-task (Android).
/// Failures are swallowed so realtime dispatch never breaks playback.
class DeviceService {
  DeviceService()
      : _device = const MethodChannel('vertisignage/device'),
        _kiosk = const MethodChannel('vertisignage/kiosk');

  final MethodChannel _device;
  final MethodChannel _kiosk;

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
  Future<void> restartApplication() async {
    if (!Platform.isAndroid) return;
    try {
      await _device.invokeMethod<void>('restartApp');
    } catch (e, st) {
      KioskLog.e('DeviceService.restartApp', e, st);
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

  /// Screen pinning / lock task (Android L+). May fail if not device owner.
  Future<bool> setLockTaskEnabled(bool enabled) async {
    if (!Platform.isAndroid) return false;
    try {
      final method = enabled ? 'startLockTask' : 'stopLockTask';
      final ok = await _device.invokeMethod<bool>(method);
      return ok ?? false;
    } catch (e, st) {
      KioskLog.e('DeviceService.lockTask', e, st);
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

  Future<void> wakeAppToForeground() async {
    if (!Platform.isAndroid) return;
    try {
      await _device.invokeMethod<void>('wakeApp');
    } catch (e, st) {
      KioskLog.e('DeviceService.wakeApp', e, st);
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
