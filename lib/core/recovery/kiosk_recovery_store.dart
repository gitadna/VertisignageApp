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
  static const Duration _dedupeWindow = Duration(seconds: 30);

  bool get isSafeMode =>
      _storage.getString(StorageKeys.deviceBox, StorageKeys.safeMode) == 'true';

  Future<void> enterSafeMode() async {
    await _storage.setString(StorageKeys.deviceBox, StorageKeys.safeMode, 'true');
    _gate.value = true;
  }

  Future<void> clearSafeMode() async {
    await _storage.remove(StorageKeys.deviceBox, StorageKeys.safeMode);
    await _storage.remove(StorageKeys.deviceBox, StorageKeys.fatalCrashLogJson);
    await _storage.remove(StorageKeys.deviceBox, StorageKeys.fatalCrashMarkersJson);
    await _storage.remove(StorageKeys.deviceBox, StorageKeys.safeModeReason);
    _gate.value = false;
  }

  /// Record a crash marker; enters safe mode when too many occur within [_windowSec].
  ///
  /// `sig` helps dedupe repeated non-fatal errors so they don't force recovery mode.
  Future<void> recordCrashMarker({
    String sig = 'unknown',
    String source = 'flutter',
  }) async {
    final now = DateTime.now().toUtc();

    // New structured markers.
    final markers = await _readMarkers();
    if (_shouldDedupe(markers, now, sig, source)) {
      return;
    }
    markers.add({
      'atUtc': now.toIso8601String(),
      'sig': sig,
      'source': source,
    });

    final cutoff = now.subtract(const Duration(seconds: _windowSec));
    final recent = _filterRecentMarkers(markers, cutoff);
    await _writeMarkers(recent);

    // Keep legacy key in sync for older builds / tools.
    await _storage.setString(
      StorageKeys.deviceBox,
      StorageKeys.fatalCrashLogJson,
      jsonEncode(
        recent
            .map((e) => DateTime.tryParse('${e['atUtc']}')?.toUtc())
            .whereType<DateTime>()
            .map((e) => e.toIso8601String())
            .toList(),
      ),
    );

    if (recent.length >= _threshold) {
      await _storage.setString(
        StorageKeys.deviceBox,
        StorageKeys.safeModeReason,
        'threshold=$_threshold windowSec=$_windowSec lastSource=$source lastSig=$sig',
      );
      await enterSafeMode();
    }
  }

  Future<List<Map<String, dynamic>>> _readMarkers() async {
    // Prefer new format.
    final raw = _storage.getString(
      StorageKeys.deviceBox,
      StorageKeys.fatalCrashMarkersJson,
    );
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {}
    }

    // Migrate from legacy timestamp-only list.
    final legacy = _storage.getString(
      StorageKeys.deviceBox,
      StorageKeys.fatalCrashLogJson,
    );
    if (legacy != null && legacy.isNotEmpty) {
      try {
        final list = jsonDecode(legacy) as List<dynamic>;
        return list
            .map((e) => DateTime.tryParse(e as String)?.toUtc())
            .whereType<DateTime>()
            .map(
              (t) => <String, dynamic>{
                'atUtc': t.toIso8601String(),
                'sig': 'legacy',
                'source': 'legacy',
              },
            )
            .toList();
      } catch (_) {}
    }
    return <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _filterRecentMarkers(
    List<Map<String, dynamic>> markers,
    DateTime cutoffUtc,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final m in markers) {
      final at = DateTime.tryParse('${m['atUtc']}')?.toUtc();
      if (at == null) continue;
      if (at.isBefore(cutoffUtc)) continue;
      out.add(m);
    }
    return out;
  }

  Future<void> _writeMarkers(List<Map<String, dynamic>> markers) async {
    await _storage.setString(
      StorageKeys.deviceBox,
      StorageKeys.fatalCrashMarkersJson,
      jsonEncode(markers),
    );
  }

  bool _shouldDedupe(
    List<Map<String, dynamic>> markers,
    DateTime nowUtc,
    String sig,
    String source,
  ) {
    if (markers.isEmpty) return false;
    final last = markers.last;
    final lastAt = DateTime.tryParse('${last['atUtc']}')?.toUtc();
    if (lastAt == null) return false;
    if (nowUtc.difference(lastAt) > _dedupeWindow) return false;
    final lastSig = '${last['sig'] ?? ''}';
    final lastSource = '${last['source'] ?? ''}';
    return lastSig == sig && lastSource == source;
  }

  /// Hydrate gate from disk after reboot (safe mode persisted).
  void restoreGateFromDisk() {
    _gate.value = isSafeMode;
  }
}
