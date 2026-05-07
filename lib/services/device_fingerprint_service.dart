import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/constants/storage_keys.dart';
import '../core/storage/local_storage.dart';

/// Produces a stable, unique-per-install fingerprint used by backend
/// identity matching and recovery. Combines:
///
/// - a per-install UUID that is generated on first launch and persisted in
///   secure storage (also mirrored to Hive for visibility), guaranteeing a
///   different fingerprint for every fresh APK install (incl. reinstalls);
/// - Android `Settings.Secure.ANDROID_ID` plus serial / model / brand / device
///   / build fingerprint via `device_info_plus`, so the value is also tied to
///   the underlying hardware.
///
/// This eliminates the previous collision risk where multiple Android devices
/// shared a fingerprint built only from `Platform.localHostname`.
class DeviceFingerprintService {
  DeviceFingerprintService(this._storage)
    : _secure = const FlutterSecureStorage(aOptions: AndroidOptions()),
      _deviceInfo = DeviceInfoPlugin();

  /// Test-friendly constructor that allows injecting collaborators.
  DeviceFingerprintService.withDeps({
    required LocalStorage storage,
    required FlutterSecureStorage secure,
    required DeviceInfoPlugin deviceInfo,
  }) : _storage = storage,
       _secure = secure,
       _deviceInfo = deviceInfo;

  final LocalStorage _storage;
  final FlutterSecureStorage _secure;
  final DeviceInfoPlugin _deviceInfo;

  String? _cached;

  Future<String> getFingerprint() async {
    final cached = _cached;
    if (cached != null && cached.isNotEmpty) return cached;

    final stored = _storage.getString(
      StorageKeys.deviceBox,
      StorageKeys.deviceFingerprint,
    );
    if (stored != null && stored.isNotEmpty) {
      _cached = stored;
      return stored;
    }

    final installId = await _resolveInstallId();
    final hardware = await _readHardwareSignals();
    final raw = <String>[
      'v2',
      installId,
      ...hardware,
    ].join('|');
    final fingerprint = sha256.convert(utf8.encode(raw)).toString();

    await _storage.setString(
      StorageKeys.deviceBox,
      StorageKeys.deviceFingerprint,
      fingerprint,
    );
    await _writeSecure(StorageKeys.deviceFingerprint, fingerprint);

    _cached = fingerprint;
    return fingerprint;
  }

  Future<String> _resolveInstallId() async {
    String? installId;
    try {
      installId = await _secure.read(key: StorageKeys.installUuid);
    } catch (_) {}
    if (installId == null || installId.isEmpty) {
      installId = _storage.getString(
        StorageKeys.deviceBox,
        StorageKeys.installUuid,
      );
    }
    if (installId != null && installId.isNotEmpty) return installId;

    final fresh = _generateUuidV4();
    await _writeSecure(StorageKeys.installUuid, fresh);
    await _storage.setString(
      StorageKeys.deviceBox,
      StorageKeys.installUuid,
      fresh,
    );
    return fresh;
  }

  Future<List<String>> _readHardwareSignals() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return <String>[
          'android',
          info.id,
          info.serialNumber,
          info.model,
          info.brand,
          info.device,
          info.fingerprint,
          info.hardware,
          info.product,
        ].map(_safe).toList();
      }
      if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return <String>[
          'ios',
          info.identifierForVendor ?? '',
          info.model,
          info.name,
          info.systemVersion,
        ].map(_safe).toList();
      }
    } catch (_) {}
    return <String>[
      Platform.operatingSystem,
      Platform.operatingSystemVersion,
      _safeHostname(),
    ];
  }

  Future<void> _writeSecure(String key, String? value) async {
    try {
      if (value == null) {
        await _secure.delete(key: key);
      } else {
        await _secure.write(key: key, value: value);
      }
    } catch (_) {}
  }

  static String _safe(String value) => value.replaceAll('|', '_').trim();

  static String _safeHostname() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'unknown-host';
    }
  }

  /// RFC4122 v4 UUID using a cryptographically-strong source.
  static String _generateUuidV4() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
