import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../core/config/environment_config.dart';
import '../core/logging/kiosk_log.dart';
import '../features/player/data/kiosk_fleet_api.dart';
import '../services/device_service.dart';
import '../services/token_store.dart';

/// Registers FCM token + native push context when the kiosk is paired (Android).
class PushRegistrationCoordinator {
  PushRegistrationCoordinator({
    required TokenStore tokenStore,
    required KioskFleetApi fleetApi,
    required DeviceService device,
    required EnvironmentConfig env,
  })  : _tokenStore = tokenStore,
        _fleetApi = fleetApi,
        _device = device,
        _env = env;

  final TokenStore _tokenStore;
  final KioskFleetApi _fleetApi;
  final DeviceService _device;
  final EnvironmentConfig _env;

  bool _listening = false;
  StreamSubscription<String>? _tokenRefreshSub;
  Timer? _contextRefreshTimer;

  void start() {
    if (_listening) return;
    if (!Platform.isAndroid) return;
    _listening = true;
    _tokenStore.addListener(_sync);
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) async {
        await _postTokenSafe(token);
        await _sync();
      },
      onError: (Object e, StackTrace st) {
        KioskLog.e('PushRegistration.onTokenRefresh', e, st);
      },
    );
    _contextRefreshTimer ??= Timer.periodic(
      const Duration(minutes: 10),
      (_) => unawaited(_sync()),
    );
    unawaited(_sync());
  }

  void stop() {
    if (!_listening) return;
    _listening = false;
    _tokenStore.removeListener(_sync);
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _contextRefreshTimer?.cancel();
    _contextRefreshTimer = null;
  }

  Future<void> _postTokenSafe(String token) async {
    try {
      await _fleetApi.postPushToken(token: token, platform: 'android');
    } catch (e, st) {
      KioskLog.e('PushRegistration.postToken', e, st);
    }
  }

  Future<void> _sync() async {
    final paired = _tokenStore.hasPairedDevice;
    final access = _tokenStore.accessToken;
    final identity = _tokenStore.loadPairedDevice();
    if (!paired || access == null || access.isEmpty || identity == null) {
      return;
    }

    await _device.syncPushContextForNative(
      apiBaseUrl: _env.apiBaseUrl,
      accessToken: access,
      deviceId: identity.deviceId,
    );

    try {
      await FirebaseMessaging.instance.requestPermission();
      final fcm = await FirebaseMessaging.instance.getToken();
      if (fcm != null && fcm.isNotEmpty) {
        await _fleetApi.postPushToken(token: fcm, platform: 'android');
      }
    } catch (e, st) {
      KioskLog.e('PushRegistration.sync', e, st);
    }
  }
}
