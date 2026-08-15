import 'package:flutter/material.dart';

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/audio_source.dart';
import 'package:asmr_hub/sources/asmrone/asmr_one_auth.dart';
import 'package:asmr_hub/sources/asmrone/asmr_one_scraper.dart';
import 'package:asmr_hub/sources/base/base_source.dart';

/// asmr.one source: Japanese doujin ASMR works and user playlists.
class AsmrOneSource extends BaseAudioSource {
  AsmrOneSource()
    : super(
        sourceTypeId: 'asmrone',
        sourceName: 'asmr.one',
        icon: Icons.graphic_eq,
        auth: AsmrOneAuth.instance,
        scraper: AsmrOneScraper(),
      );

  @override
  String? get helpText => '''
asmr.one 源：日本同人 ASMR 音声作品站。支持以下链接：

• 作品页（多音轨）：https://asmr.one/work/{id}
• 播放列表：https://asmr.one/playlist?id={uuid}

提示：
• 打开播放列表需要登录账号（用户名/密码或 Cookie）
• 免费注册：登录页提供注册入口（无需邮箱）
• 作品通常包含多个音轨，会作为播放列表加入''';

  @override
  Future<List<AudioTrack>> getRecommendations({int limit = 20}) async {
    // Recommendations are not implemented for asmr.one (no public
    // recommendation endpoint); the source list is navigated manually.
    return [];
  }

  @override
  bool canHandleUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host == 'asmr.one' ||
        host == 'www.asmr.one' ||
        host == 'asmr-200.com' ||
        host.endsWith('.asmr.one');
  }

  @override
  Future<AudioTrack?> parseFromUrl(String url) async {
    if (!canHandleUrl(url)) {
      throw AudioSourceException(
        'Unrecognized asmr.one URL: $url',
        sourceTypeId,
        type: AudioSourceExceptionType.unsupportedUrl,
      );
    }
    // Playlists and works are multi-track; use getPlaylist.
    throw AudioSourceException(
      'This is an asmr.one playlist/work URL. Use getPlaylist instead.',
      sourceTypeId,
      type: AudioSourceExceptionType.playlistUrl,
    );
  }

  @override
  Future<List<AudioTrack>> getPlaylist(String playlistUrl) async {
    return scraper.scrapePlaylist(playlistUrl);
  }

  /// The media CDN requires the asmr.one referer.
  @override
  Map<String, String> downloadHeaders(AudioTrack track) => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://asmr.one/',
  };
}
