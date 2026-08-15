// Verifies the FFmpeg bridge decodes a real Bilibili DASH audio stream to PCM.
// Run: flutter test test/ffmpeg_bridge_test.dart
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_hub/services/ffmpeg/ffmpeg_bridge.dart';
import 'package:asmr_hub/sources/bilibili/bilibili_api.dart';

void main() {
  test('bridge decodes bilibili DASH audio to PCM', () async {
    final api = BilibiliApi();
    final info = await api.fetchVideoInfo('BV1GJ411x7h7');
    final url = await api.fetchAudioUrl(info.bvid, info.cid);
    stdout.writeln('URL: ${url.substring(0, 80)}...');

    final bridge = FfmpegBridge.instance;
    expect(bridge, isNotNull, reason: 'bridge must be available in tests');
    if (bridge == null) return;
    final handle = bridge.open(
      url,
      headers: 'Referer: https://www.bilibili.com/\r\n'
          'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 '
          'Safari/537.36',
    );
    expect(handle, isNotNull, reason: 'bridge_open must succeed');
    if (handle == null) return;

    final sampleRate = bridge.getSampleRate(handle);
    final channels = bridge.getChannels(handle);
    stdout.writeln('SAMPLE_RATE: $sampleRate CHANNELS: $channels');
    expect(sampleRate, greaterThan(0));
    expect(channels, greaterThan(0));

    // Read ~2 seconds of PCM (48k stereo s16 = 192000 bytes/s).
    final capacity = sampleRate * channels * 2 * 2;
    final buffer = calloc<Uint8>(capacity);
    var total = 0;
    final stopwatch = Stopwatch()..start();
    while (total < capacity && stopwatch.elapsedMilliseconds < 30000) {
      final n = bridge.readPcm(
        handle,
        buffer + total,
        capacity - total,
      );
      if (n <= 0) {
        stdout.writeln('READ END: $n err=${bridge.lastError(handle)}');
        break;
      }
      total += n;
    }
    stopwatch.stop();
    calloc.free(buffer);

    stdout.writeln('PCM READ: $total bytes in ${stopwatch.elapsedMilliseconds}ms');
    expect(total, greaterThan(sampleRate * channels * 2),
        reason: 'at least 1 second of PCM must decode');
    bridge.close(handle);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
