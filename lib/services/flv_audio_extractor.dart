import 'dart:typed_data';

/// FLV audio extraction result.
class FlvAudioChunk {
  /// Sound format: 2 = MP3, 10 = AAC (raw AAC frames; no ADTS header).
  final int soundFormat;

  /// Audio payload (MP3 frames for format 2; raw AAC for format 10).
  final Uint8List data;

  const FlvAudioChunk(this.soundFormat, this.data);
}

/// Streaming FLV demuxer that extracts audio tags.
///
/// Feeds raw bytes incrementally via [addChunk] and collects audio payloads
/// via [audioChunks]. Video tags are skipped. Tag boundaries that span chunk
/// boundaries are handled by an internal buffer.
class FlvAudioExtractor {
  static const int _headerSize = 9;
  static const int _tagHeaderSize = 11;
  static const int _prevTagSize = 4;

  static const int _tagAudio = 8;

  /// Sound format constants (FLV SoundFormat field).
  static const int soundFormatMp3 = 2;
  static const int soundFormatAac = 10;

  final BytesBuilder _buf = BytesBuilder(copy: false);
  bool _headerParsed = false;
  bool _isFlv = false;

  int _expectedTagSize = 0;
  int _tagType = 0;
  bool _inTag = false;
  bool _audioInfoRead = false;
  int _audioFormat = 0;
  int _audioPayloadLeft = 0;
  final BytesBuilder _audioPayload = BytesBuilder(copy: false);

  final List<FlvAudioChunk> audioChunks = [];

  /// True once the FLV signature has been confirmed.
  bool get isFlv => _isFlv;

  /// True if the stream is (definitely) not FLV.
  bool get isInvalid => _headerParsed && !_isFlv;

  void addChunk(List<int> chunk) {
    _buf.add(chunk);
    _process();
  }

  void _process() {
    while (true) {
      if (!_headerParsed) {
        final bytes = _buf.takeBytes();
        if (bytes.length < _headerSize + _prevTagSize) {
          _buf.add(bytes);
          return;
        }
        _headerParsed = true;
        _isFlv =
            bytes.length >= 3 &&
            bytes[0] == 0x46 && // 'F'
            bytes[1] == 0x4C && // 'L'
            bytes[2] == 0x56; // 'V'
        // Skip header + first prevTagSize (13 bytes total handled above).
        final rest = bytes.sublist(_headerSize + _prevTagSize);
        if (rest.isNotEmpty) _buf.add(rest);
        if (!_isFlv) return;
        continue;
      }

      if (!_inTag) {
        final bytes = _buf.takeBytes();
        if (bytes.length < _tagHeaderSize) {
          _buf.add(bytes);
          return;
        }
        _tagType = bytes[0];
        _expectedTagSize = (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
        _inTag = true;
        _audioInfoRead = false;
        _audioPayloadLeft = 0;
        _audioPayload.clear();
        final rest = bytes.sublist(_tagHeaderSize);
        if (rest.isNotEmpty) _buf.add(rest);
        continue;
      }

      // Inside a tag.
      if (_tagType == _tagAudio) {
        if (!_audioInfoRead) {
          final bytes = _buf.takeBytes();
          if (bytes.isEmpty) return;
          _audioInfoRead = true;
          _audioFormat = (bytes[0] >> 4) & 0x0F;
          _audioPayloadLeft = _expectedTagSize - 1;
          final rest = bytes.sublist(1);
          if (rest.isNotEmpty) _buf.add(rest);
          continue;
        }

        if (_audioPayloadLeft > 0) {
          final bytes = _buf.takeBytes();
          if (bytes.isEmpty) return;
          final take = bytes.length < _audioPayloadLeft
              ? bytes.length
              : _audioPayloadLeft;
          _audioPayload.add(bytes.sublist(0, take));
          _audioPayloadLeft -= take;
          if (take < bytes.length) {
            _buf.add(bytes.sublist(take));
          }
          if (_audioPayloadLeft == 0) {
            final payload = _audioPayload.takeBytes();
            if (_audioFormat == soundFormatMp3 ||
                _audioFormat == soundFormatAac) {
              audioChunks.add(
                FlvAudioChunk(_audioFormat, Uint8List.fromList(payload)),
              );
            }
            if (!_finishTag()) return;
          }
          continue;
        }
        if (!_finishTag()) return;
        continue;
      }

      // Skip video / script / other tag payload.
      final bytes = _buf.takeBytes();
      if (bytes.isEmpty) return;
      if (bytes.length <= _expectedTagSize) {
        _expectedTagSize -= bytes.length;
        if (_expectedTagSize == 0) {
          if (!_finishTag()) return;
        }
      } else {
        // Consume only what the tag needs; return the excess bytes.
        _buf.add(bytes.sublist(_expectedTagSize));
        _expectedTagSize = 0;
        if (!_finishTag()) return;
      }
    }
  }

  /// Consume the 4-byte previous-tag-size field. Returns false when more
  /// data is needed; the caller must stop processing until more arrives.
  bool _finishTag() {
    final bytes = _buf.takeBytes();
    if (bytes.length < _prevTagSize) {
      _buf.add(bytes);
      return false;
    }
    final rest = bytes.sublist(_prevTagSize);
    if (rest.isNotEmpty) _buf.add(rest);
    _inTag = false;
    return true;
  }
}
