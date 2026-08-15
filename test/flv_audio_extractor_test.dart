// Tests for the streaming FLV audio extractor using a real sample captured
// from a Douyu live stream.
// Run: flutter test test/flv_audio_extractor_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_hub/services/flv_audio_extractor.dart';

void main() {
  final fixture = File('test/fixtures/douyu_sample.flv');
  final bytes = fixture.readAsBytesSync();

  test('extracts audio from real FLV data', () {
    expect(
      String.fromCharCodes(bytes.sublist(0, 3)),
      'FLV',
      reason: 'fixture must be FLV',
    );
    final extractor = FlvAudioExtractor();

    // Feed the data in small chunks to exercise boundary handling.
    const chunkSize = 1024;
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize) < bytes.length ? i + chunkSize : bytes.length;
      extractor.addChunk(bytes.sublist(i, end));
    }

    expect(extractor.isFlv, isTrue);
    expect(extractor.isInvalid, isFalse);
    expect(extractor.audioChunks, isNotEmpty);

    // Audio tags must be MP3 or AAC.
    for (final chunk in extractor.audioChunks) {
      expect(
        chunk.soundFormat == FlvAudioExtractor.soundFormatMp3 ||
            chunk.soundFormat == FlvAudioExtractor.soundFormatAac,
        isTrue,
        reason: 'unexpected sound format ${chunk.soundFormat}',
      );
      expect(chunk.data.length, greaterThan(0));
    }
  });

  test('handles byte-at-a-time feeding', () {
    final extractor = FlvAudioExtractor();
    for (final b in bytes) {
      extractor.addChunk([b]);
    }
    expect(extractor.isFlv, isTrue);
    expect(extractor.audioChunks, isNotEmpty);
    final audioBytes = extractor.audioChunks.fold<int>(
      0,
      (sum, c) => sum + c.data.length,
    );
    expect(audioBytes, greaterThan(1000));
  });

  test('rejects non-FLV input', () {
    final extractor = FlvAudioExtractor();
    extractor.addChunk(
      List<int>.generate(64, (i) => i), // garbage
    );
    expect(extractor.isInvalid, isTrue);
    expect(extractor.audioChunks, isEmpty);
  });
}
