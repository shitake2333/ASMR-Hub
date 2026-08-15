import 'package:flutter/material.dart';

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/audio_source.dart';
import 'package:asmr_hub/sources/base/base_source.dart';
import 'package:asmr_hub/sources/youtube/youtube_auth.dart';
import 'package:asmr_hub/sources/youtube/youtube_scraper.dart';

class YouTubeSource extends BaseAudioSource {
  YouTubeSource()
    : super(
        sourceTypeId: 'youtube',
        sourceName: 'YouTube',
        icon: Icons.audio_file,
        iconAsset: 'lib/sources/youtube/icon.svg',
        auth: YouTubeAuth(),
        scraper: YouTubeScraper(),
      );

  @override
  String? get helpText => '''
YouTube 源。支持以下链接：

• 单个视频：https://www.youtube.com/watch?v={id}
• 短链接：https://youtu.be/{id}
• 播放列表：https://www.youtube.com/playlist?list={id}
  - 播放列表会以多曲目方式加入

提示：
• 视频仅提取音频（不播放画面）
• 登录（浏览器/Cookie）可访问会员或受限内容
• 需要网络连接；YouTube 可能对部分区域有限制''';

  @override
  Future<List<AudioTrack>> search(String query, {int limit = 20}) async {
    // In-app search is not exposed by the UI yet; paste a video/playlist URL
    // to add content.
    return [];
  }

  @override
  Future<List<AudioTrack>> getRecommendations({int limit = 20}) async {
    // Recommendations are not implemented for YouTube; add videos by URL.
    return [];
  }

  @override
  bool canHandleUrl(String url) {
    return url.contains('youtube.com') || url.contains('youtu.be');
  }

  @override
  Future<AudioTrack?> parseFromUrl(String url) async {
    if (!canHandleUrl(url)) {
      throw AudioSourceException(
        'Unrecognized YouTube URL: $url',
        sourceTypeId,
        type: AudioSourceExceptionType.unsupportedUrl,
      );
    }
    // Playlist URLs go through getPlaylist; single videos parse directly.
    if (YouTubeScraper.extractPlaylistId(url) != null) {
      throw AudioSourceException(
        'This is a YouTube playlist URL. Use getPlaylist instead.',
        sourceTypeId,
        type: AudioSourceExceptionType.playlistUrl,
      );
    }
    return scraper.scrapeVideo(url);
  }

  @override
  Future<List<AudioTrack>> getPlaylist(String playlistUrl) async {
    return scraper.scrapePlaylist(playlistUrl);
  }
}
