import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';

import 'package:asmr_hub/models/account_info.dart';
import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/audio_duration_probe.dart';
import 'package:asmr_hub/sources/base/base_source.dart';
import 'package:asmr_hub/sources/base/source_auth.dart';
import 'package:asmr_hub/sources/base/source_scraper.dart';

class LocalAuth extends SourceAuth {
  LocalAuth() : super('');

  @override
  bool get requiresAuth => false;

  @override
  bool get supportsQrCodeLogin => false;

  @override
  bool get supportsWebLogin => false;

  @override
  bool get supportsCookieLogin => false;

  @override
  bool get isLoggedIn => true;

  @override
  AccountInfo? get currentUser => AccountInfo(name: 'Local User');

  @override
  String? get cookie => null;

  @override
  Future<void> loginWithCookie(String cookie) async {}

  @override
  Future<void> loginWithQrCode(BuildContext context) async {}

  @override
  Future<void> loginWithWeb(BuildContext context) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<void> checkLoginStatus() async {}

  @override
  bool get supportsCredentialsLogin => false;

  @override
  Future<void> loginWithCredentials(String username, String password) async {
    // Not applicable for local files
  }
}

class LocalScraper implements SourceScraper {
  static const List<String> _supportedExtensions = [
    '.mp3',
    '.wav',
    '.flac',
    '.aac',
    '.ogg',
    '.m4a',
    '.wma',
  ];

  String? rootDirectory;

  @override
  Future<List<AudioTrack>> scrapePlaylist(String url) async {
    try {
      final directory = Directory(url);
      if (!await directory.exists()) {
        final file = File(url);
        if (await file.exists()) {
          final track = await _createTrackFromFile(file);
          if (track != null) return [track];
        }
        return [];
      }

      final files = await _scanDirectory(directory);
      final tracks = <AudioTrack>[];

      for (final file in files) {
        final track = await _createTrackFromFile(file);
        if (track != null) tracks.add(track);
      }

      return tracks;
    } catch (e) {
      return [];
    }
  }

  @override
  Future<AudioTrack> scrapeVideo(String url) async {
    String filePath = url;
    if (url.startsWith('file://')) {
      filePath = url.substring(7);
    }

    final file = File(filePath);
    final track = await _createTrackFromFile(file);
    if (track == null) throw Exception('File not found');
    return track;
  }

  @override
  Future<String> scrapeStreamUrl(String trackId, {String? quality}) async {
    // Keep raw paths without a file:// prefix: callers treat non-http as
    // local file paths directly (a prefix would break File() lookups).
    return trackId;
  }

  Future<List<File>> _scanDirectory(Directory directory) async {
    final files = <File>[];
    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File && _isSupportedFile(entity.path)) {
          files.add(entity);
        }
      }
    } catch (e) {
      // Ignore errors
    }
    return files;
  }

  bool _isSupportedFile(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    return _supportedExtensions.contains(ext);
  }

  Future<AudioTrack?> _createTrackFromFile(File file) async {
    try {
      if (!await file.exists()) return null;

      final fileName = path.basenameWithoutExtension(file.path);
      final stat = await file.stat();

      final parts = fileName.split(' - ');
      final artist = parts.length > 1 ? parts[0] : 'Unknown Artist';
      final title = parts.length > 1 ? parts[1] : fileName;

      // Probe the real duration from the file header instead of using a
      // hard-coded placeholder.
      final duration = await AudioDurationProbe.probeFile(file.path);

      return AudioTrack(
        id: file.path,
        title: title,
        artist: artist,
        duration: duration,
        streamUrl: file.path,
        sourceTypeId: 'local',
        metadata: {
          'filePath': file.path,
          'fileSize': stat.size,
          'lastModified': stat.modified.toIso8601String(),
        },
      );
    } catch (e) {
      return null;
    }
  }
}

class LocalAudioSource extends BaseAudioSource {
  LocalAudioSource()
    : super(
        sourceTypeId: 'local',
        sourceName: 'Local Files',
        icon: Icons.folder,
        auth: LocalAuth(),
        scraper: LocalScraper(),
      );

  @override
  String? get helpText => '''
本地文件源。直接添加本机音频文件或文件夹：

• 单个文件：选择任意音频文件（mp3/wav/flac/m4a/ogg 等）
• 文件夹：选择目录，其中的音频文件都会加入

提示：
• 不需要网络和登录
• 支持播放本地录音（直播录制产生的文件也可直接添加）''';

  @override
  Future<bool> initialize(AudioSourceConfig config) async {
    // Request storage permission
    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.request().isGranted) {
        // Granted all files access
      } else if (await Permission.storage.request().isGranted) {
        // Granted storage permission
      } else {
        // Permission denied
        return false;
      }
    }

    final scraper = this.scraper as LocalScraper;
    scraper.rootDirectory = config.parameters?['rootDirectory'];
    scraper.rootDirectory ??= '/storage/emulated/0/Music';
    return true;
  }

  @override
  Future<List<AudioTrack>> search(String query, {int limit = 20}) async {
    final scraper = this.scraper as LocalScraper;
    if (scraper.rootDirectory == null) return [];

    try {
      final directory = Directory(scraper.rootDirectory!);
      final files = await scraper._scanDirectory(directory);

      final filteredFiles = files
          .where((file) {
            final fileName = path.basename(file.path).toLowerCase();
            return fileName.contains(query.toLowerCase());
          })
          .take(limit)
          .toList();

      final tracks = <AudioTrack>[];
      for (final file in filteredFiles) {
        final track = await scraper._createTrackFromFile(file);
        if (track != null) tracks.add(track);
      }

      return tracks;
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<AudioTrack>> getRecommendations({int limit = 20}) async {
    return await search('', limit: limit);
  }

  @override
  bool canHandleUrl(String url) {
    if (url.startsWith('file://')) return true;
    try {
      return File(url).existsSync() || Directory(url).existsSync();
    } catch (e) {
      // Invalid path (e.g. a network URL on Windows where ':' and '?' are
      // illegal path characters) - not a local file.
      return false;
    }
  }
}
