// Reproduce the in-app add-source flow for Bilibili URLs.
// Run: flutter test test/bilibili_repro_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_hub/sources/bilibili/bilibili_source.dart';

void main() {
  final source = BilibiliSource();

  test('video URL parse', () async {
    final track = await source.parseFromUrl(
      'https://www.bilibili.com/video/BV1GJ411x7h7',
    );
    expect(track, isNotNull);
    expect(track!.title, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('season URL getPlaylist', () async {
    final tracks = await source.getPlaylist(
      'https://space.bilibili.com/517327498/channel/collectiondetail?sid=3993361',
    );
    expect(tracks, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('favorite URL getPlaylist', () async {
    final tracks = await source.getPlaylist(
      'https://space.bilibili.com/5930584/favlist?fid=2584246284',
    );
    expect(tracks, isNotEmpty);
    expect(tracks.first.id, startsWith('video:'));
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('b23.tv short link parse', () async {
    final track = await source.parseFromUrl('https://b23.tv/XXXX');
    expect(track, isNull); // may fail gracefully
  }, timeout: const Timeout(Duration(minutes: 1)));
}
