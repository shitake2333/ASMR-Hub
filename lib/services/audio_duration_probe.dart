import 'dart:io';
import 'dart:typed_data';

/// Lightweight audio duration probing by parsing file headers.
///
/// Supports WAV, FLAC, MP3 (ID3v2/Xing/CBR estimate) and MP4/M4A (mvhd).
/// Returns [Duration.zero] when the duration cannot be determined.
class AudioDurationProbe {
  /// Probes the duration of a local audio file.
  static Future<Duration> probeFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return Duration.zero;
      final lower = path.toLowerCase();

      if (lower.endsWith('.wav') || lower.endsWith('.wave')) {
        return _probeWav(await _read(file, 1024));
      }
      if (lower.endsWith('.flac')) {
        return await _probeFlac(file);
      }
      if (lower.endsWith('.mp3') || lower.endsWith('.mp2')) {
        return await _probeMp3(file);
      }
      if (lower.endsWith('.m4a') ||
          lower.endsWith('.m4b') ||
          lower.endsWith('.mp4') ||
          lower.endsWith('.aac') ||
          lower.endsWith('.mka')) {
        final size = await file.length();
        // AAC ADTS streams have no container header; estimate from frames.
        if (lower.endsWith('.aac')) {
          return await _probeAacAdts(file);
        }
        return await _probeMp4(file, size);
      }
    } catch (e) {
      // Fall through
    }
    return Duration.zero;
  }

  static Future<Uint8List> _read(File file, int maxBytes) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      final n = length < maxBytes ? length : maxBytes;
      return await raf.read(n);
    } finally {
      await raf.close();
    }
  }

  // ---------------------------------------------------------------- WAV

  static Duration _probeWav(Uint8List header) {
    if (header.length < 44 ||
        String.fromCharCodes(header.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(header.sublist(8, 12)) != 'WAVE') {
      return Duration.zero;
    }
    var offset = 12;
    int? sampleRate;
    int? channels;
    int? bitsPerSample;
    int? dataSize;
    while (offset + 8 <= header.length) {
      final chunkId = String.fromCharCodes(header.sublist(offset, offset + 4));
      final chunkSize = _u32le(header, offset + 4);
      if (chunkId == 'fmt ' &&
          chunkSize >= 16 &&
          offset + 24 <= header.length) {
        sampleRate = _u32le(header, offset + 12);
        channels = _u16le(header, offset + 10);
        bitsPerSample = _u16le(header, offset + 22);
      } else if (chunkId == 'data') {
        dataSize = chunkSize;
        break;
      }
      offset += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }
    if (sampleRate == null ||
        channels == null ||
        bitsPerSample == null ||
        dataSize == null ||
        sampleRate == 0) {
      return Duration.zero;
    }
    final bytesPerSecond = sampleRate * channels * (bitsPerSample ~/ 8);
    if (bytesPerSecond == 0) return Duration.zero;
    return Duration(milliseconds: (dataSize * 1000 / bytesPerSecond).round());
  }

  // --------------------------------------------------------------- FLAC

  static Future<Duration> _probeFlac(File file) async {
    final header = await _read(file, 512);
    // 'fLaC' marker + metadata blocks; STREAMINFO is the first block.
    if (header.length < 4 ||
        String.fromCharCodes(header.sublist(0, 4)) != 'fLaC') {
      return Duration.zero;
    }
    var offset = 4;
    var isLast = false;
    while (!isLast && offset + 4 <= header.length) {
      final headerByte = header[offset];
      isLast = (headerByte & 0x80) != 0;
      final blockType = headerByte & 0x7F;
      final blockSize = _u24(header, offset + 1);
      offset += 4;
      if (offset + blockSize > header.length) return Duration.zero;
      if (blockType == 0 && blockSize >= 34) {
        // STREAMINFO: sample rate (20 bits), total samples (36 bits)
        final sampleRate =
            ((header[offset + 10] & 0x0F) << 12) |
            (header[offset + 11] << 4) |
            ((header[offset + 12] >> 4) & 0x0F);
        final totalSamples =
            (BigInt.from(header[offset + 13] & 0x0F) << 32) |
            (BigInt.from(header[offset + 14]) << 24) |
            (BigInt.from(header[offset + 15]) << 16) |
            (BigInt.from(header[offset + 16]) << 8) |
            BigInt.from(header[offset + 17]);
        if (sampleRate == 0 || totalSamples == BigInt.zero) {
          return Duration.zero;
        }
        return Duration(
          milliseconds:
              (totalSamples * BigInt.from(1000) ~/ BigInt.from(sampleRate))
                  .toInt(),
        );
      }
      offset += blockSize;
    }
    return Duration.zero;
  }

  // ---------------------------------------------------------------- MP3

  static Future<Duration> _probeMp3(File file) async {
    final raf = await file.open();
    try {
      final fileSize = await raf.length();
      if (fileSize < 4) return Duration.zero;

      // Skip ID3v2 tag.
      final head = await raf.read(10);
      var offset = 0;
      if (head.length >= 10 &&
          String.fromCharCodes(head.sublist(0, 3)) == 'ID3') {
        final tagSize =
            ((head[6] & 0x7F) << 21) |
            ((head[7] & 0x7F) << 14) |
            ((head[8] & 0x7F) << 7) |
            (head[9] & 0x7F);
        offset = 10 + tagSize;
      }

      // Find the first frame header.
      var frameHeader = Uint8List(0);
      var searchOffset = offset;
      while (searchOffset < fileSize - 4 && searchOffset < offset + 64 * 1024) {
        await raf.setPosition(searchOffset);
        final bytes = await raf.read(4);
        if (bytes.length == 4 && _isMp3FrameSync(bytes)) {
          frameHeader = bytes;
          offset = searchOffset;
          break;
        }
        searchOffset++;
      }
      if (frameHeader.length != 4) return Duration.zero;

      final version = (frameHeader[1] >> 3) & 0x03; // 0=MPEG2.5 2=MPEG2 3=MPEG1
      final layer = (frameHeader[1] >> 1) & 0x03;
      final bitrateIndex = (frameHeader[2] >> 4) & 0x0F;
      final sampleRateIndex = (frameHeader[2] >> 2) & 0x03;
      if (version == 1 ||
          layer != 1 ||
          bitrateIndex == 0 ||
          bitrateIndex == 15 ||
          sampleRateIndex == 3) {
        return Duration.zero;
      }

      final sampleRate = _mp3SampleRate(version, sampleRateIndex);
      final bitrateKbps = _mp3Bitrate(version, layer, bitrateIndex);
      if (sampleRate == 0 || bitrateKbps == 0) return Duration.zero;

      // Try to find a Xing/Info header for VBR frame counts.
      final frameHeaderPos = offset;
      await raf.setPosition(offset + 4);
      final sideInfo = await raf.read(40);
      final xingOffset = _findXing(sideInfo, version);
      if (xingOffset != null) {
        await raf.setPosition(offset + 4 + xingOffset);
        final xing = await raf.read(8);
        if (xing.length == 8 && (xing[0] & 0x01) != 0) {
          final frames =
              ((xing[4] & 0xFF) << 24) |
              ((xing[5] & 0xFF) << 16) |
              ((xing[6] & 0xFF) << 8) |
              (xing[7] & 0xFF);
          if (frames > 0) {
            final ms = (frames * 1152 * 1000) ~/ sampleRate;
            return Duration(milliseconds: ms);
          }
        }
      }

      // CBR estimate from file size (audio data after ID3 tag).
      final audioBytes = fileSize - frameHeaderPos;
      final seconds = audioBytes * 8 / (bitrateKbps * 1000);
      return Duration(milliseconds: (seconds * 1000).round());
    } finally {
      await raf.close();
    }
  }

  static bool _isMp3FrameSync(Uint8List b) {
    return b.length == 4 && b[0] == 0xFF && (b[1] & 0xE0) == 0xE0;
  }

  static int _mp3SampleRate(int version, int index) {
    const rates = [
      [11025, 12000, 8000, 0], // MPEG 2.5
      [0, 0, 0, 0],
      [22050, 24000, 16000, 0], // MPEG 2
      [44100, 48000, 32000, 0], // MPEG 1
    ];
    return rates[version][index];
  }

  static int _mp3Bitrate(int version, int layer, int index) {
    // Layer III only (layer == 1).
    const v1 = [
      0,
      32,
      40,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      160,
      192,
      224,
      256,
      320,
      0,
    ];
    const v2 = [
      0,
      8,
      16,
      24,
      32,
      40,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      144,
      160,
      0,
    ];
    return version == 3 ? v1[index] : v2[index];
  }

  /// Offset of the Xing/Info tag within the side info, or null.
  static int? _findXing(Uint8List sideInfo, int version) {
    final mpeg1 = version == 3;
    final offset = mpeg1 ? 36 : 21;
    if (sideInfo.length < offset + 4) return null;
    for (var i = 0; i < 4 && offset + i + 4 <= sideInfo.length; i++) {
      final tag = String.fromCharCodes(
        sideInfo.sublist(offset + i, offset + i + 4),
      );
      if (tag == 'Xing' || tag == 'Info') return i;
    }
    return null;
  }

  // ---------------------------------------------------------------- AAC

  /// AAC ADTS: duration from frame count estimate (frame duration 1024
  /// samples for AAC-LC).
  static Future<Duration> _probeAacAdts(File file) async {
    final raf = await file.open();
    try {
      final fileSize = await raf.length();
      if (fileSize < 7) return Duration.zero;
      final head = await raf.read(7);
      if (head.length < 7 || head[0] != 0xFF || (head[1] & 0xF0) != 0xF0) {
        return Duration.zero;
      }
      final sampleRateIndex = (head[2] >> 2) & 0x0F;
      final sampleRate = _aacSampleRate(sampleRateIndex);
      if (sampleRate == 0) return Duration.zero;
      // Average frame size estimate from the first frames.
      var totalFrames = 0;
      var totalBytes = 0;
      var offset = 0;
      while (offset + 7 <= fileSize && totalFrames < 50) {
        await raf.setPosition(offset);
        final b = await raf.read(7);
        if (b.length < 7 || b[0] != 0xFF || (b[1] & 0xF0) != 0xF0) break;
        final frameLength =
            ((b[3] & 0x03) << 11) | (b[4] << 3) | ((b[5] >> 5) & 0x07);
        if (frameLength < 7) break;
        offset += frameLength;
        totalFrames++;
        totalBytes += frameLength;
      }
      if (totalFrames == 0) return Duration.zero;
      final avgFrameSize = totalBytes / totalFrames;
      final estimatedFrames = fileSize / avgFrameSize;
      final ms = (estimatedFrames * 1024 * 1000 / sampleRate).round();
      return Duration(milliseconds: ms);
    } finally {
      await raf.close();
    }
  }

  static int _aacSampleRate(int index) {
    const rates = [
      96000,
      88200,
      64000,
      48000,
      44100,
      32000,
      24000,
      22050,
      16000,
      12000,
      11025,
      8000,
      7350,
      0,
      0,
      0,
    ];
    return index < rates.length ? rates[index] : 0;
  }

  // ---------------------------------------------------------------- MP4

  static Future<Duration> _probeMp4(File file, int fileSize) async {
    final raf = await file.open();
    try {
      // Walk top-level boxes looking for moov.
      var offset = 0;
      while (offset + 8 <= fileSize) {
        await raf.setPosition(offset);
        final header = await raf.read(8);
        if (header.length < 8) return Duration.zero;
        var boxSize = _u32(header, 0);
        final boxType = String.fromCharCodes(header.sublist(4, 8));
        if (boxSize == 1) {
          final large = await raf.read(8);
          if (large.length < 8) return Duration.zero;
          boxSize = (_u32(large, 0) << 32) | _u32(large, 4);
          offset += 8;
        }
        if (boxSize < 8) return Duration.zero;
        if (boxType == 'moov') {
          return await _probeMoov(
            raf,
            offset + (boxSize == 1 ? 16 : 8),
            boxSize,
          );
        }
        offset += boxSize;
      }
      return Duration.zero;
    } finally {
      await raf.close();
    }
  }

  static Future<Duration> _probeMoov(
    RandomAccessFile raf,
    int start,
    int moovSize,
  ) async {
    // mvhd: version 0 -> timescale@12, duration@16 (version 1 -> 64-bit).
    final end = start + moovSize;
    var offset = start;
    while (offset + 8 <= end) {
      await raf.setPosition(offset);
      final header = await raf.read(8);
      if (header.length < 8) return Duration.zero;
      final boxSize = _u32(header, 0);
      final boxType = String.fromCharCodes(header.sublist(4, 8));
      if (boxSize < 8) return Duration.zero;
      if (boxType == 'mvhd' && boxSize >= 32) {
        await raf.setPosition(offset + 8);
        final payload = await raf.read(boxSize - 8 < 64 ? boxSize - 8 : 64);
        if (payload.length < 20) return Duration.zero;
        final version = payload[0];
        if (version == 1) {
          final timescale = _u32(payload, 20);
          if (timescale == 0) return Duration.zero;
          final durationMs =
              (_u64(payload, 24) * BigInt.from(1000) ~/ BigInt.from(timescale))
                  .toInt();
          return Duration(milliseconds: durationMs);
        } else {
          final timescale = _u32(payload, 12);
          final duration = _u32(payload, 16);
          if (timescale == 0) return Duration.zero;
          return Duration(milliseconds: (duration * 1000) ~/ timescale);
        }
      }
      offset += boxSize;
    }
    return Duration.zero;
  }

  // ------------------------------------------------------------- helpers

  static int _u16le(Uint8List b, int o) => (b[o + 1] << 8) | b[o];

  static int _u24(Uint8List b, int o) =>
      (b[o] << 16) | (b[o + 1] << 8) | b[o + 2];

  static int _u32le(Uint8List b, int o) =>
      (b[o] & 0xFF) |
      ((b[o + 1] & 0xFF) << 8) |
      ((b[o + 2] & 0xFF) << 16) |
      ((b[o + 3] & 0xFF) << 24);

  static int _u32(Uint8List b, int o) =>
      ((b[o] & 0xFF) << 24) |
      ((b[o + 1] & 0xFF) << 16) |
      ((b[o + 2] & 0xFF) << 8) |
      (b[o + 3] & 0xFF);

  static BigInt _u64(Uint8List b, int o) =>
      (BigInt.from(_u32(b, o)) << 32) | BigInt.from(_u32(b, o + 4));
}
