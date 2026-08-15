import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:asmr_hub/services/preferences_service.dart';

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  Future<String> getCacheDirectory(String sourceTypeId) async {
    final basePath = await PreferencesService().getCachePath();
    final cacheDir = Directory(path.join(basePath, sourceTypeId));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir.path;
  }

  Future<String> getCacheFilePath(String sourceTypeId, String trackId) async {
    final cacheDir = await getCacheDirectory(sourceTypeId);
    // Sanitize trackId to be a valid filename
    final safeFilename = trackId.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return path.join(cacheDir, safeFilename);
  }

  Future<bool> isCached(String sourceTypeId, String trackId) async {
    final filePath = await getCacheFilePath(sourceTypeId, trackId);
    return File(filePath).exists();
  }

  /// Deletes the cached file of a single track (if any).
  Future<void> clearCacheForTrack(String sourceTypeId, String trackId) async {
    try {
      final filePath = await getCacheFilePath(sourceTypeId, trackId);
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error clearing track cache: $e');
    }
  }

  Future<int> getCacheSize(String sourceTypeId) async {
    try {
      final cacheDir = await getCacheDirectory(sourceTypeId);
      final directory = Directory(cacheDir);
      int totalSize = 0;
      if (await directory.exists()) {
        await for (final file in directory.list(recursive: true)) {
          if (file is File) {
            totalSize += await file.length();
          }
        }
      }
      return totalSize;
    } catch (e) {
      debugPrint('Error calculating cache size: $e');
      return 0;
    }
  }

  Future<void> clearCache(String sourceTypeId) async {
    try {
      final cacheDir = await getCacheDirectory(sourceTypeId);
      final directory = Directory(cacheDir);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }

  Future<void> clearAllCache() async {
    try {
      final basePath = await PreferencesService().getCachePath();
      final cacheDir = Directory(basePath);
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing all cache: $e');
    }
  }

  // ----------------------------------------------------------- metadata

  /// Downloads [url] into the metadata cache directory (covers etc.) and
  /// returns the local file path. Reuses the file when already cached.
  /// [headers] are passed to the HTTP request (needed for anti-hotlink CDNs
  /// like Bilibili). Returns null on failure.
  Future<String?> cacheRemoteFile(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final basePath = await PreferencesService().getCachePath();
      final metaDir = Directory(path.join(basePath, 'meta'));
      if (!await metaDir.exists()) {
        await metaDir.create(recursive: true);
      }
      final hash = base64Url
          .encode(utf8.encode(url))
          .replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
      final ext = _guessExtension(url);
      final filePath = path.join(metaDir.path, '$hash$ext');
      final file = File(filePath);
      if (await file.exists()) return filePath;

      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      await file.writeAsBytes(response.bodyBytes);
      return filePath;
    } catch (e) {
      debugPrint('Error caching remote file: $e');
      return null;
    }
  }

  /// Headers required to fetch cover art for [url] (anti-hotlink CDNs).
  static Map<String, String>? coverHeadersFor(String url) {
    // Browser headers are needed by essentially every cover CDN; at minimum
    // a real User-Agent avoids plain 403s, and the referer satisfies
    // anti-hotlink checks.
    const ua =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    if (url.contains('hdslb.com') ||
        url.contains('bilivideo.com') ||
        url.contains('biliimg.com')) {
      return {'User-Agent': ua, 'Referer': 'https://www.bilibili.com/'};
    }
    if (url.contains('douyucdn.cn')) {
      return {'User-Agent': ua, 'Referer': 'https://www.douyu.com/'};
    }
    if (url.contains('asmr.one') || url.contains('asmr-200.com')) {
      return {'User-Agent': ua, 'Referer': 'https://asmr.one/'};
    }
    if (url.contains('dlsite.com')) {
      return {'User-Agent': ua, 'Referer': 'https://www.dlsite.com/'};
    }
    if (url.contains('ytimg.com') ||
        url.contains('youtube.com') ||
        url.contains('ggpht.com')) {
      return {'User-Agent': ua};
    }
    return {'User-Agent': ua};
  }

  String _guessExtension(String url) {
    // Match the extension at the end of the URL path (ignoring query/hash),
    // not anywhere in the string ("a.jpg.png" style false matches).
    try {
      final uri = Uri.parse(url);
      final lower = uri.path.toLowerCase();
      // Douyu live screenshots use an `.avif` path suffix but are actually
      // served as JPEG; cache them as .jpg so the image decoder picks the
      // right codec.
      if (url.contains('douyucdn.cn') && lower.contains('/asrpic/')) {
        return '.jpg';
      }
      if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return '.jpg';
      if (lower.endsWith('.png')) return '.png';
      if (lower.endsWith('.webp')) return '.webp';
      if (lower.endsWith('.gif')) return '.gif';
      if (lower.endsWith('.avif')) return '.avif';
      if (lower.endsWith('.heic')) return '.heic';
    } catch (_) {
      // fall through to default
    }
    return '.jpg';
  }
}
