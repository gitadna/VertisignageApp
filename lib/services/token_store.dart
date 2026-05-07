import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/constants/storage_keys.dart';
import '../core/storage/local_storage.dart';
import '../models/auth_session.dart';
import '../models/device_identity.dart';
import 'token_reader.dart';

/// Hive-backed token persistence implementing [TokenReader].
class TokenStore extends ChangeNotifier implements TokenReader {
  TokenStore(this._storage);

  final LocalStorage _storage;
  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  Future<void> _writeSecure(String key, String? value) async {
    try {
      if (value == null) {
        await _secure.delete(key: key);
      } else {
        await _secure.write(key: key, value: value);
      }
    } catch (_) {}
  }

  @override
  String? get accessToken {
    return _storage.getString(StorageKeys.authBox, StorageKeys.accessToken);
  }

  String? get refreshToken {
    return _storage.getString(StorageKeys.authBox, StorageKeys.refreshToken);
  }

  Future<void> saveSession(AuthSession session) async {
    if (session.accessToken != null) {
      await _storage.setString(
        StorageKeys.authBox,
        StorageKeys.accessToken,
        session.accessToken!,
      );
      await _writeSecure(StorageKeys.accessToken, session.accessToken);
    } else {
      await _storage.remove(StorageKeys.authBox, StorageKeys.accessToken);
      await _writeSecure(StorageKeys.accessToken, null);
    }
    if (session.refreshToken != null) {
      await _storage.setString(
        StorageKeys.authBox,
        StorageKeys.refreshToken,
        session.refreshToken!,
      );
      await _writeSecure(StorageKeys.refreshToken, session.refreshToken);
    } else {
      await _storage.remove(StorageKeys.authBox, StorageKeys.refreshToken);
      await _writeSecure(StorageKeys.refreshToken, null);
    }
    if (session.accessTokenExpiresAt != null) {
      await _storage.setString(
        StorageKeys.authBox,
        StorageKeys.accessTokenExpiresAt,
        session.accessTokenExpiresAt!.toIso8601String(),
      );
      await _writeSecure(
        StorageKeys.accessTokenExpiresAt,
        session.accessTokenExpiresAt!.toIso8601String(),
      );
    } else {
      await _storage.remove(
        StorageKeys.authBox,
        StorageKeys.accessTokenExpiresAt,
      );
      await _writeSecure(StorageKeys.accessTokenExpiresAt, null);
    }
    notifyListeners();
  }

  Future<void> saveSessionJson(Map<String, dynamic> json) async {
    await saveSession(AuthSession.fromJson(json));
  }

  Future<AuthSession?> loadSession() async {
    final access = _storage.getString(
      StorageKeys.authBox,
      StorageKeys.accessToken,
    );
    final refresh = _storage.getString(
      StorageKeys.authBox,
      StorageKeys.refreshToken,
    );
    final expRaw = _storage.getString(
      StorageKeys.authBox,
      StorageKeys.accessTokenExpiresAt,
    );
    if (access == null && refresh == null) return null;
    return AuthSession(
      accessToken: access,
      refreshToken: refresh,
      accessTokenExpiresAt:
          expRaw != null ? DateTime.tryParse(expRaw) : null,
    );
  }

  Future<void> clearAuth() async {
    await _storage.clearBox(StorageKeys.authBox);
    await _writeSecure(StorageKeys.accessToken, null);
    await _writeSecure(StorageKeys.refreshToken, null);
    await _writeSecure(StorageKeys.accessTokenExpiresAt, null);
    notifyListeners();
  }

  /// Stores ad-hoc device metadata (legacy helper).
  Future<void> saveDeviceMetaJson(Map<String, dynamic> meta) async {
    await _storage.setString(
      StorageKeys.deviceBox,
      '_meta_json',
      jsonEncode(meta),
    );
  }

  Future<void> savePairedDevice(DeviceIdentity identity) async {
    await _storage.setString(
      StorageKeys.deviceBox,
      StorageKeys.pairedDeviceJson,
      jsonEncode(identity.toJson()),
    );
    await _writeSecure(StorageKeys.pairedDeviceJson, jsonEncode(identity.toJson()));
    notifyListeners();
  }

  Future<void> saveLicenseContext({
    required String licenseId,
    required String deviceName,
    String? orgEnrollmentCode,
  }) async {
    await _storage.setString(
      StorageKeys.deviceBox,
      StorageKeys.licenseId,
      licenseId.trim().toUpperCase(),
    );
    await _writeSecure(StorageKeys.licenseId, licenseId.trim().toUpperCase());
    await _storage.setString(
      StorageKeys.deviceBox,
      StorageKeys.deviceName,
      deviceName.trim(),
    );
    await _writeSecure(StorageKeys.deviceName, deviceName.trim());
    if (orgEnrollmentCode != null && orgEnrollmentCode.trim().isNotEmpty) {
      final code = orgEnrollmentCode.trim().toUpperCase();
      await _storage.setString(
        StorageKeys.deviceBox,
        StorageKeys.orgEnrollmentCode,
        code,
      );
      await _writeSecure(StorageKeys.orgEnrollmentCode, code);
    } else {
      await _storage.remove(StorageKeys.deviceBox, StorageKeys.orgEnrollmentCode);
      await _writeSecure(StorageKeys.orgEnrollmentCode, null);
    }
  }

  String? get savedOrgEnrollmentCode {
    final raw = _storage.getString(
      StorageKeys.deviceBox,
      StorageKeys.orgEnrollmentCode,
    );
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim().toUpperCase();
  }

  String? get savedLicenseId {
    final raw = _storage.getString(StorageKeys.deviceBox, StorageKeys.licenseId);
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim().toUpperCase();
  }

  String? get savedDeviceName {
    final raw = _storage.getString(StorageKeys.deviceBox, StorageKeys.deviceName);
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim();
  }

  /// Sync read for startup gating and [hasPairedDevice].
  DeviceIdentity? loadPairedDevice() {
    final raw = _storage.getString(
      StorageKeys.deviceBox,
      StorageKeys.pairedDeviceJson,
    );
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return DeviceIdentity.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  bool get hasPairedDevice {
    final id = loadPairedDevice();
    return id != null && id.paired;
  }

  /// Clears device JWT, paired identity, and cached playlist after auth failure.
  Future<void> invalidateDeviceSession() async {
    await _storage.clearBox(StorageKeys.authBox);
    await _storage.remove(StorageKeys.deviceBox, StorageKeys.pairedDeviceJson);
    await _storage.remove(StorageKeys.deviceBox, StorageKeys.playlistBundleJson);
    await _writeSecure(StorageKeys.accessToken, null);
    await _writeSecure(StorageKeys.refreshToken, null);
    await _writeSecure(StorageKeys.accessTokenExpiresAt, null);
    await _writeSecure(StorageKeys.pairedDeviceJson, null);
    notifyListeners();
  }
}
