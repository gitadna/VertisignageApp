import 'dart:convert';

import '../core/constants/storage_keys.dart';
import '../core/storage/local_storage.dart';
import '../models/auth_session.dart';
import '../models/device_identity.dart';
import 'token_reader.dart';

/// Hive-backed token persistence implementing [TokenReader].
class TokenStore implements TokenReader {
  TokenStore(this._storage);

  final LocalStorage _storage;

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
    } else {
      await _storage.remove(StorageKeys.authBox, StorageKeys.accessToken);
    }
    if (session.refreshToken != null) {
      await _storage.setString(
        StorageKeys.authBox,
        StorageKeys.refreshToken,
        session.refreshToken!,
      );
    } else {
      await _storage.remove(StorageKeys.authBox, StorageKeys.refreshToken);
    }
    if (session.accessTokenExpiresAt != null) {
      await _storage.setString(
        StorageKeys.authBox,
        StorageKeys.accessTokenExpiresAt,
        session.accessTokenExpiresAt!.toIso8601String(),
      );
    } else {
      await _storage.remove(
        StorageKeys.authBox,
        StorageKeys.accessTokenExpiresAt,
      );
    }
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
}
