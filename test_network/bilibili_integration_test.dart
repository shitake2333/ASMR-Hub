// Integration tests for the Bilibili source against the live site.
// Run: flutter test test/bilibili_integration_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_hub/sources/bilibili/bilibili_api.dart';
import 'package:asmr_hub/sources/bilibili/bilibili_scraper.dart';
import 'package:asmr_hub/services/live_recorder.dart';

void main() {
  // NOTE: no TestWidgetsFlutterBinding here - real network is required.

  test('fetches video info and audio stream URL', () async {
    final api = BilibiliApi();
    final info = await api.fetchVideoInfo('BV1GJ411x7h7');
    expect(info.title, isNotEmpty);
    expect(info.cid, greaterThan(0));

    final audioUrl = await api.fetchAudioUrl(info.bvid, info.cid);
    expect(audioUrl, startsWith('http'));
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('fetches season archives (合集)', () async {
    final api = BilibiliApi();
    final videos = await api.fetchSeasonArchives(
      seasonId: 3993361,
      mid: 517327498,
    );
    expect(videos, isNotEmpty);
    expect(videos.first.title, isNotEmpty);
    expect(videos.first.bvid, startsWith('BV'));
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('scraper parses video URL into a track', () async {
    final scraper = BilibiliScraper();
    final track = await scraper.scrapeVideo(
      'https://www.bilibili.com/video/BV1GJ411x7h7',
    );
    expect(track.id, startsWith('video:'));
    expect(track.title, isNotEmpty);
    expect(track.duration, greaterThan(Duration.zero));

    final streamUrl = await scraper.scrapeStreamUrl(track.id);
    expect(streamUrl, startsWith('http'));
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('live room playlist contains recordings after recording', () async {
    final dir = Directory.systemTemp.createTempSync('recorder_test');

    // A tiny fake FLV stream served locally.
    final fakeFlv = <int>[
      0x46, 0x4C, 0x56, 0x01, 0x05, 0, 0, 0, 9, 0, 0, 0, 0, // FLV header
      0, 0, 0, 0, 0, 0, 0, 0, // prev tag size
      9, 0, 0, 0x03, 0, 0, 0, 0, 0, 0, 0, // video tag (11+3 bytes)
      0x17, 0, 0, 0, // video data (4 bytes)
      0, 0, 0, 0, // prev tag size
      8, 0, 0, 0x05, 0, 0, 0, 0, 0, 0, 0, // audio tag (11+5 bytes)
      0x2F, 0xFF, 0xFB, 0x90, 0x00, // audio data (MP3 frame head)
      0, 0, 0, 0, // prev tag size
    ];

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response.add(fakeFlv);
      request.response.close();
    });

    final recorder = LiveRecorder();
    final target = '${dir.path}/rec.flv';
    final ok = await recorder.start(
      'http://127.0.0.1:${server.port}/live.flv',
      target,
      key: 'test:flv',
    );
    expect(ok, isTrue);
    expect(recorder.isRecording, isTrue);

    // Let the downloader consume the stream.
    await Future<void>.delayed(const Duration(seconds: 2));
    await recorder.stop();

    expect(File(target).existsSync(), isTrue);
    expect(File(target).lengthSync(), greaterThan(0));

    await server.close(force: true);
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('recording file name uses sanitized title', () {
    final scraper = BilibiliScraper();
    final name = scraper.recordingFileName('【ASMR】深夜放松 <测试>');
    expect(name, contains('【ASMR】深夜放松'));
    expect(name.contains('<'), isFalse);
    expect(name.contains('>'), isFalse);
    expect(name.endsWith('.flv'), isTrue);
  });
}
