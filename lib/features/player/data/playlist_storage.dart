import 'dart:convert';

import '../../../core/constants/storage_keys.dart';
import '../../../core/storage/local_storage.dart';
import '../../../models/playlist_bundle.dart';

/// Hive-backed playlist snapshot for offline playback.
class PlaylistStorage {
  PlaylistStorage(this._storage);

  final LocalStorage _storage;

  Future<void> save(PlaylistBundle bundle) async {
    await _storage.setString(
      StorageKeys.deviceBox,
      StorageKeys.playlistBundleJson,
      jsonEncode(bundle.toJson()),
    );
  }

  PlaylistBundle? load() {
    final raw = _storage.getString(
      StorageKeys.deviceBox,
      StorageKeys.playlistBundleJson,
    );
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return PlaylistBundle.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    await _storage.remove(
      StorageKeys.deviceBox,
      StorageKeys.playlistBundleJson,
    );
  }
}
