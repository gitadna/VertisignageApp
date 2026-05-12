import 'dart:io';

import '../../core/logging/kiosk_log.dart';
import '../../services/device_service.dart';

/// Opens the system **App info** screen for VertiSignage (`Settings` → app details).
///
/// Use only after an explicit user action (installer / admin). Never call on a timer.
/// Safe on phones, TVs, and OEM signage builds: failures are swallowed and logged.
Future<bool> openAndroidApplicationDetailsSettings(DeviceService device) async {
  if (!Platform.isAndroid) return false;
  try {
    final ok = await device.openAppSettings();
    if (!ok) {
      KioskLog.w('AndroidAppInfo', 'open_app_settings_returned_false');
    }
    return ok;
  } catch (e, st) {
    KioskLog.e('AndroidAppInfo', e, st);
    return false;
  }
}
