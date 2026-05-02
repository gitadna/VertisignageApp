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

  /// Hard restart process (returns to launcher intent).
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

  Future<void> stopForegroundNotification() async {
    if (!Platform.isAndroid) return;
    try {
      await _kiosk.invokeMethod<void>('stopForeground');
    } catch (_) {
      /* ignore */
    }
  }
}
