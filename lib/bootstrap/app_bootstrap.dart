import 'package:hive_flutter/hive_flutter.dart';

import '../core/di/injection.dart';
import '../core/logging/kiosk_log.dart';
import '../core/telemetry/fleet_telemetry.dart';
import '../features/pairing/di/register_pairing.dart';
import '../features/player/di/register_player.dart';
import '../kiosk/kiosk_post_bootstrap.dart';

/// Staged Flutter bootstrap.
///
/// [initCritical] runs synchronously before `runApp`: Hive, critical DI, feature wiring, and
/// the lightweight half of [KioskPostBootstrap]. Heavy I/O (websocket/Firebase/OTA/push/etc.)
/// is moved to [initDeferred] which is invoked after the first frame paints so the splash
/// dismisses immediately.
class AppBootstrap {
  AppBootstrap._();

  static bool _criticalDone = false;
  static bool _deferredDone = false;
  static int? _criticalStartMs;

  /// Lightweight bootstrap suitable to run before `runApp`. Idempotent.
  static Future<void> initCritical() async {
    if (_criticalDone) return;
    final start = DateTime.now().millisecondsSinceEpoch;
    _criticalStartMs = start;
    await Hive.initFlutter();
    await configureCriticalDependencies();
    registerPairingModule(sl);
    registerPlayerModule(sl);
    await KioskPostBootstrap.configureCritical(sl);
    _criticalDone = true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - start;
    KioskLog.event('boot', 'flutter_critical_bootstrap_complete elapsedMs=$elapsed');
    FleetTelemetry.event('boot', 'flutter_critical_bootstrap_complete elapsedMs=$elapsed');
  }

  /// Heavy bootstrap suitable to run AFTER the first frame paints. Idempotent.
  ///
  /// Failures here must never block the UI: each downstream coordinator is responsible for its
  /// own retry/recovery, this only orchestrates ordering.
  static Future<void> initDeferred() async {
    if (_deferredDone) return;
    final start = DateTime.now().millisecondsSinceEpoch;
    KioskLog.event('boot', 'deferred_bootstrap_started');
    FleetTelemetry.event('boot', 'deferred_bootstrap_started');
    try {
      await configureDeferredDependencies();
      await KioskPostBootstrap.configureDeferred(sl);
    } catch (error, stackTrace) {
      KioskLog.e('boot', 'deferred_bootstrap_failed error=$error stack=$stackTrace');
      FleetTelemetry.event(
        'boot',
        'deferred_bootstrap_failed error=${error.runtimeType}',
      );
      rethrow;
    } finally {
      _deferredDone = true;
      final elapsed = DateTime.now().millisecondsSinceEpoch - start;
      final totalElapsed = _criticalStartMs == null
          ? elapsed
          : DateTime.now().millisecondsSinceEpoch - _criticalStartMs!;
      KioskLog.event(
        'boot',
        'deferred_bootstrap_complete elapsedMs=$elapsed totalSinceCriticalMs=$totalElapsed',
      );
      FleetTelemetry.event(
        'boot',
        'deferred_bootstrap_complete elapsedMs=$elapsed totalSinceCriticalMs=$totalElapsed',
      );
    }
  }

  /// Backwards-compatible single-call entrypoint. Internally runs both phases sequentially so
  /// any legacy caller (tests, scripts) keeps working.
  static Future<void> init() async {
    await initCritical();
    await initDeferred();
  }
}
