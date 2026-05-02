import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../models/playlist_item.dart';

/// Downloads remote images into app support storage; memoizes URL → path in memory.
class ImageCacheService {
  ImageCacheService({Dio? downloadClient})
      : _dio = downloadClient ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 60),
                responseType: ResponseType.bytes,
              ),
            );

  final Dio _dio;
  final Map<String, String> _pathByUrl = {};
  Directory? _cacheDir;

  Future<Directory> _directory() async {
    if (_cacheDir != null) return _cacheDir!;
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'image_cache'));
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
      return file.path;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ImageCacheService: failed for $url — $e\n$st');
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
    if (lower.contains('.png')) return '.png';
    if (lower.contains('.webp')) return '.webp';
    if (lower.contains('.gif')) return '.gif';
    return '.jpg';
  }

  /// Clears in-memory map only (files remain on disk for reuse).
  void forgetUrl(String url) {
    _pathByUrl.remove(url.trim());
  }

  /// Downloads each asset once (with existing retry policy); keeps items whose file resolved.
  Future<List<PlaylistItem>> prefetchAndFilter(List<PlaylistItem> items) async {
    final ready = <PlaylistItem>[];
    for (final item in items) {
      final path = await resolveLocalPath(item.url);
      if (path != null) {
        ready.add(item);
      }
    }
    return ready;
  }
}
