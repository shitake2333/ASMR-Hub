import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/audio_source.dart';
import 'package:asmr_hub/services/cache_service.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/sources/base/source_auth.dart';
import 'package:asmr_hub/sources/base/source_scraper.dart';

abstract class BaseAudioSource extends AudioSource {
  @override
  final String sourceTypeId;
  @override
  final String sourceName;
  @override
  final IconData icon;
  @override
  final String? iconAsset;

  final SourceAuth auth;
  final SourceScraper scraper;

  BaseAudioSource({
    required this.sourceTypeId,
    required this.sourceName,
    required this.icon,
    this.iconAsset,
    required this.auth,
    required this.scraper,
  });

  @override
  bool get requiresAuth => auth.requiresAuth;

  @override
  bool get supportsSearch => true;

  @override
  bool get supportsPlaylists => true;

  @override
  bool get isLive => false;

  @override
  Widget getIcon(
    BuildContext context, {
    String? path,
    double? size,
    Color? color,
  }) {
    final iconColor = color ?? Theme.of(context).colorScheme.primary;
    final iconSize = size ?? 24.0;

    if (path != null) {
      try {
        final iconPath = '$path${Platform.pathSeparator}icon.svg';
        final iconFile = File(iconPath);
        if (iconFile.existsSync()) {
          return SvgPicture.file(
            iconFile,
            width: iconSize,
            height: iconSize,
            colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
          );
        }
      } catch (e) {
        // Ignore errors
      }
    }

    if (iconAsset != null) {
      return SvgPicture.asset(
        iconAsset!,
        width: iconSize,
        height: iconSize,
        colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
      );
    }

    return Icon(icon, size: iconSize, color: iconColor);
  }

  @override
  Future<bool> initialize(AudioSourceConfig config) async {
    return true;
  }

  @override
  Future<List<AudioTrack>> search(String query, {int limit = 20}) async {
    return [];
  }

  @override
  Future<String> getStreamUrl(String trackId, {String? quality}) async {
    return scraper.scrapeStreamUrl(trackId, quality: quality);
  }

  @override
  Future<List<AudioTrack>> getPlaylist(String playlistUrl) async {
    return scraper.scrapePlaylist(playlistUrl);
  }

  @override
  Future<List<AudioTrack>> getRecommendations({int limit = 20}) async {
    return [];
  }

  @override
  Future<AudioTrack?> parseFromUrl(String url) async {
    try {
      return await scraper.scrapeVideo(url);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<AudioTrack?> getTrackInfo(String trackId) async {
    return null;
  }

  @override
  Future<bool> checkAvailability() async {
    return true;
  }

  /// Default implementation: downloads the stream URL into the source's
  /// cache directory. Sources with anti-hotlink CDNs (e.g. Bilibili) should
  /// override this to attach the required request headers.
  @override
  Future<void> download(AudioTrack track) async {
    if (track.metadata?['isLive'] == true) {
      throw Exception('Live streams cannot be downloaded; use recording');
    }
    final streamUrl = track.streamUrl.isNotEmpty
        ? track.streamUrl
        : await getStreamUrl(track.id);
    if (streamUrl.isEmpty) {
      throw Exception('No stream URL available for download');
    }
    final cachePath = await CacheService().getCacheFilePath(
      sourceTypeId,
      track.id,
    );
    final file = File(cachePath);
    if (await file.exists()) {
      // Already cached.
      return;
    }
    await file.parent.create(recursive: true);

    // Local files (e.g. recordings) are copied directly instead of fetched.
    if (!streamUrl.startsWith('http')) {
      final sourceFile = File(streamUrl);
      if (await sourceFile.exists()) {
        await sourceFile.copy(cachePath);
        LogService().info('Copied ${track.title} -> $cachePath');
      } else {
        throw Exception('Local file not found: $streamUrl');
      }
      return;
    }

    final request = http.Request('GET', Uri.parse(streamUrl));
    final headers = downloadHeaders(track);
    for (final entry in headers.entries) {
      request.headers.putIfAbsent(entry.key, () => entry.value);
    }
    final response = await request.send().timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw Exception('Download failed with status ${response.statusCode}');
    }
    final sink = file.openWrite();
    try {
      await response.stream.pipe(sink);
    } finally {
      await sink.close();
    }
    LogService().info('Downloaded ${track.title} -> $cachePath');
  }

  /// Extra HTTP headers used by [download]. Override in sources whose CDN
  /// requires browser headers.
  Map<String, String> downloadHeaders(AudioTrack track) => const {};

  // ------------------------------------------------------- live recording

  @override
  bool get supportsLiveRecording => false;

  @override
  bool get isRecording => false;

  @override
  Future<bool> startRecording(AudioTrack liveTrack) async => false;

  @override
  Future<void> stopRecording() async {}

  @override
  Future<List<AudioTrack>> loadRecordings(AudioTrack liveTrack) async => [];

  @override
  Future<bool> isRoomLive(String roomId) async => false;

  @override
  String? get helpText => null;

  @override
  Future<void> dispose() async {
    // Default implementation
  }
}
