import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_hub/sources/douyu/douyu_scraper.dart';

/// Verifies that the douyu page-meta fallback extracts the room cover from
/// the new page layout (rpic.douyucdn.cn/asrpic / og:image) for rooms where
/// the betard API is blocked (e.g. 92020).
void main() {
  test('Douyu page-meta fallback extracts cover + avatar for restricted rooms',
      () async {
    final scraper = DouyuScraper();
    final meta = await scraper.fetchPageMetaForRecording('92020');
    // ignore: avoid_print
    print('meta: title=${meta.title} cover=${meta.cover} '
        'avatar=${meta.avatar} owner=${meta.owner} isLive=${meta.isLive}');
    expect(meta.title, isNotEmpty, reason: 'title should be parsed');
    expect(meta.cover, isNotEmpty, reason: 'cover must be extracted');
    expect(
      meta.cover.startsWith('http'),
      isTrue,
      reason: 'cover must be an absolute URL',
    );
    expect(meta.avatar, isNotEmpty, reason: 'owner avatar must be extracted');
    expect(
      meta.avatar.startsWith('http'),
      isTrue,
      reason: 'avatar must be an absolute URL',
    );
  });

  test('Douyu page-meta fallback works for a normal room (3484)', () async {
    final scraper = DouyuScraper();
    final meta = await scraper.fetchPageMetaForRecording('3484');
    // ignore: avoid_print
    print(
      'meta: title=${meta.title} cover=${meta.cover} '
      'avatar=${meta.avatar} isLive=${meta.isLive}',
    );
    expect(meta.title, isNotEmpty);
    expect(meta.cover, isNotEmpty);
    expect(meta.avatar, isNotEmpty);
  });
}
