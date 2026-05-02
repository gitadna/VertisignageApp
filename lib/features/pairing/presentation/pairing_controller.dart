import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../../../models/auth_session.dart';
import '../../../models/device_identity.dart';
import '../../../services/token_store.dart';
import '../data/pairing_api.dart';

enum PairingPhase { idle, loading, success, error }

/// Orchestrates pairing API + persistence; no UI.
class PairingController extends ChangeNotifier {
  PairingController({
    required PairingApi pairingApi,
    required TokenStore tokenStore,
  })  : _pairingApi = pairingApi,
        _tokenStore = tokenStore;

  final PairingApi _pairingApi;
  final TokenStore _tokenStore;

  PairingPhase phase = PairingPhase.idle;
  String? errorMessage;
  DeviceIdentity? lastPaired;

  Future<void> submit(String rawCode) async {
    phase = PairingPhase.loading;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await _pairingApi.pairDevice(rawCode);
      await _tokenStore.saveSession(
        AuthSession(accessToken: result.accessToken),
      );
      await _tokenStore.savePairedDevice(result.identity);
      lastPaired = result.identity;
      phase = PairingPhase.success;
      notifyListeners();
    } on AppException catch (e) {
      phase = PairingPhase.error;
      errorMessage = e.message;
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

  void clearError() {
    if (phase != PairingPhase.error) return;
    phase = PairingPhase.idle;
    errorMessage = null;
    notifyListeners();
  }
}
