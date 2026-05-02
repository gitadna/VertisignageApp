import 'package:hive_flutter/hive_flutter.dart';

import '../constants/storage_keys.dart';
import 'local_storage.dart';

/// [LocalStorage] using two Hive boxes: auth and device metadata.
class HiveLocalStorage implements LocalStorage {
  Box<String>? _auth;
  Box<String>? _device;

  @override
  Future<void> init() async {
    _auth = await Hive.openBox<String>(StorageKeys.authBox);
    _device = await Hive.openBox<String>(StorageKeys.deviceBox);
  }

  Box<String> _boxFor(String boxName) {
    switch (boxName) {
      case StorageKeys.authBox:
        final b = _auth;
        if (b == null) {
          throw StateError('HiveLocalStorage.init() was not called');
        }
        return b;
      case StorageKeys.deviceBox:
        final b = _device;
        if (b == null) {
          throw StateError('HiveLocalStorage.init() was not called');
        }
        return b;
      default:
        throw ArgumentError('Unknown box: $boxName');
    }
  }

  @override
  String? getString(String boxName, String key) {
    return _boxFor(boxName).get(key);
  }

  @override
  Future<void> setString(String boxName, String key, String value) async {
    await _boxFor(boxName).put(key, value);
  }

  @override
  Future<void> remove(String boxName, String key) async {
    await _boxFor(boxName).delete(key);
  }

  @override
  Future<void> clearBox(String boxName) async {
    await _boxFor(boxName).clear();
  }
}
