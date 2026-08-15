import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_hub/services/ffmpeg/ffmpeg_audio_decoder.dart';

/// Verifies FLAC encoding via the FFmpeg bridge: decoding a local MP3 and
/// re-encoding to FLAC produces a valid FLAC stream (fLaC magic + frames).
void main() {
  test('ffmpeg decoder re-encodes MP3 to valid FLAC', () async {
    // Find a local MP3.
    final dir = Directory(r'D:\data\asmr_hub\bilibili');
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.mp3'))
        .take(1)
        .toList();
    expect(files, isNotEmpty, reason: 'need a local MP3');
    final source = files.first.path;

    final decoder = FfmpegAudioDecoder();
    final info = await decoder.start(
      source,
      codec: 2, // FLAC
    );
    expect(info, isNotNull);

    // Drain the decoder: pull PCM chunks to drive encoding, collect bytes.
    final encoded = BytesBuilder();
    for (var i = 0; i < 50; i++) {
      final chunk = await decoder.nextChunk();
      if (chunk == null || chunk.isEmpty) break;
      while (true) {
        final enc = await decoder.takeEncoded();
        if (enc == null || enc.isEmpty) break;
        encoded.add(enc);
      }
    }
    for (var i = 0; i < 20; i++) {
      final enc = await decoder.takeEncoded();
      if (enc == null || enc.isEmpty) break;
      encoded.add(enc);
    }
    await decoder.stop();

    final bytes = encoded.toBytes();
    // ignore: avoid_print
    print('FLAC bytes produced: ${bytes.length}');
    expect(bytes.length, greaterThan(100), reason: 'must produce FLAC data');

    // FLAC stream starts with "fLaC" magic.
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'fLaC',
        reason: 'must start with fLaC marker');

    // Write to a temp file and verify a standard decoder accepts it.
    final out = File('${Directory.systemTemp.path}/probe_enc.flac');
    await out.writeAsBytes(bytes);
    final result = await Process.run(
      'ffmpeg',
      ['-v', 'error', '-i', out.path, '-f', 'null', '-'],
    );
    // ignore: avoid_print
    print('ffmpeg decode check: exit=${result.exitCode} '
        'stderr=${result.stderr.toString().trim()}');
    expect(result.exitCode, 0,
        reason: 'ffmpeg must decode the produced FLAC: ${result.stderr}');
    await out.delete();
  });
}
