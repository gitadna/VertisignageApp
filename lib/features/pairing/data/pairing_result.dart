import '../../../models/device_identity.dart';

/// Result of `POST /api/devices/pair` including the kiosk device access token.
class PairingCompleteResult {
  const PairingCompleteResult({
    required this.identity,
    required this.accessToken,
  });

  final DeviceIdentity identity;
  final String accessToken;
}
