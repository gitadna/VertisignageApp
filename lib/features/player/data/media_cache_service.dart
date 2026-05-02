import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../models/playlist_item.dart';

/// Downloads remote images/videos into app support storage; memoizes URL → path.
/// URL-type playlist rows skip downloads (handled only in [prefetchAndFilter]).
class MediaCacheService {
  MediaCacheService({
    Dio? downloadClient,
    this.maxCacheMb = 2048,
  }) : _dio = downloadClient ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 45),
                receiveTimeout: const Duration(minutes: 15),
                responseType: ResponseType.bytes,
              ),
            );

  final Dio _dio;
  final int maxCacheMb;

  final Map<String, String> _pathByUrl = {};
  Directory? _cacheDir;

  Future<Directory> _directory() async {
    if (_cacheDir != null) return _cacheDir!;
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'media_cache'));
    await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  /// Returns a local file path for [url], or `null` after one retry if download fails.
  Future<String?> resolveLocalPath(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final cached = _pathByUrl[trimmed];
    if (cached != null && await File(cached).exists()) {
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

      final dir = await _directory();
      final name = _fileNameForUrl(url);
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(bytes, flush: true);
      if (!await file.exists()) return null;
      await _enforceBudgetIfNeeded();
      return file.path;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('MediaCacheService: failed for $url — $e\n$st');
      }
      return null;
    }
  }

  Future<void> _enforceBudgetIfNeeded() async {
    final budgetBytes = maxCacheMb * 1024 * 1024;
    try {
      final dir = await _directory();
      if (!await dir.exists()) return;

      final files = <File>[];
      await for (final e in dir.list()) {
        if (e is File) files.add(e);
      }
      var total = 0;
      for (final f in files) {
        total += await f.length();
      }
      if (total <= budgetBytes) return;

      files.sort((a, b) {
        final ta = a.statSync().modified;
        final tb = b.statSync().modified;
        return ta.compareTo(tb);
      });

      for (final f in files) {
        if (total <= budgetBytes) break;
        try {
          final len = await f.length();
          await f.delete();
          total -= len;
          _pathByUrl.removeWhere((_, path) => path == f.path);
        } catch (_) {}
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('MediaCacheService._enforceBudgetIfNeeded: $e\n$st');
      }
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
    try {
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

  /// Approximate cache usage in megabytes (best-effort).
  Future<int?> approximateCacheSizeMb() async {
    try {
      final dir = await _directory();
      var total = 0;
      if (!await dir.exists()) return 0;
      await for (final e in dir.list(recursive: true)) {
        if (e is File) total += await e.length();
      }
      return (total / (1024 * 1024)).round();
    } catch (_) {
      return null;
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
