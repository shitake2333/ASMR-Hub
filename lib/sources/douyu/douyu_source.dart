import 'dart:io';

import 'package:flutter/material.dart';

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/audio_source.dart';
import 'package:asmr_hub/services/live_recorder.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/sources/base/base_source.dart';
import 'package:asmr_hub/sources/douyu/douyu_auth.dart';
import 'package:asmr_hub/sources/douyu/douyu_scraper.dart';

class DouyuSource extends BaseAudioSource {
  final LogService _logger = LogService();

  DouyuSource()
    : super(
        sourceTypeId: 'douyu',
        sourceName: 'Douyu',
        icon: Icons.live_tv,
        auth: DouyuAuth.instance,
        scraper: DouyuScraper(),
      );

  DouyuScraper get _douyuScraper => scraper as DouyuScraper;

  @override
  bool get isLive => true;

  @override
  String? get helpText => '''
Douyu（斗鱼）直播源。支持以下链接：

• 直播房间：https://www.douyu.com/{roomId}（如 /92020）
  - 开播时可直接收听，也可录制直播到本地文件
  - 支持后台多房间录制（播放列表页「我的播放列表」→ 直播监控）

提示：
• 扫码登录后可获得完整房间列表与高清画质
• 部分直播间存在地域/鉴权限制，无法播放时会提示
• 主播下播后房间卡片会显示「直播已下播」''';

  @override
  Future<List<AudioTrack>> getRecommendations({int limit = 20}) async {
    // Recommendations are not implemented for Douyu; add rooms by URL.
    return [];
  }

  @override
  bool canHandleUrl(String url) {
    return url.contains('douyu.com') || url.contains('douyutv.com');
  }

  @override
  Future<AudioTrack?> parseFromUrl(String url) async {
    if (!canHandleUrl(url)) {
      throw AudioSourceException(
        'Unrecognized Douyu URL: $url',
        sourceTypeId,
        type: AudioSourceExceptionType.unsupportedUrl,
      );
    }
    // Accept any URL with a valid room id; the live room info is fetched
    // when the user opens the source (offline rooms stay addable).
    final roomId = await _douyuScraper.resolveRoomId(url);
    if (roomId == null) {
      throw AudioSourceException(
        'Unrecognized Douyu room: $url',
        sourceTypeId,
        type: AudioSourceExceptionType.unsupportedUrl,
      );
    }
    return AudioTrack(
      id: roomId,
      title: 'Douyu Live $roomId',
      artist: 'Douyu',
      duration: Duration.zero,
      streamUrl: '',
      sourceTypeId: 'douyu',
      metadata: {'isLive': false, 'isLiveCard': true, 'roomId': roomId},
    );
  }

  @override
  Future<List<AudioTrack>> getPlaylist(String playlistUrl) async {
    // Live rooms expose the unified live-card + recordings playlist.
    return scraper.scrapePlaylist(playlistUrl);
  }

  // ------------------------------------------------------------ recording

  @override
  bool get supportsLiveRecording => true;

  @override
  bool get isRecording =>
      LiveRecorder().isRecordingAny((k) => k.startsWith('douyu:'));

  @override
  Future<bool> startRecording(AudioTrack liveTrack) async {
    final roomId = liveTrack.metadata?['roomId']?.toString() ?? liveTrack.id;
    if (roomId.isEmpty) return false;

    try {
      var title = liveTrack.title;
      if (title.startsWith('Douyu Live')) {
        try {
          final room = await _douyuScraper.fetchRoomInfoForRecording(roomId);
          if (room.isNotEmpty && room['room_name'] != null) {
            title = room['room_name'].toString();
          }
        } catch (e) {
          // keep placeholder title
        }
      }

      final streamUrl = await scraper.scrapeStreamUrl(roomId);
      if (streamUrl.isEmpty) return false;

      final dir = await _douyuScraper.recordingsDir(roomId);
      final fileName = _douyuScraper.recordingFileName(title);
      final filePath = '$dir${Platform.pathSeparator}$fileName';

      // Douyu streams FLV directly over HTTP.
      return await LiveRecorder().start(
        streamUrl,
        filePath,
        key: 'douyu:$roomId',
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://www.douyu.com/$roomId',
        },
      );
    } catch (e) {
      _logger.error('Failed to start Douyu recording', e);
      return false;
    }
  }

  @override
  Future<void> stopRecording() async {
    await LiveRecorder().stopWhere((k) => k.startsWith('douyu:'));
  }

  @override
  Future<List<AudioTrack>> loadRecordings(AudioTrack liveTrack) {
    final roomId = liveTrack.metadata?['roomId']?.toString() ?? liveTrack.id;
    return _douyuScraper.loadRecordings(roomId);
  }

  /// Whether the room is currently streaming.
  @override
  Future<bool> isRoomLive(String roomId) async {
    try {
      final room = await _douyuScraper.fetchRoomInfoForRecording(roomId);
      return room['show_status'] == 1 && room['videoLoop'] != 1;
    } catch (e) {
      // betard is rate-limited for some rooms: fall back to the room page.
      final meta = await _douyuScraper.fetchPageMetaForRecording(roomId);
      return meta.isLive;
    }
  }
}
