import '../../../core/constants/storage_keys.dart';
import '../../../core/storage/local_storage.dart';

/// Device-wide preference toggles for playback backends.
class KioskVideoPreferences {
  KioskVideoPreferences(this._storage);

  final LocalStorage _storage;

  bool get preferVlcVideo =>
      _storage.getString(StorageKeys.deviceBox, StorageKeys.preferVlcVideo) ==
      'true';

  Future<void> setPreferVlcVideo(bool v) async {
    await _storage.setString(
      StorageKeys.deviceBox,
      StorageKeys.preferVlcVideo,
      v ? 'true' : 'false',
    );
  }
}

