import 'dart:convert';

import '../constants/storage_keys.dart';
import '../storage/local_storage.dart';
import 'safe_mode_gate.dart';

/// Persists crash timeline and safe-mode flag (Hive-backed).
class KioskRecoveryStore {
  KioskRecoveryStore(this._storage, this._gate);

  final LocalStorage _storage;
  final SafeModeGate _gate;

  static const int _windowSec = 600;
  static const int _threshold = 3;

  bool get isSafeMode =>
      _storage.getString(StorageKeys.deviceBox, StorageKeys.safeMode) == 'true';

  Future<void> enterSafeMode() async {
    await _storage.setString(StorageKeys.deviceBox, StorageKeys.safeMode, 'true');
    _gate.value = true;
  }

  Future<void> clearSafeMode() async {
    await _storage.remove(StorageKeys.deviceBox, StorageKeys.safeMode);
    await _storage.remove(StorageKeys.deviceBox, StorageKeys.fatalCrashLogJson);
    _gate.value = false;
  }

  /// Record a crash marker; enters safe mode when too many occur within [_windowSec].
  Future<void> recordCrashMarker() async {
    final now = DateTime.now().toUtc();
    final raw = _storage.getString(
      StorageKeys.deviceBox,
      StorageKeys.fatalCrashLogJson,
    );
    List<DateTime> stamps = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        stamps = list
            .map((e) => DateTime.tryParse(e as String)?.toUtc())
            .whereType<DateTime>()
            .toList();
      } catch (_) {}
    }
    stamps.add(now);
    final cutoff = now.subtract(const Duration(seconds: _windowSec));
    stamps = stamps.where((t) => !t.isBefore(cutoff)).toList();

    await _storage.setString(
      StorageKeys.deviceBox,
      StorageKeys.fatalCrashLogJson,
      jsonEncode(stamps.map((e) => e.toIso8601String()).toList()),
    );

    if (stamps.length >= _threshold) {
      await enterSafeMode();
    }
  }

  /// Hydrate gate from disk after reboot (safe mode persisted).
  void restoreGateFromDisk() {
    _gate.value = isSafeMode;
  }
}
