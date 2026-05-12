import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'bootstrap/app_bootstrap.dart';
import 'core/logging/kiosk_log.dart';
import 'core/telemetry/fleet_telemetry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final mainStartedAt = DateTime.now().millisecondsSinceEpoch;

  // Critical: open Hive + register DI + critical post-bootstrap. Must stay light so first
  // frame paints quickly. Anything heavy (websocket, OTA, push) runs in `initDeferred`
  // after the first frame paints via BootSplash.
  await AppBootstrap.initCritical();
  KioskLog.event(
    'boot',
    'flutter_main_critical_done elapsedMs=${DateTime.now().millisecondsSinceEpoch - mainStartedAt}',
  );

  // Firebase init is moved into the deferred phase wrapper so it doesn't block first frame on
  // slow OEMs. It still runs before any websocket/push coordinator that depends on it because
  // those start inside `AppBootstrap.initDeferred` after this completes.
  Future<void> deferred() async {
    if (Platform.isAndroid) {
      try {
        await Firebase.initializeApp();
        FleetTelemetry.event('boot', 'firebase_initialized');
      } catch (error) {
        KioskLog.w('boot', 'Firebase.initializeApp failed', error);
        FleetTelemetry.event('boot', 'firebase_initialized_failed error=${error.runtimeType}');
      }
    }
    await AppBootstrap.initDeferred();
  }

  runApp(VertisignageApp(deferredInit: deferred));
}
