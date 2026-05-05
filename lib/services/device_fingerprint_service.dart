import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Produces a stable per-device fingerprint for license recovery checks.
class DeviceFingerprintService {
  DeviceFingerprintService();

  Future<String> getFingerprint() async {
    try {
      final host = Platform.localHostname;
      final raw = [
        Platform.operatingSystem,
        Platform.operatingSystemVersion,
        host,
      ].join('|');
      return sha256.convert(utf8.encode(raw)).toString();
    } catch (_) {}
    return sha256.convert(utf8.encode('fallback:${DateTime.now().year}')).toString();
  }
}
