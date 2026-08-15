// HLS (m3u8) decoding verification against a local HLS stream.
// Requires test_hls to be served; the server is started here.
// Run: flutter test test/ffmpeg_hls_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_hub/services/ffmpeg/ffmpeg_audio_decoder.dart';

void main() {
  test('decodes an HLS m3u8 stream', () async {
    // Serve the generated HLS directory over HTTP.
    final hlsDir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}test_hls',
    );
    expect(hlsDir.existsSync(), isTrue, reason: 'generate test_hls first');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      final file = File('${hlsDir.path}${request.uri.path}');
      if (file.existsSync()) {
        request.response.headers.contentType = request.uri.path.endsWith('.m3u8')
            ? ContentType('application', 'vnd.apple.mpegurl')
            : ContentType('video', 'mp2t');
        request.response.add(file.readAsBytesSync());
      } else {
        request.response.statusCode = 404;
      }
      request.response.close();
    });

    final decoder = FfmpegAudioDecoder();
    final decoded = await decoder.start('http://127.0.0.1:${server.port}/test.m3u8');
    expect(decoded, isNotNull, reason: 'HLS must open');

    var received = 0;
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(end)) {
      final remaining = end.difference(DateTime.now());
      final chunk = await decoder
          .nextChunk()
          .timeout(remaining, onTimeout: () => null);
      if (chunk == null) break;
      received += chunk.length;
      if (received > 44100 * 2 * 2) break;
    }

    expect(received, greaterThan(44100 * 2 * 2),
        reason: 'HLS must decode to PCM (440Hz tone is ~6s)');
    await decoder.stop();
    await server.close(force: true);
  }, timeout: const Timeout(Duration(minutes: 1)));
}
