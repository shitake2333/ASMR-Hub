import 'dart:async';
import 'dart:io';

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/ffmpeg/ffmpeg_audio_decoder.dart';
import 'package:asmr_hub/services/log_service.dart';

/// Recording status.
class RecordingStatus {
  final String sessionKey;
  final bool isRecording;
  final String? filePath;
  final int bytesWritten;
  final String? error;

  const RecordingStatus({
    required this.sessionKey,
    required this.isRecording,
    this.filePath,
    this.bytesWritten = 0,
    this.error,
  });
}

/// One active recording session (FLV passthrough or HLS->MP3).
class _RecorderSession {
  final String key;
  final String filePath;
  bool active = false;
  int bytes = 0;
  String? error;

  // FLV passthrough resources.
  HttpClient? client;
  HttpClientRequest? request;
  IOSink? sink;
  StreamSubscription<List<int>>? subscription;

  // HLS -> MP3 resources.
  FfmpegAudioDecoder? decoder;
  RandomAccessFile? hlsFile;

  _RecorderSession({required this.key, required this.filePath});
}

/// Records live streams to local files. Supports multiple concurrent
/// sessions (e.g. background monitoring of several rooms at once).
///
/// Transport per session:
/// - FLV over HTTP ([start]): raw bytes are streamed to the file as-is.
/// - HLS m3u8 ([startHls]): the stream is decoded by the bundled FFmpeg
///   bridge and re-encoded to MP3 while recording.
///
/// [statusStream] reports progress for every session.
class LiveRecorder {
  static final LiveRecorder _instance = LiveRecorder._internal();
  factory LiveRecorder() => _instance;
  LiveRecorder._internal();

  final LogService _logger = LogService();
  final StreamController<RecordingStatus> _statusController =
      StreamController<RecordingStatus>.broadcast();
  final Map<String, _RecorderSession> _sessions = {};

  /// Session key for a live track (source + room).
  static String keyFor(AudioTrack track) {
    final roomId = track.metadata?['roomId']?.toString() ?? track.id;
    return '${track.sourceTypeId}:$roomId';
  }

  /// Emits status changes while recording.
  Stream<RecordingStatus> get statusStream => _statusController.stream;

  /// Whether any session is recording.
  bool get isRecording => _sessions.values.any((s) => s.active);

  /// Whether the session with [key] is recording.
  bool isRecordingKey(String key) => _sessions[key]?.active ?? false;

  /// Whether any session whose key matches [test] is recording.
  bool isRecordingAny(bool Function(String key) test) =>
      _sessions.entries.any((e) => test(e.key) && e.value.active);

  /// Starts recording [streamUrl] into [filePath] (raw FLV passthrough).
  Future<bool> start(
    String streamUrl,
    String filePath, {
    required String key,
    Map<String, String>? headers,
  }) async {
    await stop(key);
    final session = _RecorderSession(key: key, filePath: filePath);
    _sessions[key] = session;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15)
        // Live CDN edges sometimes serve mismatched certificates; the
        // stream is audio-only and never executed, so accept them.
        ..badCertificateCallback = (cert, host, port) => true;
      session.client = client;
      final request = await client.getUrl(Uri.parse(streamUrl));
      session.request = request;
      final ua =
          headers?['User-Agent'] ??
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      request.headers.set('User-Agent', ua);
      final referer = headers?['Referer'];
      if (referer != null) request.headers.set('Referer', referer);

      final response = await request.close();
      if (response.statusCode != 200) {
        _logger.warning('Recording request failed: ${response.statusCode}');
        _sessions.remove(key);
        // Close the client so the socket is not leaked.
        session.client?.close(force: true);
        session.client = null;
        return false;
      }

      // Ensure the directory exists.
      final file = File(filePath);
      await file.parent.create(recursive: true);
      session.sink = file.openWrite();

      session.active = true;

      session.subscription = response.listen(
        (chunk) {
          if (!session.active) return;
          session.sink?.add(chunk);
          session.bytes += chunk.length;
          if (session.bytes % (1024 * 1024) < 64 * 1024) {
            _emit(session);
          }
        },
        onError: (Object e) {
          _logger.error('Recording stream error', e);
          session.error = e.toString();
          _emit(session);
          unawaited(stop(key));
        },
        onDone: () {
          unawaited(stop(key));
        },
        cancelOnError: true,
      );

      _emit(session);
      _logger.info('Recording started: $filePath');
      return true;
    } catch (e) {
      _logger.error('Failed to start recording', e);
      await stop(key);
      return false;
    }
  }

  /// Starts recording an HLS (m3u8) live stream as MP3 via the FFmpeg bridge.
  Future<bool> startHls(
    String streamUrl,
    String filePath, {
    required String key,
    String? bridgeHeaders,
    String? userAgent,
  }) async {
    await stop(key);
    final session = _RecorderSession(key: key, filePath: filePath);
    _sessions[key] = session;
    try {
      final file = File(filePath);
      await file.parent.create(recursive: true);
      final raf = await file.open(mode: FileMode.write);
      session.hlsFile = raf;

      final decoder = FfmpegAudioDecoder();
      session.decoder = decoder;
      final info = await decoder.start(
        streamUrl,
        headers: bridgeHeaders ?? '',
        userAgent: userAgent,
        mp3Bitrate: 128000,
      );
      if (info == null) {
        _logger.error('HLS recording: cannot open $streamUrl');
        await raf.close();
        session.hlsFile = null;
        try {
          await file.delete();
        } catch (_) {}
        _sessions.remove(key);
        return false;
      }

      session.active = true;
      _emit(session);
      _logger.info('HLS recording started: $filePath');

      unawaited(_hlsRecordLoop(session, decoder, raf));
      return true;
    } catch (e) {
      _logger.error('Failed to start HLS recording', e);
      await stop(key);
      return false;
    }
  }

  Future<void> _hlsRecordLoop(
    _RecorderSession session,
    FfmpegAudioDecoder decoder,
    RandomAccessFile raf,
  ) async {
    try {
      while (session.active && _sessions[session.key] == session) {
        // Drive decoding by pulling PCM (discarded); the encoder sidecar
        // produces the MP3 we keep.
        final chunk = await decoder.nextChunk().timeout(
          const Duration(seconds: 15),
          onTimeout: () => null,
        );
        if (chunk == null || chunk.isEmpty) {
          // EOF/error: drain whatever the encoder flushed.
          await _drainEncoded(session, decoder, raf);
          break;
        }
        await _drainEncoded(session, decoder, raf);
      }
    } catch (e) {
      _logger.error('HLS recording loop error', e);
      session.error = e.toString();
      _emit(session);
    } finally {
      unawaited(stop(session.key));
    }
  }

  Future<void> _drainEncoded(
    _RecorderSession session,
    FfmpegAudioDecoder decoder,
    RandomAccessFile raf,
  ) async {
    while (session.active && _sessions[session.key] == session) {
      final enc = await decoder.takeEncoded().timeout(
        const Duration(seconds: 15),
        onTimeout: () => null,
      );
      if (enc == null || enc.isEmpty) return;
      await raf.writeFrom(enc);
      session.bytes += enc.length;
      if (session.bytes % (1024 * 1024) < 64 * 1024) {
        _emit(session);
      }
    }
  }

  /// Stops one session (or all when [key] is null) and closes its file.
  Future<void> stop([String? key]) async {
    final sessions = key == null
        ? _sessions.values.toList()
        : [_sessions.remove(key)].whereType<_RecorderSession>().toList();
    await _stopSessions(sessions, remove: key == null);
  }

  /// Stops every session whose key matches [test].
  Future<void> stopWhere(bool Function(String key) test) async {
    final sessions = _sessions.values.where((s) => test(s.key)).toList();
    await _stopSessions(sessions, remove: true);
  }

  Future<void> _stopSessions(
    List<_RecorderSession> sessions, {
    required bool remove,
  }) async {
    for (final session in sessions) {
      session.active = false;
      await session.subscription?.cancel();
      session.subscription = null;
      session.request?.abort();
      session.request = null;
      try {
        await session.sink?.flush();
        await session.sink?.close();
      } catch (e) {
        // ignore
      }
      session.sink = null;
      session.client?.close(force: true);
      session.client = null;
      final hlsFile = session.hlsFile;
      session.hlsFile = null;
      if (hlsFile != null) {
        try {
          await hlsFile.flush();
          await hlsFile.close();
        } catch (e) {
          // ignore
        }
      }
      final decoder = session.decoder;
      session.decoder = null;
      if (decoder != null) {
        await decoder.stop();
      }
      if (remove) {
        _sessions.remove(session.key);
      }
      _emit(session);
      _logger.info(
        'Recording stopped: ${session.filePath} (${session.bytes} bytes)',
      );
    }
  }

  void _emit(_RecorderSession session) {
    _statusController.add(
      RecordingStatus(
        sessionKey: session.key,
        isRecording: session.active,
        filePath: session.filePath,
        bytesWritten: session.bytes,
        error: session.error,
      ),
    );
  }

  void dispose() {
    unawaited(stop());
    _statusController.close();
  }
}
