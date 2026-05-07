import 'package:flutter/foundation.dart';
import 'dart:async';

import '../../../core/errors/app_exception.dart';
import '../../../models/auth_session.dart';
import '../../../models/device_identity.dart';
import '../../../services/device_fingerprint_service.dart';
import '../../../services/token_store.dart';
import '../data/pairing_api.dart';

enum PairingPhase { idle, loading, success, error }

/// Orchestrates pairing API + persistence; no UI.
class PairingController extends ChangeNotifier {
  PairingController({
    required PairingApi pairingApi,
    required TokenStore tokenStore,
    required DeviceFingerprintService fingerprintService,
  })  : _pairingApi = pairingApi,
        _tokenStore = tokenStore,
        _fingerprintService = fingerprintService;

  final PairingApi _pairingApi;
  final TokenStore _tokenStore;
  final DeviceFingerprintService _fingerprintService;
  // Keep this aligned with Dio receive timeout to avoid premature UI errors
  // while the request is still in-flight on slower LAN/dev setups.
  static const Duration _pairingTimeout = Duration(seconds: 90);

  PairingPhase phase = PairingPhase.idle;
  String? errorMessage;
  DeviceIdentity? lastPaired;

  Future<void> submit({
    required String rawLicenseId,
    required String rawDeviceName,
    String? rawOrgEnrollmentCode,
  }) async {
    if (phase == PairingPhase.loading) return;
    phase = PairingPhase.loading;
    errorMessage = null;
    notifyListeners();

    try {
      final fingerprint = await _fingerprintService.getFingerprint();
      final result = await _pairingApi
          .pairDevice(
            licenseId: rawLicenseId,
            deviceName: rawDeviceName,
            fingerprint: fingerprint,
            orgEnrollmentCode: rawOrgEnrollmentCode,
          )
          .timeout(_pairingTimeout);
      await _tokenStore.saveSession(
        AuthSession(accessToken: result.accessToken),
      );
      await _tokenStore.saveLicenseContext(
        licenseId: rawLicenseId,
        deviceName: rawDeviceName,
        orgEnrollmentCode: rawOrgEnrollmentCode,
      );
      await _tokenStore.savePairedDevice(result.identity);
      lastPaired = result.identity;
      phase = PairingPhase.success;
      notifyListeners();
    } on AppException catch (e) {
      phase = PairingPhase.error;
      errorMessage = e.message;
      notifyListeners();
    } on TimeoutException {
      phase = PairingPhase.error;
      errorMessage =
          'Pairing request timed out. Check API base URL/network and try again.';
      notifyListeners();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('PairingController.submit: $e\n$st');
      }
      phase = PairingPhase.error;
      errorMessage = 'Something went wrong';
      notifyListeners();
    }
  }

  Future<void> recoverFromSavedLicense() async {
    final licenseId = _tokenStore.savedLicenseId;
    final deviceName = _tokenStore.savedDeviceName;
    if (licenseId == null || deviceName == null) return;
    if (phase == PairingPhase.loading) return;
    await submit(
      rawLicenseId: licenseId,
      rawDeviceName: deviceName,
      rawOrgEnrollmentCode: null,
    );
  }

  Future<void> recoverFromFingerprint() async {
    if (phase == PairingPhase.loading) return;
    // Guard: never call the fingerprint-only register endpoint on a truly
    // fresh install. Without this, a new APK could match a colliding
    // fingerprint on the server and inherit another device's identity.
    final hasPriorContext =
        _tokenStore.savedLicenseId != null ||
        _tokenStore.savedDeviceName != null ||
        _tokenStore.loadPairedDevice() != null;
    if (!hasPriorContext) {
      phase = PairingPhase.idle;
      errorMessage = null;
      notifyListeners();
      return;
    }
    phase = PairingPhase.loading;
    errorMessage = null;
    notifyListeners();
    try {
      final fingerprint = await _fingerprintService.getFingerprint();
      final defaultName = _tokenStore.savedDeviceName ?? 'Android Screen';
      final result = await _pairingApi
          .recoverDevice(
            deviceName: defaultName,
            fingerprint: fingerprint,
          )
          .timeout(_pairingTimeout);
      await _tokenStore.saveSession(AuthSession(accessToken: result.accessToken));
      await _tokenStore.savePairedDevice(result.identity);
      final savedLicense = result.identity.licenseId;
      if (savedLicense != null && savedLicense.isNotEmpty) {
        await _tokenStore.saveLicenseContext(
          licenseId: savedLicense,
          deviceName: defaultName,
        );
      }
      lastPaired = result.identity;
      phase = PairingPhase.success;
      notifyListeners();
    } on AppException catch (e) {
      phase = PairingPhase.idle;
      errorMessage = e.message;
      notifyListeners();
    } on TimeoutException {
      phase = PairingPhase.idle;
      errorMessage =
          'Auto-recovery timed out. Verify API URL/network, then register manually.';
      notifyListeners();
    } catch (_) {
      phase = PairingPhase.idle;
      notifyListeners();
    }
  }

  void clearError() {
    if (phase != PairingPhase.error) return;
    phase = PairingPhase.idle;
    errorMessage = null;
    notifyListeners();
  }
}
