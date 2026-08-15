// End-to-end: FFmpeg decoder isolate decodes a real Bilibili DASH audio.
// Run: flutter test test/ffmpeg_decoder_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_hub/services/ffmpeg/ffmpeg_audio_decoder.dart';
import 'package:asmr_hub/sources/bilibili/bilibili_api.dart';

void main() {
  test('decoder pulls PCM from a bilibili DASH audio URL', () async {
    final api = BilibiliApi();
    final info = await api.fetchVideoInfo('BV1GJ411x7h7');
    final url = await api.fetchAudioUrl(info.bvid, info.cid);

    final decoder = FfmpegAudioDecoder();
    final decoded = await decoder.start(
      url,
      headers: 'Referer: https://www.bilibili.com/\r\n'
          'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 '
          'Safari/537.36',
    );
    expect(decoded, isNotNull, reason: 'decoder must report audio info');
    stdout.writeln(
      'DECODED: ${decoded!.sampleRate}Hz ${decoded.channels}ch',
    );
    expect(decoded.sampleRate, 44100);
    expect(decoded.channels, 2);

    var received = 0;
    final end = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(end)) {
      final remaining = end.difference(DateTime.now());
      final chunk = await decoder
          .nextChunk()
          .timeout(remaining, onTimeout: () => null);
      if (chunk == null) break;
      received += chunk.length;
      if (received > 44100 * 2 * 2) break; // > 1 second of stereo PCM
    }

    expect(received, greaterThan(44100 * 2 * 2),
        reason: 'at least 1 second of PCM must stream');

    await decoder.stop();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
