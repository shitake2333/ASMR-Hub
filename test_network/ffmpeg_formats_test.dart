// Verify the FFmpeg decoder handles all target formats: Bilibili DASH m4s,
// Bilibili live HLS (m3u8), Douyu FLV, and local audio files. Also verifies
// decodeToFile writes a valid PCM WAV.
// Run: flutter test test/ffmpeg_formats_test.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_hub/services/ffmpeg/ffmpeg_audio_decoder.dart';
import 'package:asmr_hub/sources/bilibili/bilibili_api.dart';
import 'package:asmr_hub/sources/douyu/douyu_scraper.dart';

List<int> _u32le(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

Uint8List _wavBytes() {
  const sr = 44100;
  final pcm = sr * 2;
  final w = BytesBuilder();
  w.add('RIFF'.codeUnits);
  w.add(_u32le(36 + pcm));
  w.add('WAVE'.codeUnits);
  w.add('fmt '.codeUnits);
  w.add(_u32le(16));
  w.add([1, 0]);
  w.add([1, 0]);
  w.add(_u32le(sr));
  w.add(_u32le(sr * 2));
  w.add([2, 0]);
  w.add([16, 0]);
  w.add('data'.codeUnits);
  w.add(_u32le(pcm));
  for (var i = 0; i < pcm ~/ 2; i++) {
    final v = (32767 * 0.3 * sin(i * 2 * 3.14159 * 440 / sr)).round();
    w.add([v & 0xFF, (v >> 8) & 0xFF]);
  }
  return w.takeBytes();
}

/// Runs a pull-mode decoder against [url] and returns bytes of PCM received
/// within [wait].
Future<int> _decodeFor(
  String url, {
  String? headers,
  Duration wait = const Duration(seconds: 8),
}) async {
  final decoder = FfmpegAudioDecoder();
  final info = await decoder.start(url, headers: headers);
  if (info == null) return 0;
  var received = 0;
  final end = DateTime.now().add(wait);
  while (DateTime.now().isBefore(end)) {
    final remaining = end.difference(DateTime.now());
    final chunk = await decoder
        .nextChunk()
        .timeout(remaining, onTimeout: () => null);
    if (chunk == null) break;
    received += chunk.length;
  }
  await decoder.stop();
  return received;
}

void main() {
  test('decodes local WAV file', () async {
    final file = File('${Directory.systemTemp.path}/fmt_test.wav');
    file.writeAsBytesSync(_wavBytes());
    final bytes = await _decodeFor(file.path);
    expect(bytes, greaterThanOrEqualTo(44100 * 2 * 2),
        reason: 'local 1s wav must fully decode to PCM');
    try {
      file.deleteSync();
    } catch (_) {}
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('decodeToFile writes a valid PCM WAV', () async {
    final file = File('${Directory.systemTemp.path}/fmt_test.wav');
    file.writeAsBytesSync(_wavBytes());
    final out = File('${Directory.systemTemp.path}/fmt_out.wav');
    final decoder = FfmpegAudioDecoder();
    final ok = await decoder.decodeToFile(file.path, out.path);
    expect(ok, isTrue, reason: 'decodeToFile must succeed');
    expect(out.existsSync(), isTrue);
    final size = await out.length();
    expect(size, 44 + 44100 * 2 * 2,
        reason: '1s 44100Hz stereo s16 WAV = header + PCM');
    // Verify header fields.
    final bytes = await out.readAsBytes();
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(bytes[22] | (bytes[23] << 8), 2, reason: 'channels = 2');
    expect(
      bytes[24] | (bytes[25] << 8) | (bytes[26] << 16) | (bytes[27] << 24),
      44100,
      reason: 'sample rate = 44100',
    );
    await decoder.stop();
    try {
      file.deleteSync();
      out.deleteSync();
    } catch (_) {}
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('decodes bilibili DASH m4s', () async {
    final api = BilibiliApi();
    final info = await api.fetchVideoInfo('BV1GJ411x7h7');
    final url = await api.fetchAudioUrl(info.bvid, info.cid);
    final bytes = await _decodeFor(
      url,
      headers: 'Referer: https://www.bilibili.com/\r\n'
          'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 '
          'Safari/537.36',
    );
    expect(bytes, greaterThan(44100 * 2 * 2),
        reason: 'bilibili m4s must decode to PCM');
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('decodes bilibili live HLS (m3u8)', () async {
    // Get a live room stream URL. All test rooms may be offline (early
    // morning); in that case skip with a note instead of failing.
    final api = BilibiliApi();
    String? url;
    try {
      final info = await api.fetchLiveRoomInfo(27109059);
      if (!info.isLive) {
        stdout.writeln('SKIP: room 27109059 offline');
        return;
      }
      url = await api.fetchLiveStreamUrl(27109059);
    } catch (e) {
      stdout.writeln('SKIP: cannot fetch live URL: $e');
      return;
    }
    expect(url, isNotNull);
    stdout.writeln('HLS URL: ${url.substring(0, 80)}...');
    final bytes = await _decodeFor(
      url,
      headers: 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'Chrome/120.0.0.0\r\nReferer: https://live.bilibili.com/',
      wait: const Duration(seconds: 15),
    );
    expect(bytes, greaterThan(0),
        reason: 'live HLS must stream some PCM (may be silent if offline)');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('decodes douyu FLV live stream', () async {
    final scraper = DouyuScraper();
    String? url;
    try {
      final track = await scraper.scrapeVideo('https://www.douyu.com/24422');
      url = await scraper.scrapeStreamUrl(track.id);
    } catch (e) {
      fail('cannot fetch douyu URL: $e');
    }
    expect(url, isNotNull);
    stdout.writeln('FLV URL: ${url.substring(0, 80)}...');
    final bytes = await _decodeFor(
      url,
      headers: 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'Chrome/120.0.0.0\r\nReferer: https://www.douyu.com/',
      wait: const Duration(seconds: 10),
    );
    expect(bytes, greaterThan(0),
        reason: 'douyu FLV must stream some PCM');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
