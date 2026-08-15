// cid fallback test for bilibili tracks
import 'package:flutter_test/flutter_test.dart';
import 'package:asmr_hub/sources/bilibili/bilibili_scraper.dart';

void main() {
  test('scrapeStreamUrl resolves missing cid via view API', () async {
    final scraper = BilibiliScraper();
    // cid=0 simulates favorite/season API tracks
    final url = await scraper.scrapeStreamUrl('video:BV1GJ411x7h7:0');
    expect(url, startsWith('http'));
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('scrapeStreamUrl uses provided cid', () async {
    final scraper = BilibiliScraper();
    final url = await scraper.scrapeStreamUrl('video:BV1GJ411x7h7:137649199');
    expect(url, startsWith('http'));
  }, timeout: const Timeout(Duration(minutes: 1)));
}
