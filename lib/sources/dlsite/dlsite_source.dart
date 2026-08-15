import 'package:flutter/material.dart';

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/audio_source.dart';
import 'package:asmr_hub/sources/base/base_source.dart';
import 'package:asmr_hub/sources/dlsite/dlsite_auth.dart';
import 'package:asmr_hub/sources/dlsite/dlsite_scraper.dart';

class DLSiteSource extends BaseAudioSource {
  DLSiteSource()
    : super(
        sourceTypeId: 'dlsite',
        sourceName: 'DLSite',
        icon: Icons.book, // Placeholder icon; a DLSite SVG could replace this.
        auth: DLSiteAuth.instance,
        scraper: DLSiteScraper(),
      );

  @override
  String? get helpText => '''
DLSite 源：DLsite（日本数字内容商店）的 ASMR/音声作品。

支持以下链接：
• 作品页：https://www.dlsite.com/maniax/work/=/product_id/RJ{id}.html
  （作品会以多音轨播放列表方式加入）

提示：
• 需要登录账号（用户名/密码或 Cookie）才能播放已购买的作品
• 建议使用「浏览器登录」方式，直接打开 DLsite 登录页
• 未购买的作品无法播放''';

  @override
  Future<List<AudioTrack>> getRecommendations({int limit = 20}) async {
    // Recommendations are not implemented for DLSite; open works by RJ URL.
    return [];
  }

  @override
  bool canHandleUrl(String url) {
    return url.contains('dlsite.com');
  }

  @override
  Future<AudioTrack?> parseFromUrl(String url) async {
    // DLSite works are multi-track playlists; direct the detail page to
    // getPlaylist instead.
    if (canHandleUrl(url)) {
      throw AudioSourceException(
        'This is a DLSite work URL. Use getPlaylist instead.',
        sourceTypeId,
        type: AudioSourceExceptionType.playlistUrl,
      );
    }
    throw AudioSourceException(
      'Unrecognized DLSite URL: $url',
      sourceTypeId,
      type: AudioSourceExceptionType.unsupportedUrl,
    );
  }

  @override
  Future<List<AudioTrack>> getPlaylist(String playlistUrl) async {
    return scraper.scrapePlaylist(playlistUrl);
  }

  /// The optimized audio CDN requires the play referer.
  @override
  Map<String, String> downloadHeaders(AudioTrack track) => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://play.dlsite.com/',
  };
}
