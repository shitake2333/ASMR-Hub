import 'dart:io';

import 'package:flutter/material.dart';

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/audio_source.dart';
import 'package:asmr_hub/services/live_recorder.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/sources/base/base_source.dart';
import 'package:asmr_hub/sources/twitch/twitch_auth.dart';
import 'package:asmr_hub/sources/twitch/twitch_scraper.dart';

/// Twitch live source: audio-only playback of public channels.
class TwitchSource extends BaseAudioSource {
  final LogService _logger = LogService();

  TwitchSource()
    : super(
        sourceTypeId: 'twitch',
        sourceName: 'Twitch',
        icon: Icons.live_tv,
        auth: TwitchAuth(),
        scraper: TwitchScraper(),
      );

  TwitchScraper get _twitchScraper => scraper as TwitchScraper;

  @override
  bool get isLive => true;

  @override
  String? get helpText => '''
Twitch 直播源（仅音频）。支持以下链接：

• 频道页：https://www.twitch.tv/{channel}（如 /xqc）
  - 开播时可直接收听（audio-only），也可录制直播到本地文件
  - 支持后台多房间录制（播放列表页「我的播放列表」→ 直播监控）

提示：
• 匿名即可收听公开频道的音频流，无需登录
• 主播下播后房间卡片会显示「直播已下播」
• 需要网络连接''';

  @override
  Future<List<AudioTrack>> getRecommendations({int limit = 20}) async {
    // Recommendations are not implemented for Twitch; add channels by URL.
    return [];
  }

  @override
  bool canHandleUrl(String url) {
    return url.contains('twitch.tv');
  }

  @override
  Future<AudioTrack?> parseFromUrl(String url) async {
    if (!canHandleUrl(url)) {
      throw AudioSourceException(
        'Unrecognized Twitch URL: $url',
        sourceTypeId,
        type: AudioSourceExceptionType.unsupportedUrl,
      );
    }
    final channel = _twitchScraper.extractChannel(url);
    if (channel == null) {
      throw AudioSourceException(
        'Unrecognized Twitch channel: $url',
        sourceTypeId,
        type: AudioSourceExceptionType.unsupportedUrl,
      );
    }
    return AudioTrack(
      id: channel,
      title: 'Twitch Live $channel',
      artist: 'Twitch',
      duration: Duration.zero,
      streamUrl: '',
      sourceTypeId: 'twitch',
      metadata: {'isLive': false, 'isLiveCard': true, 'roomId': channel},
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
      LiveRecorder().isRecordingAny((k) => k.startsWith('twitch:'));

  @override
  Future<bool> startRecording(AudioTrack liveTrack) async {
    final channel = liveTrack.metadata?['roomId']?.toString() ?? liveTrack.id;
    if (channel.isEmpty) return false;

    try {
      var title = liveTrack.title;
      if (title.startsWith('Twitch Live')) {
        title = 'Twitch Live $channel';
      }

      final streamUrl = await scraper.scrapeStreamUrl(channel);
      if (streamUrl.isEmpty) return false;

      final dir = await _twitchScraper.recordingsDir(channel);
      final fileName = _twitchScraper.recordingFileName(title);
      final filePath = '$dir${Platform.pathSeparator}$fileName';

      // Twitch audio-only is HLS: record as MP3 via the FFmpeg bridge.
      return await LiveRecorder().startHls(
        streamUrl,
        filePath,
        key: 'twitch:$channel',
        bridgeHeaders:
            'User-Agent: '
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/120.0.0.0 Safari/537.36\r\n'
            'Client-ID: kimne78kx3ncx6brgo4mv6wki5h1ko',
        userAgent:
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/120.0.0.0 Safari/537.36',
      );
    } catch (e) {
      _logger.error('Failed to start Twitch recording', e);
      return false;
    }
  }

  @override
  Future<void> stopRecording() async {
    await LiveRecorder().stopWhere((k) => k.startsWith('twitch:'));
  }

  @override
  Future<List<AudioTrack>> loadRecordings(AudioTrack liveTrack) {
    final channel = liveTrack.metadata?['roomId']?.toString() ?? liveTrack.id;
    return _twitchScraper.loadRecordings(channel);
  }

  /// Whether the channel is currently streaming.
  @override
  Future<bool> isRoomLive(String roomId) async {
    return _twitchScraper.isChannelLive(roomId);
  }
}
