// Verify HLS live recording: LiveRecorder.startHls decodes an HLS m3u8
// (local fixture) and writes a valid MP3.
// Run: flutter test test/live_recorder_hls_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_hub/services/live_recorder.dart';

void main() {
  test('startHls records an HLS stream to MP3', () async {
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

    final out = File('${Directory.systemTemp.path}/hls_rec_test.mp3');
    final recorder = LiveRecorder();
    final ok = await recorder.startHls(
      'http://127.0.0.1:${server.port}/test.m3u8',
      out.path,
      key: 'test:hls',
    );
    expect(ok, isTrue, reason: 'HLS recording must start');
    expect(recorder.isRecording, isTrue);

    // The fixture is ~6s; wait for it to be fully recorded (EOF stops it).
    var waited = 0;
    while (recorder.isRecording && waited < 20) {
      await Future<void>.delayed(const Duration(seconds: 1));
      waited++;
    }
    if (recorder.isRecording) {
      await recorder.stop();
    }

    expect(out.existsSync(), isTrue);
    final size = await out.length();
    stdout.writeln('recorded $size bytes in ${waited}s');
    expect(size, greaterThan(1024), reason: 'must contain real MP3 data');

    // Validate with ffprobe if available.
    final ffprobe = File(
      r'C:\Users\86139\scoop\apps\ffmpeg\current\bin\ffprobe.exe',
    );
    if (ffprobe.existsSync()) {
      final res = await Process.run(ffprobe.path, [
        '-v', 'error',
        '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1',
        out.path,
      ]);
      stdout.writeln('ffprobe duration: ${res.stdout.toString().trim()}');
      expect(res.exitCode, 0, reason: 'ffprobe must accept the MP3');
      final dur = double.tryParse(res.stdout.toString().trim());
      expect(dur, isNotNull);
      expect(dur!, greaterThan(4.0), reason: '~6s HLS fixture');
      expect(dur, lessThan(9.0));
    } else {
      stdout.writeln('SKIP ffprobe check (not found)');
    }

    await server.close(force: true);
    try {
      out.deleteSync();
    } catch (_) {}
  }, timeout: const Timeout(Duration(minutes: 2)));
}
