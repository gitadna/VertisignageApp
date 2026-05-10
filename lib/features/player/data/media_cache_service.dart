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
import 'playback_perf_telemetry.dart';

/// Downloads remote images/videos into app support storage; memoizes URL → path.
/// URL-type playlist rows skip downloads (handled only in [prefetchAndFilter]).
class MediaCacheService {
  MediaCacheService({
    Dio? downloadClient,
    LocalStorage? persistentStorage,
    String? apiBaseUrl,
    this.maxCacheMb = 400,
  }) :         _dio = downloadClient ??
            Dio(
              BaseOptions(
                baseUrl: (apiBaseUrl ?? '').trim(),
                connectTimeout: const Duration(seconds: 45),
                receiveTimeout: const Duration(minutes: 15),
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
  int? _trackedTotalBytes;
  bool _ledgerHydrated = false;

  int get budgetBytes => maxCacheMb * 1024 * 1024;

  Future<Directory> _directory() async {
    await _hydrateFromDiskOnce();
    if (_cacheDir != null) return _cacheDir!;
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'media_cache'));
    await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  Future<void> _hydrateFromDiskOnce() async {
    if (_ledgerHydrated) return;
    _ledgerHydrated = true;
    final storage = _persistentStorage;
    if (storage == null) {
      return;
    }
    try {
      final raw = storage.getString(
        StorageKeys.deviceBox,
        StorageKeys.mediaCacheLruJson,
      );
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            final k = e.key;
            final v = e.value;
            if (k is String && v is num) {
              _lastAccessEpochMs[k] = v.toInt();
            }
          }
        }
      }

      final tracked = storage.getString(
        StorageKeys.deviceBox,
        StorageKeys.mediaCacheTrackedTotalBytes,
      );
      _trackedTotalBytes = int.tryParse((tracked ?? '').trim());
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('MediaCacheService hydrate: $e\n$st');
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

  Future<void> _persistTrackedTotalBytes() async {
    final storage = _persistentStorage;
    if (storage == null) return;
    try {
      final t = (_trackedTotalBytes ?? 0).clamp(0, 1 << 62);
      _trackedTotalBytes = t;
      await storage.setString(
        StorageKeys.deviceBox,
        StorageKeys.mediaCacheTrackedTotalBytes,
        t.toString(),
      );
    } catch (_) {
      // best-effort only
    }
  }

  void _touchPath(String path) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastAccessEpochMs[path] = now;
    unawaited(_persistLruToDisk());
  }

  /// Approximate cache usage in megabytes (best-effort).
  Future<int?> approximateCacheSizeMb() async {
    try {
      await _directory(); // ensure disk hydration ran
      final t = (_trackedTotalBytes ?? 0).clamp(0, 1 << 62);
      return (t / (1024 * 1024)).round();
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureSpaceForIncomingBytes(int incomingLen) async {
    await _directory();
    if (_trackedTotalBytes == null) {
      _trackedTotalBytes = 0;
      unawaited(_persistTrackedTotalBytes());
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
      unawaited(_persistTrackedTotalBytes());
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
      _trackedTotalBytes = 0;
      unawaited(_persistTrackedTotalBytes());
    }
    while ((_trackedTotalBytes ?? 0) > budget) {
      final ok = await _evictLeastRecentlyUsedOne();
      if (!ok) break;
    }
  }

  String _mediaKindBucketForUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.mp4') ||
        lower.contains('.webm') ||
        lower.contains('.mov')) {
      return 'video';
    }
    if (lower.contains('.png') ||
        lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.webp') ||
        lower.contains('.gif')) {
      return 'image';
    }
    return 'file';
  }

  /// Returns a local file path for [url], or `null` after one retry if download fails.
  Future<String?> resolveLocalPath(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final sw = Stopwatch()..start();
    final bucket = _mediaKindBucketForUrl(trimmed);

    final cached = _pathByUrl[trimmed];
    if (cached != null && await File(cached).exists()) {
      _touchPath(cached);
      sw.stop();
      PlaybackPerfTelemetry.mediaResolve(
        cacheHit: true,
        elapsedMs: sw.elapsedMilliseconds,
        mediaKindBucket: bucket,
      );
      return cached;
    }
    _pathByUrl.remove(trimmed);

    Future<String?> attempt() => _downloadToFile(trimmed);

    var path = await attempt();
    path ??= await attempt();
    sw.stop();
    if (path != null) {
      _pathByUrl[trimmed] = path;
      PlaybackPerfTelemetry.mediaResolve(
        cacheHit: false,
        elapsedMs: sw.elapsedMilliseconds,
        mediaKindBucket: bucket,
      );
    } else {
      PlaybackPerfTelemetry.mediaResolveFailed(mediaKindBucket: bucket);
    }
    return path;
  }

  Future<String?> _downloadToFile(String url) async {
    File? tempFile;
    try {
      final resolvedUrl = _resolveReachableUrl(url);
      final uri = Uri.tryParse(resolvedUrl);
      if (uri == null) return null;

      // Accept both absolute URLs and server-returned relative paths like `/uploads/x.mp4`.
      // Relative URLs are resolved by Dio using [BaseOptions.baseUrl].
      final base = _dio.options.baseUrl.trim();
      final isAbsolute = uri.hasScheme;
      final canResolveRelative = !isAbsolute && base.isNotEmpty;
      if (!isAbsolute && !canResolveRelative) return null;

      var reservedLen = 32 * 1024 * 1024;
      try {
        final head = await _dio.head(
          resolvedUrl,
          options: Options(
            followRedirects: true,
            validateStatus: (s) => s != null && s < 500,
          ),
        );
        final cl = head.headers.value('content-length');
        final parsed = cl != null ? int.tryParse(cl) : null;
        if (parsed != null && parsed > 0) {
          reservedLen = parsed;
        }
      } catch (_) {
        // Optional HEAD; fall back to conservative reservation.
      }

      await _ensureSpaceForIncomingBytes(reservedLen);

      final dir = await _directory();
      final name = _fileNameForUrl(url);
      final finalPath = p.join(dir.path, name);
      final tempPath = '$finalPath.part';
      tempFile = File(tempPath);
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }

      await _dio.download(
        resolvedUrl,
        tempPath,
        deleteOnError: true,
        options: Options(followRedirects: true),
      );

      if (!await tempFile.exists()) return null;
      var len = await tempFile.length();
      if (len <= 0) {
        try {
          await tempFile.delete();
        } catch (_) {}
        return null;
      }

      await _ensureSpaceForIncomingBytes(len);

      final dest = File(finalPath);
      if (await dest.exists()) {
        try {
          final oldLen = await dest.length();
          await dest.delete();
          if (_trackedTotalBytes != null) {
            _trackedTotalBytes = (_trackedTotalBytes! - oldLen).clamp(0, 1 << 62);
            unawaited(_persistTrackedTotalBytes());
          }
        } catch (_) {}
      }

      await tempFile.rename(finalPath);
      tempFile = null;

      if (!await dest.exists()) return null;
      len = await dest.length();
      if (len <= 0) {
        try {
          await dest.delete();
        } catch (_) {}
        return null;
      }

      _trackedTotalBytes = (_trackedTotalBytes ?? 0) + len;
      unawaited(_persistTrackedTotalBytes());
      _touchPath(dest.path);
      await _enforceBudgetIfNeeded();
      return dest.path;
    } catch (e, st) {
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      if (kDebugMode) {
        debugPrint('MediaCacheService: failed for $url — $e\n$st');
      }
      return null;
    }
  }

  String _resolveReachableUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return trimmed;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;

    final baseRaw = _dio.options.baseUrl.trim();
    if (baseRaw.isEmpty) return trimmed;
    final base = Uri.tryParse(baseRaw);
    if (base == null || !base.hasAuthority) return trimmed;

    if (!uri.hasScheme) {
      return trimmed;
    }

    final host = uri.host.toLowerCase();
    final isLoopbackHost =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    if (!isLoopbackHost) return trimmed;

    final rewritten = uri.replace(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
    );
    return rewritten.toString();
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
    try {
      final storage = _persistentStorage;
      if (storage != null) {
        await storage.remove(
          StorageKeys.deviceBox,
          StorageKeys.mediaCacheLruJson,
        );
        await storage.remove(
          StorageKeys.deviceBox,
          StorageKeys.mediaCacheTrackedTotalBytes,
        );
      }
      final dir = await _directory();
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        try {
          if (entity is File) await entity.delete();
        } catch (_) {}
      }
      unawaited(_persistTrackedTotalBytes());
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
        unawaited(_persistTrackedTotalBytes());
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('MediaCacheService.pruneToUrls: $e\n$st');
      }
    }
  }

  Future<PlaylistItem?> _prefetchOne(PlaylistItem item) async {
    if (item.mediaKind == PlaylistMediaKind.url) {
      final uri = Uri.tryParse(item.url.trim());
      if (uri != null &&
          uri.hasAuthority &&
          (uri.isScheme('https') || uri.isScheme('http'))) {
        return item;
      }
      return null;
    }
    final path = await resolveLocalPath(item.url);
    return path != null ? item : null;
  }

  /// Ensures each asset is cached where needed. URL slides pass http(s) validation only.
  /// File assets prefetch with bounded parallelism (batch size 3) while preserving order.
  Future<List<PlaylistItem>> prefetchAndFilter(List<PlaylistItem> items) async {
    final sw = Stopwatch()..start();
    const batchSize = 3;
    final ready = <PlaylistItem>[];
    var i = 0;
    while (i < items.length) {
      final end = i + batchSize > items.length ? items.length : i + batchSize;
      final batch = items.sublist(i, end);
      final results = await Future.wait(batch.map(_prefetchOne));
      for (final r in results) {
        if (r != null) {
          ready.add(r);
        }
      }
      i = end;
    }
    sw.stop();
    PlaybackPerfTelemetry.prefetchRound(
      itemCount: items.length,
      elapsedMs: sw.elapsedMilliseconds,
      readyCount: ready.length,
    );
    return ready;
  }
}
