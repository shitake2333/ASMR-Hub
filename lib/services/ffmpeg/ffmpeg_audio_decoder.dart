import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:asmr_hub/services/ffmpeg/ffmpeg_bridge.dart';
import 'package:asmr_hub/services/log_service.dart';

/// Decoded audio stream parameters.
class DecodedAudioInfo {
  final int sampleRate;
  final int channels;
  final Duration duration;

  const DecodedAudioInfo({
    required this.sampleRate,
    required this.channels,
    this.duration = Duration.zero,
  });
}

/// FFmpeg-based audio decoder.
///
/// Two usage modes:
///
/// 1. **Pull mode** (live streams): [start] spawns an isolate that opens the
///    media and waits for commands; [nextChunk] pulls one PCM chunk at a time
///    so the caller can apply back-pressure.
///
/// 2. **File mode** (on-demand media): [decodeToFile] decodes the whole media
///    into a 16-bit PCM WAV file inside the background isolate. The caller
///    then plays the WAV (real duration, seeking, no buffer-overflow issues).
///
/// Output is interleaved s16le; the sample rate/channels are reported by the
/// bridge on open (currently resampled to 44100 Hz stereo).
class FfmpegAudioDecoder {
  final LogService _logger = LogService();

  Isolate? _isolate;
  SendPort? _commandPort;
  final ReceivePort _replyPort = ReceivePort();
  Completer<Uint8List?>? _pendingChunk;
  Completer<Uint8List?>? _pendingEncoded;
  Completer<bool>? _pendingSeek;
  Completer<DecodedAudioInfo?>? _readyCompleter;
  bool _started = false;
  bool _eof = false;
  bool _stopped = false;

  FfmpegAudioDecoder() {
    _replyPort.listen(_onReply);
  }

  void _onReply(Object? message) {
    if (message is _DecoderReady) {
      _commandPort = message.commandPort;
      _readyCompleter?.complete(
        DecodedAudioInfo(
          sampleRate: message.sampleRate,
          channels: message.channels,
          duration: Duration(
            milliseconds: (message.durationSeconds * 1000).round(),
          ),
        ),
      );
      _readyCompleter = null;
    } else if (message is _DecodeChunk) {
      final pending = _pendingChunk;
      _pendingChunk = null;
      pending?.complete(message.data);
    } else if (message is _DecodeEof) {
      _eof = true;
      final pending = _pendingChunk;
      _pendingChunk = null;
      pending?.complete(null);
    } else if (message is _DecodeError) {
      _logger.error('FFmpeg decode error: ${message.message}');
      _eof = true;
      final pending = _pendingChunk;
      _pendingChunk = null;
      pending?.complete(null);
    } else if (message is _EncodedChunk) {
      final pending = _pendingEncoded;
      _pendingEncoded = null;
      pending?.complete(message.data);
    } else if (message is _EncodedDone) {
      final pending = _pendingEncoded;
      _pendingEncoded = null;
      pending?.complete(null);
    } else if (message is _SeekOk) {
      final pending = _pendingSeek;
      _pendingSeek = null;
      pending?.complete(true);
    } else if (message is _SeekFail) {
      _logger.error('FFmpeg seek failed: ${message.message}');
      final pending = _pendingSeek;
      _pendingSeek = null;
      pending?.complete(false);
    }
  }

  /// Starts the pull-mode decode loop and returns the decoded audio
  /// parameters, or null if the media could not be opened.
  /// [mp3Bitrate] > 0 also encodes the decoded audio to MP3 (see
  /// [takeEncoded]). [codec] selects the encoder: 0 = none, 1 = MP3,
  /// 2 = FLAC (used for cache writing).
  Future<DecodedAudioInfo?> start(
    String url, {
    String? headers,
    String? userAgent,
    int mp3Bitrate = 0,
    int codec = 0,
  }) async {
    if (_started) return null;
    _started = true;
    _eof = false;
    _stopped = false;

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _decodeLoop,
        _IsolateArgs(
          url: url,
          headers: headers ?? '',
          userAgent: userAgent ?? '',
          mp3Bitrate: mp3Bitrate,
          codec: codec,
          replyPort: _replyPort.sendPort,
        ),
      );
    } catch (e) {
      _logger.error('FFmpeg isolate spawn failed', e);
      _started = false;
      return null;
    }
    _isolate = isolate;
    // Non-null capture for use inside the timeout/catch closures below.
    final spawned = isolate;

    final completer = Completer<DecodedAudioInfo?>();
    _readyCompleter = completer;
    try {
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _logger.error('FFmpeg bridge_open timed out: $url');
          // Kill the stuck isolate so the decoder can be retried.
          spawned.kill(priority: Isolate.immediate);
          _isolate = null;
          _commandPort = null;
          _started = false;
          return null;
        },
      );
    } catch (e) {
      _logger.error('FFmpeg decoder start failed', e);
      spawned.kill(priority: Isolate.immediate);
      _isolate = null;
      _commandPort = null;
      _started = false;
      return null;
    }
  }

  /// Pulls the next chunk of interleaved s16le PCM.
  /// Returns null at EOF or on error.
  Future<Uint8List?> nextChunk() async {
    if (_commandPort == null || _eof || _stopped) return null;
    final completer = Completer<Uint8List?>();
    _pendingChunk = completer;
    _commandPort!.send(_CmdNext());
    return completer.future;
  }

  /// Pulls the next chunk of encoded (MP3) bytes produced by the decoder.
  /// Returns null when encoding finished (all bytes consumed).
  Future<Uint8List?> takeEncoded() async {
    if (_commandPort == null || _stopped) return null;
    final completer = Completer<Uint8List?>();
    _pendingEncoded = completer;
    _commandPort!.send(_CmdTakeEncoded());
    return completer.future;
  }

  /// Seeks the input stream to [seconds]. Returns true on success.
  /// The encoder sidecar is reset; previously buffered encoded bytes are
  /// discarded, so a pending cache write must be invalidated by the caller.
  Future<bool> seek(double seconds) async {
    if (_commandPort == null || _stopped) return false;
    final completer = Completer<bool>();
    _pendingSeek = completer;
    _commandPort!.send(_CmdSeek(seconds));
    return completer.future;
  }

  /// Decodes [url] fully into a 16-bit PCM WAV file at [outputPath].
  /// Returns true on success.
  Future<bool> decodeToFile(
    String url,
    String outputPath, {
    String? headers,
    String? userAgent,
  }) async {
    final replyPort = ReceivePort();
    final isolate = await Isolate.spawn(
      _decodeToFileLoop,
      _FileArgs(
        url: url,
        headers: headers ?? '',
        userAgent: userAgent ?? '',
        outputPath: outputPath,
        replyPort: replyPort.sendPort,
      ),
    );
    try {
      final result = await replyPort.first.timeout(
        const Duration(minutes: 30),
        onTimeout: () => const _FileDone(false),
      );
      return result is _FileDone && result.ok;
    } finally {
      isolate.kill(priority: Isolate.immediate);
      replyPort.close();
    }
  }

  /// Stops decoding and releases the isolate.
  Future<void> stop() async {
    _stopped = true;
    _eof = true;
    final pending = _pendingChunk;
    _pendingChunk = null;
    pending?.complete(null);
    final pendingEnc = _pendingEncoded;
    _pendingEncoded = null;
    pendingEnc?.complete(null);
    final pendingSeek = _pendingSeek;
    _pendingSeek = null;
    pendingSeek?.complete(false);
    try {
      _commandPort?.send(_CmdStop());
    } catch (_) {}
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commandPort = null;
    _started = false;
  }

  void dispose() {
    _stopped = true;
    _eof = true;
    final pending = _pendingChunk;
    _pendingChunk = null;
    pending?.complete(null);
    final pendingEnc = _pendingEncoded;
    _pendingEncoded = null;
    pendingEnc?.complete(null);
    final pendingSeek = _pendingSeek;
    _pendingSeek = null;
    pendingSeek?.complete(false);
    try {
      _commandPort?.send(_CmdStop());
    } catch (_) {}
    _isolate?.kill(priority: Isolate.immediate);
    _replyPort.close();
  }

  bool get isRunning => _started && !_stopped;
}

// ---------------------------------------------------------------------------
// Isolate message protocol
// ---------------------------------------------------------------------------

class _IsolateArgs {
  final String url;
  final String headers;
  final String userAgent;
  final int mp3Bitrate;
  final int codec;
  final SendPort replyPort;

  _IsolateArgs({
    required this.url,
    required this.headers,
    required this.userAgent,
    required this.mp3Bitrate,
    required this.codec,
    required this.replyPort,
  });
}

class _FileArgs {
  final String url;
  final String headers;
  final String userAgent;
  final String outputPath;
  final SendPort replyPort;

  _FileArgs({
    required this.url,
    required this.headers,
    required this.userAgent,
    required this.outputPath,
    required this.replyPort,
  });
}

class _CmdNext {}

class _CmdStop {}

class _CmdTakeEncoded {}

class _CmdSeek {
  final double seconds;

  _CmdSeek(this.seconds);
}

class _DecoderReady {
  final int sampleRate;
  final int channels;
  final double durationSeconds;
  final SendPort commandPort;

  _DecoderReady(
    this.sampleRate,
    this.channels,
    this.durationSeconds,
    this.commandPort,
  );
}

class _DecodeChunk {
  final Uint8List data;

  _DecodeChunk(this.data);
}

class _DecodeEof {}

class _DecodeError {
  final String message;

  _DecodeError(this.message);
}

class _EncodedChunk {
  final Uint8List data;

  _EncodedChunk(this.data);
}

class _EncodedDone {}

class _SeekOk {}

class _SeekFail {
  final String message;

  _SeekFail(this.message);
}

class _FileDone {
  final bool ok;

  const _FileDone(this.ok);
}

// ---------------------------------------------------------------------------
// Pull-mode decode loop
// ---------------------------------------------------------------------------

/// Runs in a background isolate: opens the media, reports the audio
/// parameters, then decodes one chunk per [_CmdNext] command and returns
/// encoded (MP3) bytes per [_CmdTakeEncoded] command.
Future<void> _decodeLoop(_IsolateArgs args) async {
  final bridge = FfmpegBridge.instance;
  if (bridge == null) {
    args.replyPort.send(
      _DecodeError('FFmpeg bridge not available on this platform'),
    );
    return;
  }
  final handle = bridge.open(
    args.url,
    headers: args.headers,
    userAgent: args.userAgent,
    mp3Bitrate: args.mp3Bitrate,
    codec: args.codec,
  );
  if (handle == null) {
    args.replyPort.send(_DecodeError('bridge_open failed for ${args.url}'));
    return;
  }

  final sampleRate = bridge.getSampleRate(handle);
  final channels = bridge.getChannels(handle);
  final durationSeconds = bridge.getDuration(handle);

  final commandPort = ReceivePort();
  args.replyPort.send(
    _DecoderReady(sampleRate, channels, durationSeconds, commandPort.sendPort),
  );

  const chunkCapacity = 64 * 1024;
  final buffer = calloc<Uint8>(chunkCapacity);
  try {
    await commandPort.listen((Object? command) async {
      if (command is _CmdNext) {
        try {
          final n = bridge.readPcm(handle, buffer, chunkCapacity);
          if (n < 0) {
            args.replyPort.send(
              _DecodeError('readPcm error: ${bridge.lastError(handle)}'),
            );
          } else if (n == 0) {
            args.replyPort.send(_DecodeEof());
          } else {
            final copy = Uint8List.fromList(buffer.asTypedList(n));
            args.replyPort.send(_DecodeChunk(copy));
          }
        } catch (e) {
          args.replyPort.send(_DecodeError('readPcm threw: $e'));
        }
      } else if (command is _CmdTakeEncoded) {
        try {
          final n = bridge.takeEncoded(handle, buffer, chunkCapacity);
          if (n < 0) {
            // -2 = finished, -1 = error; both mean "no more encoded data".
            args.replyPort.send(_EncodedDone());
          } else if (n == 0) {
            args.replyPort.send(_EncodedChunk(Uint8List(0)));
          } else {
            final copy = Uint8List.fromList(buffer.asTypedList(n));
            args.replyPort.send(_EncodedChunk(copy));
          }
        } catch (e) {
          args.replyPort.send(_EncodedDone());
        }
      } else if (command is _CmdSeek) {
        final ok = bridge.seek(handle, command.seconds);
        if (ok) {
          args.replyPort.send(_SeekOk());
        } else {
          args.replyPort.send(
            _SeekFail('seek(${command.seconds}s): ${bridge.lastError(handle)}'),
          );
        }
      } else if (command is _CmdStop) {
        // Let the caller kill us; just stop responding.
      }
    }).asFuture<void>();
  } finally {
    calloc.free(buffer);
    bridge.close(handle);
  }
}

// ---------------------------------------------------------------------------
// File-mode decode loop (writes a WAV file)
// ---------------------------------------------------------------------------

/// Runs in a background isolate: decodes the whole media into a PCM WAV file.
Future<void> _decodeToFileLoop(_FileArgs args) async {
  final bridge = FfmpegBridge.instance;
  if (bridge == null) {
    args.replyPort.send(const _FileDone(false));
    return;
  }
  final handle = bridge.open(
    args.url,
    headers: args.headers,
    userAgent: args.userAgent,
  );
  if (handle == null) {
    args.replyPort.send(const _FileDone(false));
    return;
  }

  final sampleRate = bridge.getSampleRate(handle);
  final channels = bridge.getChannels(handle);

  const chunkCapacity = 64 * 1024;
  final buffer = calloc<Uint8>(chunkCapacity);
  RandomAccessFile? raf;
  try {
    final file = File(args.outputPath);
    raf = await file.open(mode: FileMode.write);
    await _writeWavHeader(raf, sampleRate, channels, 0);

    var dataSize = 0;
    var ok = true;
    while (true) {
      final n = bridge.readPcm(handle, buffer, chunkCapacity);
      if (n < 0) {
        ok = false;
        break;
      }
      if (n == 0) break;
      await raf.writeFrom(buffer.asTypedList(n));
      dataSize += n;
    }

    if (ok) {
      // Patch the RIFF/data chunk sizes now that we know the data size.
      await raf.setPosition(4);
      await raf.writeFrom(_uint32le(36 + dataSize));
      await raf.setPosition(40);
      await raf.writeFrom(_uint32le(dataSize));
    }
    // Close the file BEFORE reporting success: the caller renames the file
    // as soon as it receives this message, and an open handle would make
    // the rename fail (errno 32 on Windows).
    await raf.close();
    raf = null;
    args.replyPort.send(_FileDone(ok));
  } catch (e) {
    args.replyPort.send(const _FileDone(false));
  } finally {
    calloc.free(buffer);
    bridge.close(handle);
    try {
      await raf?.close();
    } catch (_) {}
  }
}

Future<void> _writeWavHeader(
  RandomAccessFile raf,
  int sampleRate,
  int channels,
  int dataSize,
) async {
  final bd = ByteData(44);
  // FourCC markers are written as big-endian so the bytes land in file order.
  bd.setUint32(0, 0x52494646, Endian.big); // "RIFF"
  bd.setUint32(4, 36 + dataSize, Endian.little);
  bd.setUint32(8, 0x57415645, Endian.big); // "WAVE"
  bd.setUint32(12, 0x666d7420, Endian.big); // "fmt "
  bd.setUint32(16, 16, Endian.little); // fmt chunk size
  bd.setUint16(20, 1, Endian.little); // PCM
  bd.setUint16(22, channels, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * channels * 2, Endian.little); // byte rate
  bd.setUint16(32, channels * 2, Endian.little); // block align
  bd.setUint16(34, 16, Endian.little); // bits per sample
  bd.setUint32(36, 0x64617461, Endian.big); // "data"
  bd.setUint32(40, dataSize, Endian.little);
  await raf.writeFrom(bd.buffer.asUint8List());
}

Uint8List _uint32le(int value) {
  final bd = ByteData(4);
  bd.setUint32(0, value, Endian.little);
  return bd.buffer.asUint8List();
}
