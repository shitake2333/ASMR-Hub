import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/audio_source.dart';
import 'package:asmr_hub/services/live_recorder.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/sources/base/base_source.dart';
import 'package:asmr_hub/sources/bilibili/bilibili_auth.dart';
import 'package:asmr_hub/sources/bilibili/bilibili_scraper.dart';

/// Bilibili source supporting:
///  - single videos (BV/av URLs),
///  - UGC seasons (合集) and favorite folders (收藏夹) as playlists,
///  - live rooms: current live + local recordings as a combined playlist,
///    with the ability to record the live stream to a local file.
class BilibiliSource extends BaseAudioSource {
  final LogService _logger = LogService();

  BilibiliSource()
    : super(
        sourceTypeId: 'bilibili',
        sourceName: 'Bilibili',
        icon: Icons.audio_file,
        iconAsset: 'lib/sources/bilibili/icon.svg',
        auth: BilibiliAuth.instance,
        scraper: BilibiliScraper(),
      );

  BilibiliScraper get _biliScraper => scraper as BilibiliScraper;

  @override
  bool get isLive => true;

  @override
  String? get helpText => '''
Bilibili（哔哩哔哩）源。支持以下链接：

• 单个视频：https://www.bilibili.com/video/BVxxxxxxxxxx
• 合集 / 剧集（多P）：https://www.bilibili.com/bangumi/... 或 合集页
• 收藏夹：https://space.bilibili.com/{uid}/favlist?fid={fid}
• 直播房间：https://live.bilibili.com/{roomId}
  - 开播时可直接收听，也可录制直播到本地文件
  - 支持后台多房间录制（播放列表页「我的播放列表」→ 直播监控）

提示：
• 高清音频需要登录（建议扫码登录），登录后自动携带 Cookie
• 部分付费/会员内容需要账号权限
• b23.tv 短链会自动解析''';

  /// Bilibili CDN requires browser headers (anti-hotlink).
  @override
  Map<String, String> downloadHeaders(AudioTrack track) => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://www.bilibili.com/',
  };

  @override
  Future<List<AudioTrack>> getRecommendations({int limit = 20}) async {
    // Recommendations are not implemented for Bilibili; browse by URL or
    // use the live-room watch list instead.
    return [];
  }

  @override
  bool canHandleUrl(String url) {
    return url.contains('bilibili.com') || url.contains('b23.tv');
  }

  @override
  Future<AudioTrack?> parseFromUrl(String url) async {
    final resolvedUrl = await _resolveUrl(url);
    final type = _biliScraper.detectUrlType(resolvedUrl);
    if (type == BilibiliUrlType.video || type == BilibiliUrlType.live) {
      return _biliScraper.scrapeVideo(resolvedUrl);
    }
    if (type == BilibiliUrlType.season || type == BilibiliUrlType.favorite) {
      throw AudioSourceException(
        'This is a playlist URL. Use getPlaylist instead.',
        sourceTypeId,
        type: AudioSourceExceptionType.playlistUrl,
      );
    }
    throw AudioSourceException(
      'Unrecognized Bilibili URL: $url',
      sourceTypeId,
      type: AudioSourceExceptionType.unsupportedUrl,
    );
  }

  @override
  Future<List<AudioTrack>> getPlaylist(String playlistUrl) async {
    final resolvedUrl = await _resolveUrl(playlistUrl);
    final type = _biliScraper.detectUrlType(resolvedUrl);
    if (type == BilibiliUrlType.season ||
        type == BilibiliUrlType.favorite ||
        type == BilibiliUrlType.live) {
      return _biliScraper.scrapePlaylist(resolvedUrl);
    }
    throw AudioSourceException(
      'Not a playlist URL: $playlistUrl',
      sourceTypeId,
      type: AudioSourceExceptionType.unsupportedUrl,
    );
  }

  Future<String> _resolveUrl(String url) async {
    if (url.contains('b23.tv')) {
      final client = http.Client();
      try {
        final request = http.Request('HEAD', Uri.parse(url))
          ..followRedirects = false;
        request.headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/120.0.0.0 Safari/537.36';
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode == 302 || response.statusCode == 301) {
          return response.headers['location'] ?? url;
        }
      } catch (e) {
        _logger.warning('Failed to resolve b23.tv URL: $e');
      } finally {
        client.close();
      }
    }
    return url;
  }

  // ------------------------------------------------------------ recording

  /// Whether a live recording is currently in progress.
  @override
  bool get isRecording =>
      LiveRecorder().isRecordingAny((k) => k.startsWith('bilibili:'));

  @override
  bool get supportsLiveRecording => true;

  /// Starts recording the live stream of [liveTrack] into the local
  /// recordings directory (file name uses the live title).
  @override
  Future<bool> startRecording(AudioTrack liveTrack) async {
    final roomId = _roomIdOf(liveTrack);
    if (roomId == 0) return false;

    try {
      // Use the real room title for the file name.
      var title = liveTrack.title;
      if (title.startsWith('Bilibili Live')) {
        try {
          final info = await _biliScraper.fetchLiveRoomInfo(roomId);
          title = info.title;
        } catch (e) {
          // keep the placeholder title
        }
      }

      final streamUrl = await scraper.scrapeStreamUrl(liveTrack.id);
      if (streamUrl.isEmpty) return false;

      final dir = await _biliScraper.recordingsDir(roomId);
      // Bilibili live is HLS: record as MP3 via the FFmpeg bridge.
      final fileName = _biliScraper.recordingFileName(title, extension: '.mp3');
      final filePath = '$dir${Platform.pathSeparator}$fileName';

      return await LiveRecorder().startHls(
        streamUrl,
        filePath,
        key: 'bilibili:$roomId',
        bridgeHeaders:
            'User-Agent: '
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/120.0.0.0 Safari/537.36\r\n'
            'Referer: https://live.bilibili.com/$roomId',
        userAgent:
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/120.0.0.0 Safari/537.36',
      );
    } catch (e) {
      _logger.error('Failed to start recording', e);
      return false;
    }
  }

  /// Stops the in-progress recording.
  @override
  Future<void> stopRecording() async {
    await LiveRecorder().stopWhere((k) => k.startsWith('bilibili:'));
  }

  /// Scans the local recordings of a live room.
  @override
  Future<List<AudioTrack>> loadRecordings(AudioTrack liveTrack) {
    final roomId = _roomIdOf(liveTrack);
    if (roomId == 0) return Future.value([]);
    return _biliScraper.loadRecordings(roomId);
  }

  int _roomIdOf(AudioTrack track) {
    return int.tryParse(track.metadata?['roomId']?.toString() ?? track.id) ?? 0;
  }

  /// Whether the room is currently streaming.
  @override
  Future<bool> isRoomLive(String roomId) async {
    final id = int.tryParse(roomId);
    if (id == null) return false;
    try {
      return (await _biliScraper.fetchLiveRoomInfo(id)).isLive;
    } catch (e) {
      return false;
    }
  }
}
