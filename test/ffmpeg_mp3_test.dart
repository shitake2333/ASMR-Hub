// Verify the MP3 sidecar encoder: decoding with mp3Bitrate produces valid
// MP3 bytes that ffprobe recognizes, with sensible size vs the WAV.
// Run: flutter test test/ffmpeg_mp3_test.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_hub/services/ffmpeg/ffmpeg_audio_decoder.dart';

List<int> _u32le(int v) => [
  v & 0xFF,
  (v >> 8) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 24) & 0xFF,
];

void main() {
  test('decoder produces valid MP3 while streaming PCM', () async {
    // Build a 6s 440Hz tone WAV (44100 Hz stereo s16).
    const sr = 44100;
    final pcm = sr * 2 * 2 * 6; // bytes for 6s stereo s16
    final w = BytesBuilder();
    w.add('RIFF'.codeUnits);
    w.add(_u32le(36 + pcm));
    w.add('WAVE'.codeUnits);
    w.add('fmt '.codeUnits);
    w.add(_u32le(16));
    w.add([1, 0]);
    w.add([2, 0]);
    w.add(_u32le(sr));
    w.add(_u32le(sr * 4));
    w.add([4, 0]);
    w.add([16, 0]);
    w.add('data'.codeUnits);
    w.add(_u32le(pcm));
    for (var i = 0; i < pcm ~/ 2; i++) {
      final v = (32767 * 0.3 * sin(i * 2 * 3.14159 * 440 / sr)).round();
      w.add([v & 0xFF, (v >> 8) & 0xFF]);
    }
    final src = File('${Directory.systemTemp.path}/mp3_src.wav');
    src.writeAsBytesSync(w.takeBytes());

    final decoder = FfmpegAudioDecoder();
    final info = await decoder.start(src.path, mp3Bitrate: 192000);
    expect(info, isNotNull, reason: 'must open');
    stdout.writeln(
      'opened: ${info!.sampleRate}Hz ${info.channels}ch '
      'duration=${info.duration.inSeconds}s',
    );
    expect(
      info.duration.inSeconds,
      greaterThanOrEqualTo(5),
      reason: 'duration must be known up-front',
    );

    // Pull all PCM and all MP3 output.
    final mp3Out = BytesBuilder();
    var pcmBytes = 0;
    while (true) {
      final chunk = await decoder.nextChunk().timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
      if (chunk == null) break;
      pcmBytes += chunk.length;
      while (true) {
        final enc = await decoder.takeEncoded().timeout(
          const Duration(seconds: 10),
          onTimeout: () => null,
        );
        if (enc == null || enc.isEmpty) break;
        mp3Out.add(enc);
      }
    }
    // Drain remaining encoded bytes after EOF.
    while (true) {
      final enc = await decoder.takeEncoded().timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
      if (enc == null || enc.isEmpty) break;
      mp3Out.add(enc);
    }
    await decoder.stop();

    final mp3 = mp3Out.takeBytes();
    stdout.writeln(
      'pcm=$pcmBytes bytes, mp3=${mp3.length} bytes '
      '(ratio=${(mp3.length * 100 / pcmBytes).toStringAsFixed(1)}%)',
    );
    expect(
      pcmBytes,
      greaterThan(44100 * 2 * 2 * 5),
      reason: 'must decode all 6s of PCM',
    );
    expect(mp3.length, greaterThan(1024), reason: 'must produce MP3 data');
    expect(
      mp3.length,
      lessThan(pcmBytes ~/ 5),
      reason: 'MP3 must be much smaller than PCM (~192kbps)',
    );

    // Write and validate with ffprobe if available.
    final out = File('${Directory.systemTemp.path}/mp3_out.mp3');
    out.writeAsBytesSync(mp3);
    final ffprobe = File(
      r'C:\Users\86139\scoop\apps\ffmpeg\current\bin\ffprobe.exe',
    );
    if (ffprobe.existsSync()) {
      final res = await Process.run(ffprobe.path, [
        '-v',
        'error',
        '-show_entries',
        'format=duration',
        '-of',
        'default=noprint_wrappers=1:nokey=1',
        out.path,
      ]);
      stdout.writeln('ffprobe: ${res.stdout.toString().trim()}');
      expect(res.exitCode, 0, reason: 'ffprobe must accept the MP3');
      final dur = double.tryParse(res.stdout.toString().trim());
      expect(dur, isNotNull);
      expect(dur!, greaterThan(5.0), reason: 'mp3 duration ~6s');
      expect(dur, lessThan(8.0));
    } else {
      stdout.writeln('SKIP ffprobe check (not found)');
    }

    try {
      src.deleteSync();
      out.deleteSync();
    } catch (_) {}
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('decoder seek jumps to the requested position', () async {
    // Build a 10s 440Hz tone WAV.
    const sr = 44100;
    final pcm = sr * 2 * 2 * 10;
    final w = BytesBuilder();
    w.add('RIFF'.codeUnits);
    w.add(_u32le(36 + pcm));
    w.add('WAVE'.codeUnits);
    w.add('fmt '.codeUnits);
    w.add(_u32le(16));
    w.add([1, 0]);
    w.add([2, 0]);
    w.add(_u32le(sr));
    w.add(_u32le(sr * 4));
    w.add([4, 0]);
    w.add([16, 0]);
    w.add('data'.codeUnits);
    w.add(_u32le(pcm));
    for (var i = 0; i < pcm ~/ 2; i++) {
      final v = (32767 * 0.3 * sin(i * 2 * 3.14159 * 440 / sr)).round();
      w.add([v & 0xFF, (v >> 8) & 0xFF]);
    }
    final src = File('${Directory.systemTemp.path}/seek_src.wav');
    src.writeAsBytesSync(w.takeBytes());

    final decoder = FfmpegAudioDecoder();
    final info = await decoder.start(src.path);
    expect(info, isNotNull);
    expect(info!.duration.inSeconds, greaterThanOrEqualTo(9));

    // Consume ~2s, then seek to 6s.
    var before = 0;
    while (before < sr * 2 * 2 * 2) {
      final chunk = await decoder.nextChunk().timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
      if (chunk == null) break;
      before += chunk.length;
    }
    expect(before, greaterThan(0), reason: 'must stream before seek');

    final ok = await decoder.seek(6.0);
    expect(ok, isTrue, reason: 'seek must succeed');

    // After seek to 6s of a 10s file, ~4s remain.
    var after = 0;
    while (true) {
      final chunk = await decoder.nextChunk().timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
      if (chunk == null) break;
      after += chunk.length;
    }
    stdout.writeln('before=$before after=$after');
    expect(
      after,
      greaterThan(sr * 2 * 2 * 3),
      reason: 'must decode >3s after seeking to 6s of 10s',
    );
    expect(
      after,
      lessThan(sr * 2 * 2 * 5),
      reason: 'must not decode the full 10s after seeking',
    );

    await decoder.stop();
    try {
      src.deleteSync();
    } catch (_) {}
  }, timeout: const Timeout(Duration(minutes: 2)));
}
