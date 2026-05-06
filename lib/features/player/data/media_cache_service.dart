import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/storage_keys.dart';
import '../../../core/storage/local_storage.dart';
import '../../../models/playlist_item.dart';

/// Downloads remote images/videos into app support storage; memoizes URL → path.
/// URL-type playlist rows skip downloads (handled only in [prefetchAndFilter]).
class MediaCacheService {
  MediaCacheService({
    Dio? downloadClient,
    LocalStorage? persistentStorage,
    this.maxCacheMb = 400,
  }) : _dio = downloadClient ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 45),
                receiveTimeout: const Duration(minutes: 15),
                responseType: ResponseType.bytes,
              ),
            ),
        _persistentStorage = persistentStorage;

  final Dio _dio;
  final LocalStorage? _persistentStorage;

  /// Upper bound from fleet config (typically 300–512 MB).
  final int maxCacheMb;

  final Map<String, String> _pathByUrl = {};
  final Map<String, int> _lastAccessEpochMs = {};

  Directory? _cacheDir;
  bool _lruHydrated = false;
  int? _trackedTotalBytes;

  int get budgetBytes => maxCacheMb * 1024 * 1024;

  Future<Directory> _directory() async {
    await _hydrateLruFromDiskOnce();
    if (_cacheDir != null) return _cacheDir!;
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'media_cache'));
    await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  Future<void> _hydrateLruFromDiskOnce() async {
    if (_lruHydrated) return;
    _lruHydrated = true;
    final storage = _persistentStorage;
    if (storage == null) return;
    try {
      final raw = storage.getString(
        StorageKeys.deviceBox,
        StorageKeys.mediaCacheLruJson,
      );
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final e in decoded.entries) {
        final k = e.key;
        final v = e.value;
        if (k is String && v is num) {
          _lastAccessEpochMs[k] = v.toInt();
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('MediaCacheService LRU hydrate: $e\n$st');
      }
    }
  }

  Future<void> _persistLruToDisk() async {
    final storage = _persistentStorage;
    if (storage == null) return;
    try {
      await storage.setString(
        StorageKeys.deviceBox,
        StorageKeys.mediaCacheLruJson,
        jsonEncode(_lastAccessEpochMs),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('MediaCacheService LRU persist: $e\n$st');
      }
    }
  }

  void _touchPath(String path) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastAccessEpochMs[path] = now;
    unawaited(_persistLruToDisk());
  }

  Future<int> _directoryTotalBytes(Directory dir) async {
    var total = 0;
    if (!await dir.exists()) return 0;
    await for (final e in dir.list(recursive: true)) {
      if (e is File) {
        total += await e.length();
      }
    }
    return total;
  }

  Future<void> _refreshTrackedTotal() async {
    final dir = await _directory();
    _trackedTotalBytes = await _directoryTotalBytes(dir);
  }

  /// Approximate cache usage in megabytes (best-effort).
  Future<int?> approximateCacheSizeMb() async {
    try {
      await _refreshTrackedTotal();
      final t = _trackedTotalBytes ?? 0;
      return (t / (1024 * 1024)).round();
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureSpaceForIncomingBytes(int incomingLen) async {
    await _directory();
    if (_trackedTotalBytes == null) {
      await _refreshTrackedTotal();
    }
    final budget = budgetBytes;
    while ((_trackedTotalBytes ?? 0) + incomingLen > budget) {
      final freed = await _evictLeastRecentlyUsedOne();
      if (!freed) break;
    }
  }

  Future<bool> _evictLeastRecentlyUsedOne() async {
    try {
      final dir = await _directory();
      if (!await dir.exists()) return false;

      final files = <File>[];
      await for (final e in dir.list()) {
        if (e is File) files.add(e);
      }
      if (files.isEmpty) return false;

      File? victim;
      var bestScore = 1 << 62;

      for (final f in files) {
        final path = f.path;
        final stored = _lastAccessEpochMs[path];
        final score = stored ??
            (await f.stat()).modified.millisecondsSinceEpoch;
        if (score < bestScore) {
          bestScore = score;
          victim = f;
        }
      }
      if (victim == null) return false;

      final path = victim.path;
      final len = await victim.length();
      try {
        await victim.delete();
      } catch (_) {
        return false;
      }
      _pathByUrl.removeWhere((_, p) => p == path);
      _lastAccessEpochMs.remove(path);
      unawaited(_persistLruToDisk());
      _trackedTotalBytes = (_trackedTotalBytes ?? 0) - len;
      if (_trackedTotalBytes! < 0) {
        _trackedTotalBytes = 0;
      }
      return true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('MediaCacheService._evictLeastRecentlyUsedOne: $e\n$st');
      }
      return false;
    }
  }

  Future<void> _enforceBudgetIfNeeded() async {
    final budget = budgetBytes;
    if (_trackedTotalBytes == null) {
      await _refreshTrackedTotal();
    }
    while ((_trackedTotalBytes ?? 0) > budget) {
      final ok = await _evictLeastRecentlyUsedOne();
      if (!ok) break;
    }
  }

  /// Returns a local file path for [url], or `null` after one retry if download fails.
  Future<String?> resolveLocalPath(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final cached = _pathByUrl[trimmed];
    if (cached != null && await File(cached).exists()) {
      _touchPath(cached);
      return cached;
    }
    _pathByUrl.remove(trimmed);

    Future<String?> attempt() => _downloadToFile(trimmed);

    var path = await attempt();
    path ??= await attempt();
    if (path != null) {
      _pathByUrl[trimmed] = path;
    }
    return path;
  }

  Future<String?> _downloadToFile(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) return null;

      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );

      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;

      final len = bytes.length;
      await _ensureSpaceForIncomingBytes(len);

      final dir = await _directory();
      final name = _fileNameForUrl(url);
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(bytes, flush: true);
      if (!await file.exists()) return null;

      _trackedTotalBytes = (_trackedTotalBytes ?? 0) + len;
      _touchPath(file.path);
      await _enforceBudgetIfNeeded();
      return file.path;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('MediaCacheService: failed for $url — $e\n$st');
      }
      return null;
    }
  }

  String _fileNameForUrl(String url) {
    final digest = md5.convert(utf8.encode(url));
    return '${digest.toString()}${_extensionGuess(url)}';
  }

  String _extensionGuess(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.mp4')) return '.mp4';
    if (lower.contains('.webm')) return '.webm';
    if (lower.contains('.mov')) return '.mov';
    if (lower.contains('.png')) return '.png';
    if (lower.contains('.webp')) return '.webp';
    if (lower.contains('.gif')) return '.gif';
    return '.jpg';
  }

  /// Clears in-memory map only (files remain on disk for reuse).
  void forgetUrl(String url) {
    _pathByUrl.remove(url.trim());
  }

  /// Deletes cached media files and clears the memo map (WebSocket CLEAR_CACHE).
  Future<void> clearDiskCache() async {
    _pathByUrl.clear();
    _lastAccessEpochMs.clear();
    _trackedTotalBytes = 0;
    _lruHydrated = false;
    try {
      final storage = _persistentStorage;
      if (storage != null) {
        await storage.remove(
          StorageKeys.deviceBox,
          StorageKeys.mediaCacheLruJson,
        );
      }
      final dir = await _directory();
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        try {
          if (entity is File) await entity.delete();
        } catch (_) {}
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('MediaCacheService.clearDiskCache: $e\n$st');
      }
    }
  }

  /// Removes cached media not referenced by [keepUrls].
  ///
  /// URL slides are ignored by callers; this only applies to downloaded files.
  Future<void> pruneToUrls(Iterable<String> keepUrls) async {
    try {
      final dir = await _directory();
      if (!await dir.exists()) return;

      final keepTrimmed = <String>{
        for (final u in keepUrls)
          if (u.trim().isNotEmpty) u.trim(),
      };
      final keepNames = <String>{
        for (final u in keepTrimmed) _fileNameForUrl(u),
      };
      final keepPaths = <String>{};
      for (final url in keepTrimmed) {
        final path = _pathByUrl[url];
        if (path != null) keepPaths.add(path);
      }

      final removedPaths = <String>{};
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final path = entity.path;
        final name = p.basename(path);
        final shouldKeep = keepPaths.contains(path) || keepNames.contains(name);
        if (shouldKeep) continue;
        try {
          final len = await entity.length();
          await entity.delete();
          removedPaths.add(path);
          _lastAccessEpochMs.remove(path);
          if (_trackedTotalBytes != null) {
            _trackedTotalBytes = (_trackedTotalBytes! - len).clamp(0, 1 << 62);
          }
        } catch (_) {}
      }

      if (removedPaths.isNotEmpty) {
        _pathByUrl.removeWhere((_, path) => removedPaths.contains(path));
        await _persistLruToDisk();
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('MediaCacheService.pruneToUrls: $e\n$st');
      }
    }
  }

  /// Ensures each asset is cached where needed. URL slides pass http(s) validation only.
  Future<List<PlaylistItem>> prefetchAndFilter(List<PlaylistItem> items) async {
    final ready = <PlaylistItem>[];
    for (final item in items) {
      if (item.mediaKind == PlaylistMediaKind.url) {
        final uri = Uri.tryParse(item.url.trim());
        if (uri != null &&
            uri.hasAuthority &&
            (uri.isScheme('https') || uri.isScheme('http'))) {
          ready.add(item);
        }
      } else {
        final path = await resolveLocalPath(item.url);
        if (path != null) {
          ready.add(item);
        }
      }
    }
    return ready;
  }
}
