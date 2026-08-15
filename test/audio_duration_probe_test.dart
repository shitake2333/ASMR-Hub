// Tests for the audio duration probe using synthetic files.
// Run: flutter test test/audio_duration_probe_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_hub/services/audio_duration_probe.dart';

void main() {
  final dir = Directory.systemTemp.createTempSync('duration_probe_test');

  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('WAV duration from RIFF header', () async {
    // 5 seconds of 44100 Hz 16-bit mono = 441000 bytes of PCM.
    const sampleRate = 44100;
    const seconds = 5;
    final pcmSize = sampleRate * 2 * seconds;
    final wav = BytesBuilder();
    wav.add('RIFF'.codeUnits);
    wav.add(_u32le(36 + pcmSize));
    wav.add('WAVE'.codeUnits);
    wav.add('fmt '.codeUnits);
    wav.add(_u32le(16));
    wav.add(_u16le(1)); // PCM
    wav.add(_u16le(1)); // mono
    wav.add(_u32le(sampleRate));
    wav.add(_u32le(sampleRate * 2)); // byte rate
    wav.add(_u16le(2)); // block align
    wav.add(_u16le(16)); // bits
    wav.add('data'.codeUnits);
    wav.add(_u32le(pcmSize));
    wav.add(Uint8List(pcmSize)); // silent PCM

    final file = File('${dir.path}/test.wav');
    file.writeAsBytesSync(wav.takeBytes());

    final duration = await AudioDurationProbe.probeFile(file.path);
    expect(
      duration.inSeconds,
      seconds,
      reason: 'WAV duration should be ~$seconds seconds',
    );
  });

  test('MP3 CBR duration from frame estimate', () async {
    // Fake MP3: MPEG1 Layer III, 128 kbps, 44100 Hz (CBR).
    // Frame header: FF FB 90 00
    // 5 seconds at 128kbps = 80000 bytes.
    final mp3 = BytesBuilder();
    mp3.add([0xFF, 0xFB, 0x90, 0x00]);
    mp3.add(Uint8List(80000 - 4));

    final file = File('${dir.path}/test.mp3');
    file.writeAsBytesSync(mp3.takeBytes());

    final duration = await AudioDurationProbe.probeFile(file.path);
    expect(
      duration.inSeconds,
      inInclusiveRange(4, 6),
      reason: 'MP3 duration should be ~5 seconds',
    );
  });

  test('MP3 with ID3v2 tag is handled', () async {
    final mp3 = BytesBuilder();
    // ID3v2.3 header with 100-byte tag.
    mp3.add([0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x64]);
    mp3.add(Uint8List(100));
    mp3.add([0xFF, 0xFB, 0x90, 0x00]);
    mp3.add(Uint8List(80000 - 4));

    final file = File('${dir.path}/test_id3.mp3');
    file.writeAsBytesSync(mp3.takeBytes());

    final duration = await AudioDurationProbe.probeFile(file.path);
    expect(duration.inSeconds, inInclusiveRange(4, 6));
  });

  test('unknown format returns zero', () async {
    final file = File('${dir.path}/test.xyz');
    file.writeAsBytesSync(List.filled(100, 0));
    final duration = await AudioDurationProbe.probeFile(file.path);
    expect(duration, Duration.zero);
  });

  test('missing file returns zero', () async {
    final duration = await AudioDurationProbe.probeFile('${dir.path}/nope.wav');
    expect(duration, Duration.zero);
  });
}

List<int> _u16le(int v) => [v & 0xFF, (v >> 8) & 0xFF];

List<int> _u32le(int v) => [
  v & 0xFF,
  (v >> 8) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 24) & 0xFF,
];
