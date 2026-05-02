/// Key-value persistence for device and auth data (Hive-backed in production).
abstract class LocalStorage {
  Future<void> init();

  String? getString(String boxName, String key);

  Future<void> setString(String boxName, String key, String value);

  Future<void> remove(String boxName, String key);

  /// Clears all keys in a logical box.
  Future<void> clearBox(String boxName);
}
