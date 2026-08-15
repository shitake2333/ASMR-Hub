// Tests for the Bilibili source URL detection (offline).
// Run: flutter test test/bilibili_url_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_hub/sources/bilibili/bilibili_scraper.dart';

void main() {
  final scraper = BilibiliScraper();

  test('detects video URLs', () {
    expect(
      scraper.detectUrlType('https://www.bilibili.com/video/BV1GJ411x7h7'),
      BilibiliUrlType.video,
    );
    expect(
      scraper.detectUrlType('https://b23.tv/abc123'),
      BilibiliUrlType.unknown, // resolved later
    );
    expect(
      scraper.detectUrlType('https://www.bilibili.com/video/av12345'),
      BilibiliUrlType.video,
    );
    expect(
      scraper.extractVideoId('https://www.bilibili.com/video/BV1GJ411x7h7'),
      'BV1GJ411x7h7',
    );
  });

  test('detects live URLs', () {
    expect(
      scraper.detectUrlType('https://live.bilibili.com/21452505'),
      BilibiliUrlType.live,
    );
    expect(
      scraper.extractLiveRoomId('https://live.bilibili.com/21452505'),
      21452505,
    );
  });

  test('detects season (合集) URLs', () {
    expect(
      scraper.detectUrlType(
        'https://space.bilibili.com/517327498/channel/collectiondetail?sid=3993361',
      ),
      BilibiliUrlType.season,
    );
    // New format: space.bilibili.com/{mid}/lists?sid=
    expect(
      scraper.detectUrlType(
        'https://space.bilibili.com/517327498/lists?sid=3993361',
      ),
      BilibiliUrlType.season,
    );
    final season = scraper.extractSeason(
      'https://space.bilibili.com/517327498/lists?sid=3993361',
    );
    expect(season, isNotNull);
    expect(season!.seasonId, 3993361);
    expect(season.mid, 517327498);
  });

  test('detects favorite (收藏夹) URLs', () {
    expect(
      scraper.detectUrlType('https://www.bilibili.com/medialist/play/ml12345'),
      BilibiliUrlType.favorite,
    );
    expect(
      scraper.detectUrlType('https://space.bilibili.com/123/favlist?fid=456'),
      BilibiliUrlType.favorite,
    );
    expect(
      scraper.extractFavoriteId(
        'https://www.bilibili.com/medialist/play/ml12345',
      ),
      12345,
    );
  });

  test('recording file name sanitizes title', () {
    final name = scraper.recordingFileName('测试:直播 <ASMR> "标题"');
    expect(name.contains(':'), isFalse);
    expect(name.contains('<'), isFalse);
    expect(name.contains('"'), isFalse);
    expect(name.endsWith('.flv'), isTrue);
  });
}
