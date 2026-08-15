import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/sources/base/source_scraper.dart';

/// YouTube scraper powered by youtube_explode_dart (handles innertube API,
/// stream signing and the n-parameter obfuscation).
///
/// Supports single videos (`watch?v=...`, `youtu.be/...`) and playlists
/// (`playlist?list=...`, `watch?v=...&list=...`).
class YouTubeScraper implements SourceScraper {
  static String? extractVideoId(String url) {
    final m = RegExp(
      r'(?:watch\?.*v=|youtu\.be/|/shorts/|/embed/)([A-Za-z0-9_-]{11})',
    ).firstMatch(url);
    return m?.group(1);
  }

  static String? extractPlaylistId(String url) {
    final m = RegExp(r'[?&]list=([A-Za-z0-9_-]{10,})').firstMatch(url);
    return m?.group(1);
  }

  /// Best audio-only stream URL for a video.
  Future<String> _resolveAudioUrl(String videoId) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      // Prefer high-bitrate audio-only streams (opus/m4a).
      final streams = manifest.audioOnly.toList();
      if (streams.isEmpty) {
        throw Exception('No audio streams available for $videoId');
      }
      streams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
      final best = streams.first;
      return best.url.toString();
    } finally {
      yt.close();
    }
  }

  @override
  Future<List<AudioTrack>> scrapePlaylist(String url) async {
    final playlistId = extractPlaylistId(url);
    if (playlistId == null) {
      throw Exception('Not a YouTube playlist URL: $url');
    }

    // youtube_explode's playlist parser lags behind YouTube's page
    // structure (it currently yields no videos), so parse the playlist
    // page's ytInitialData directly (lockupViewModel items).
    final response = await http.get(
      Uri.parse('https://www.youtube.com/playlist?list=$playlistId&hl=en'),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept-Language': 'en',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('YouTube playlist failed (${response.statusCode})');
    }
    final data = _extractInitialData(response.body);
    final tracks = <AudioTrack>[];
    _walkJson(data, (node) {
      final vm = node['lockupViewModel'];
      if (vm is! Map<String, dynamic>) return;
      final videoId = vm['contentId']?.toString();
      if (videoId == null ||
          !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
        return;
      }
      final meta = vm['metadata']?['lockupMetadataViewModel'];
      final title = meta?['title']?['content']?.toString() ?? '';
      if (title.isEmpty) return;
      String channel = '';
      final rows =
          meta?['metadata']?['contentMetadataViewModel']?['metadataRows']
              as List<dynamic>?;
      if (rows != null && rows.isNotEmpty) {
        final parts = rows.first['metadataParts'] as List<dynamic>? ?? [];
        if (parts.isNotEmpty) {
          channel = parts.first['text']?['content']?.toString() ?? '';
        }
      }
      String cover = '';
      final sources =
          vm['contentImage']?['thumbnailViewModel']?['image']?['sources']
              as List<dynamic>?;
      if (sources != null && sources.isNotEmpty) {
        cover = sources.first['url']?.toString() ?? '';
      }
      Duration duration = Duration.zero;
      final badges =
          vm['contentImage']?['thumbnailViewModel']?['overlays']
              as List<dynamic>?;
      if (badges != null && badges.isNotEmpty) {
        final badge =
            badges.first['thumbnailBottomOverlayViewModel']?['badges']
                as List<dynamic>?;
        if (badge != null && badge.isNotEmpty) {
          duration = _parseYtDuration(
            badge.first['thumbnailBadgeViewModel']?['text']?.toString() ?? '',
          );
        }
      }
      tracks.add(
        AudioTrack(
          id: 'youtube:$videoId',
          title: title,
          artist: channel.isEmpty ? 'YouTube' : channel,
          albumArt: cover.isEmpty ? null : cover,
          duration: duration,
          streamUrl: '',
          sourceTypeId: 'youtube',
          metadata: {'playlist': playlistId},
        ),
      );
    });
    if (tracks.isEmpty) {
      throw Exception('No videos found in playlist $playlistId');
    }
    return tracks;
  }

  static Duration _parseYtDuration(String text) {
    final parts = text.trim().split(':').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) return Duration.zero;
    if (parts.length == 3) {
      return Duration(hours: parts[0]!, minutes: parts[1]!, seconds: parts[2]!);
    }
    if (parts.length == 2) {
      return Duration(minutes: parts[0]!, seconds: parts[1]!);
    }
    return Duration.zero;
  }

  /// Extracts `var ytInitialData = {...};` from the page HTML.
  static dynamic _extractInitialData(String html) {
    final m = RegExp(
      r'var ytInitialData = (\{.+?\});</script>',
      dotAll: true,
    ).firstMatch(html);
    if (m == null) throw Exception('ytInitialData not found');
    return jsonDecode(m.group(1)!);
  }

  /// Recursively visits every map node in [data].
  static void _walkJson(
    dynamic data,
    void Function(Map<String, dynamic>) visit,
  ) {
    if (data is Map<String, dynamic>) {
      visit(data);
      for (final v in data.values) {
        _walkJson(v, visit);
      }
    } else if (data is List) {
      for (final v in data) {
        _walkJson(v, visit);
      }
    }
  }

  @override
  Future<AudioTrack> scrapeVideo(String url) async {
    final videoId = extractVideoId(url);
    if (videoId == null) {
      throw Exception('Unrecognized YouTube URL: $url');
    }
    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(videoId);
      return AudioTrack(
        id: 'youtube:$videoId',
        title: video.title,
        artist: video.author,
        albumArt: video.thumbnails.highResUrl,
        duration: video.duration ?? Duration.zero,
        streamUrl: '',
        sourceTypeId: 'youtube',
      );
    } finally {
      yt.close();
    }
  }

  @override
  Future<String> scrapeStreamUrl(String trackId, {String? quality}) async {
    // youtube:{videoId}
    final parts = trackId.split(':');
    if (parts.length != 2 || parts[0] != 'youtube') {
      throw Exception('Invalid YouTube track id: $trackId');
    }
    return _resolveAudioUrl(parts[1]);
  }
}
