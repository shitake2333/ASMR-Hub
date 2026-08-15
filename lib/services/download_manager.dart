import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/audio_source_manager.dart';
import 'package:asmr_hub/services/ffmpeg/ffmpeg_audio_decoder.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/services/preferences_service.dart';
import 'package:asmr_hub/sources/base/base_source.dart';

/// Status of a background download task.
enum DownloadTaskStatus { queued, downloading, completed, failed, canceled }

/// A background audio download task.
class DownloadTask {
  final String trackId;
  final AudioTrack track;
  final String filePath;
  final String ext; // 'mp3' | 'wav' | original for local copies
  final String? quality; // requested audio quality (null = default)
  DownloadTaskStatus status;
  int bytesDone;
  String? error;

  DownloadTask({
    required this.trackId,
    required this.track,
    required this.filePath,
    required this.ext,
    this.quality,
    this.status = DownloadTaskStatus.queued,
    this.bytesDone = 0,
  });

  bool get isActive =>
      status == DownloadTaskStatus.queued ||
      status == DownloadTaskStatus.downloading;
}

/// Background download manager.
///
/// Conceptually separates "downloads" (real audio files with proper
/// extensions in the user's download folder, visible to other software) from
/// "cache" (metadata, covers, playlist info).
///
/// Downloads run one at a time. On-demand media is decoded by the FFmpeg
/// bridge and written as MP3 (default) or WAV, matching the configured
/// download format. Local files are copied as-is.
class DownloadManager extends ChangeNotifier {
  static final DownloadManager instance = DownloadManager._();
  DownloadManager._();

  final LogService _logger = LogService();
  final List<DownloadTask> _tasks = [];
  bool _processing = false;

  /// Persisted index of downloaded files by track id. Lookup by title is
  /// unreliable (titles change), so playback checks this map first.
  final Map<String, String> _fileIndex = {};
  static const String _indexPrefsKey = 'download_index_v1';
  bool _indexLoaded = false;

  /// Loads the persisted download index (call once at startup).
  Future<void> start() async {
    if (_indexLoaded) return;
    _indexLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_indexPrefsKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map.forEach((k, v) {
          if (v is String) _fileIndex[k] = v;
        });
      }
    } catch (e) {
      _logger.warning('Failed to load download index: $e');
    }
    // Drop index entries whose files are gone.
    unawaited(validateIndex());
  }

  Future<void> _saveIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_indexPrefsKey, jsonEncode(_fileIndex));
    } catch (e) {
      _logger.warning('Failed to save download index: $e');
    }
  }

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  /// Active (queued/downloading) task for [trackId], if any.
  DownloadTask? activeTaskFor(String trackId) {
    for (final t in _tasks) {
      if (t.trackId == trackId && t.isActive) return t;
    }
    return null;
  }

  /// Completed (file exists) task for [trackId], if any.
  DownloadTask? completedTaskFor(String trackId) {
    for (final t in _tasks) {
      if (t.trackId == trackId && t.status == DownloadTaskStatus.completed) {
        return t;
      }
    }
    return null;
  }

  /// Target file path for [track] in the download folder, honouring the
  /// configured download format ('off' -> null).
  Future<String?> targetFileFor(AudioTrack track) async {
    final format = PreferencesService().getCacheFormat();
    if (format == 'off') return null;
    final ext = format; // 'mp3' | 'wav'
    final base = await PreferencesService().getDownloadPath();
    final safeTitle = track.title
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    final dir = p.join(base, track.sourceTypeId);
    final name = (safeTitle.isEmpty ? track.id : safeTitle).replaceAll(
      RegExp(r'[<>:"/\\|?*\x00-\x1F]'),
      '_',
    );
    return p.join(dir, '$name.$ext');
  }

  /// Returns the downloaded file path if a complete file already exists.
  /// Checks the track-id index first (reliable), then falls back to the
  /// title-derived path (for files downloaded before the index existed).
  Future<String?> downloadedFileFor(AudioTrack track) async {
    final indexed = _fileIndex[track.id];
    if (indexed != null && await File(indexed).exists()) return indexed;
    final f = await targetFileFor(track);
    if (f != null && await File(f).exists()) {
      // Adopt legacy downloads into the index.
      _fileIndex[track.id] = f;
      unawaited(_saveIndex());
      return f;
    }
    return null;
  }

  /// Whether [track] has a complete downloaded file.
  Future<bool> isDownloaded(AudioTrack track) async {
    return await downloadedFileFor(track) != null;
  }

  /// Synchronous in-memory check: whether the index knows [trackId] as
  /// downloaded (fast path for UI badges; files are validated on startup).
  bool isTrackCached(String trackId) => _fileIndex.containsKey(trackId);

  /// Ids of [tracks] that have a downloaded file.
  Future<Set<String>> downloadedIdsFor(Iterable<AudioTrack> tracks) async {
    final ids = <String>{};
    for (final t in tracks) {
      if (await isDownloaded(t)) ids.add(t.id);
    }
    return ids;
  }

  /// Removes index entries whose file no longer exists. Called on startup
  /// and when a source detail page is opened.
  Future<void> validateIndex() async {
    var changed = false;
    final stale = <String>[];
    for (final entry in _fileIndex.entries) {
      final f = File(entry.value);
      if (!await f.exists()) stale.add(entry.key);
    }
    for (final key in stale) {
      _fileIndex.remove(key);
      changed = true;
    }
    if (changed) {
      await _saveIndex();
      notifyListeners();
    }
  }

  /// Total size (bytes) of all downloaded files of [sourceTypeId].
  Future<int> sourceDownloadSize(String sourceTypeId) async {
    try {
      final base = await PreferencesService().getDownloadPath();
      final dir = Directory(p.join(base, sourceTypeId));
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final file in dir.list(recursive: true)) {
        if (file is File) {
          try {
            total += await file.length();
          } catch (_) {}
        }
      }
      return total;
    } catch (e) {
      _logger.warning('Cannot compute download size for $sourceTypeId: $e');
      return 0;
    }
  }

  /// Deletes every downloaded file of [sourceTypeId] (directory-level) and
  /// drops the matching index entries. Active tasks of this source are
  /// cancelled first so a finishing task cannot re-add a ghost index entry.
  Future<void> clearSourceDownloads(String sourceTypeId) async {
    // Cancel active tasks of this source and wait briefly for them to abort.
    final active = _tasks.where(
      (t) => t.track.sourceTypeId == sourceTypeId && t.isActive,
    );
    for (final t in active.toList()) {
      t.status = DownloadTaskStatus.canceled;
    }
    if (active.isNotEmpty) {
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    try {
      final base = await PreferencesService().getDownloadPath();
      final dir = Directory(p.join(base, sourceTypeId));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      _logger.warning('Cannot clear downloads for $sourceTypeId: $e');
    }
    // Drop index entries whose path points into this source's folder.
    final prefix = p.joinAll([
      await PreferencesService().getDownloadPath(),
      sourceTypeId,
      '',
    ]);
    final stale = <String>[];
    _fileIndex.forEach((id, path) {
      if (path.startsWith(prefix)) stale.add(id);
    });
    if (stale.isNotEmpty) {
      stale.forEach(_fileIndex.remove);
      await _saveIndex();
    }
    notifyListeners();
  }

  /// Enqueues a download for [track]. [quality] optionally overrides the
  /// default quality preference. Returns the task, or null when the download
  /// format is off or the file already exists.
  Future<DownloadTask?> startDownload(
    AudioTrack track, {
    String? quality,
  }) async {
    final filePath = await targetFileFor(track);
    if (filePath == null) return null;
    if (await File(filePath).exists()) return null; // already downloaded

    final existing = activeTaskFor(track.id);
    if (existing != null) return existing;

    final task = DownloadTask(
      trackId: track.id,
      track: track,
      filePath: filePath,
      ext: p.extension(filePath).replaceFirst('.', ''),
      quality: quality ?? PreferencesService().getAudioQuality(),
    );
    _tasks.add(task);
    notifyListeners();
    unawaited(_process());
    return task;
  }

  /// Cancels a queued/running task. The partial file is removed.
  Future<void> cancel(String trackId) async {
    final task = activeTaskFor(trackId);
    if (task == null) return;
    task.status = DownloadTaskStatus.canceled;
    notifyListeners();
    // The running executor checks the status after each chunk and aborts.
  }

  /// Removes the task record and deletes the downloaded file (if any).
  Future<void> remove(String trackId) async {
    final task = _tasks.where((t) => t.trackId == trackId).toList();
    for (final t in task) {
      if (t.isActive) {
        await cancel(trackId);
        // Wait until it settles.
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    _tasks.removeWhere((t) => t.trackId == trackId);
    notifyListeners();
  }

  /// Deletes the downloaded file of [track] if present.
  Future<void> deleteFile(AudioTrack track) async {
    final f = await downloadedFileFor(track);
    if (f != null) {
      try {
        final file = File(f);
        if (await file.exists()) await file.delete();
      } catch (e) {
        _logger.warning('Failed to delete download file: $e');
      }
    }
    if (_fileIndex.remove(track.id) != null) {
      await _saveIndex();
    }
    notifyListeners();
  }

  /// Processes queued tasks with up to [maxThreads] concurrent downloads.
  /// Each task runs in its own async worker; the workers are fanned out from
  /// the queue as slots free up.
  Future<void> _process() async {
    if (_processing) return;
    _processing = true;
    try {
      while (true) {
        final maxThreads = PreferencesService().getMaxDownloadThreads();
        // Collect queued tasks.
        final queued = _tasks
            .where((t) => t.status == DownloadTaskStatus.queued)
            .toList();
        if (queued.isEmpty) break;

        // Fill up to `maxThreads` concurrent workers.
        final batch = queued.take(maxThreads).toList();
        await Future.wait(batch.map((task) => _execute(task)));
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _execute(DownloadTask task) async {
    task.status = DownloadTaskStatus.downloading;
    notifyListeners();
    try {
      // Resolve the real stream URL.
      final manager = AudioSourceManager();
      final streamUrl =
          task.track.streamUrl.isNotEmpty &&
              task.track.streamUrl.startsWith('http')
          ? task.track.streamUrl
          : await manager.getStreamUrl(task.track, quality: task.quality);
      if (streamUrl.isEmpty) {
        throw Exception('No stream URL available');
      }

      // Local files are copied directly (keep original format).
      if (!streamUrl.startsWith('http')) {
        await _copyLocal(task, streamUrl);
        return;
      }

      final source = manager.getSources().firstWhere(
        (s) => s.sourceTypeId == task.track.sourceTypeId,
        orElse: () => throw Exception('Unknown source'),
      );
      final headers = (source is BaseAudioSource)
          ? source.downloadHeaders(task.track)
          : const <String, String>{};
      final headerString = headers.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\r\n');
      final ua = headers['User-Agent'];

      final isMp3 = task.ext == 'mp3';
      final isFlac = task.ext == 'flac';
      // codec: 0 = none (PCM), 1 = MP3, 2 = FLAC.
      final encCodec = isMp3
          ? 1
          : isFlac
          ? 2
          : 0;
      final decoder = FfmpegAudioDecoder();
      final info = await decoder.start(
        streamUrl,
        headers: headerString,
        userAgent: ua,
        mp3Bitrate: isMp3 ? 192000 : 0,
        codec: encCodec,
      );
      if (info == null) {
        throw Exception('Cannot open media for download');
      }

      final partPath = '${task.filePath}.part';
      await File(partPath).parent.create(recursive: true);
      final raf = await File(partPath).open(mode: FileMode.write);
      var dataSize = 0;
      // Rate limiting state: bytes written since the last throttle tick.
      final maxRateKb = PreferencesService().getMaxDownloadRate();
      var rateWindowBytes = 0;
      var rateWindowStart = DateTime.now();
      Future<void> throttle(int written) async {
        if (maxRateKb <= 0) return;
        rateWindowBytes += written;
        final elapsedMs = DateTime.now()
            .difference(rateWindowStart)
            .inMilliseconds;
        final limitBytesPerSec = maxRateKb * 1024;
        if (rateWindowBytes >= limitBytesPerSec) {
          final targetMs = (rateWindowBytes / limitBytesPerSec * 1000).round();
          final wait = targetMs - elapsedMs;
          if (wait > 0) {
            await Future<void>.delayed(Duration(milliseconds: wait));
          }
          rateWindowBytes = 0;
          rateWindowStart = DateTime.now();
        }
      }

      try {
        // Encoded formats (MP3/FLAC) need no WAV header; raw PCM does.
        if (!isMp3 && !isFlac) {
          await raf.writeFrom(
            _wavHeaderBytes(info.sampleRate, info.channels, 0),
          );
        }
        var lastNotify = 0;
        while (true) {
          if (task.status != DownloadTaskStatus.downloading) {
            throw Exception('canceled');
          }
          final chunk = await decoder.nextChunk().timeout(
            const Duration(seconds: 30),
            onTimeout: () => null,
          );
          if (chunk == null || chunk.isEmpty) break;
          if (isMp3 || isFlac) {
            while (true) {
              final enc = await decoder.takeEncoded();
              if (enc == null || enc.isEmpty) break;
              await raf.writeFrom(enc);
              dataSize += enc.length;
              task.bytesDone = dataSize;
              await throttle(enc.length);
            }
          } else {
            await raf.writeFrom(chunk);
            dataSize += chunk.length;
            task.bytesDone = dataSize;
            await throttle(chunk.length);
          }
          if (task.bytesDone - lastNotify > 256 * 1024) {
            lastNotify = task.bytesDone;
            notifyListeners();
          }
        }
        // EOF: drain remaining encoded bytes (encoder flush).
        if (isMp3 || isFlac) {
          while (true) {
            final enc = await decoder.takeEncoded();
            if (enc == null || enc.isEmpty) break;
            await raf.writeFrom(enc);
            dataSize += enc.length;
            task.bytesDone = dataSize;
          }
        }
        await raf.close();
        if (!isMp3 && !isFlac) {
          // Patch WAV sizes.
          final f = File(partPath);
          final r = await f.open(mode: FileMode.write);
          await r.setPosition(4);
          await r.writeFrom(_uint32le(36 + dataSize));
          await r.setPosition(40);
          await r.writeFrom(_uint32le(dataSize));
          await r.close();
        }
        await File(partPath).rename(task.filePath);
        task.status = DownloadTaskStatus.completed;
        _fileIndex[task.trackId] = task.filePath;
        unawaited(_saveIndex());
        _logger.info('Download completed: ${task.filePath} ($dataSize bytes)');
      } finally {
        try {
          await raf.close();
        } catch (_) {}
        await decoder.stop();
        // Clean up a leftover partial file on failure/cancel.
        if (task.status != DownloadTaskStatus.completed) {
          try {
            final f = File(partPath);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      if (task.status == DownloadTaskStatus.canceled) {
        _logger.info('Download canceled: ${task.filePath}');
      } else {
        task.status = DownloadTaskStatus.failed;
        task.error = e.toString();
        _logger.error('Download failed: ${task.filePath}', e);
      }
    }
    notifyListeners();
  }

  Future<void> _copyLocal(DownloadTask task, String localPath) async {
    final src = File(localPath);
    if (!await src.exists()) {
      throw Exception('Local file not found: $localPath');
    }
    await File(task.filePath).parent.create(recursive: true);
    await src.copy(task.filePath);
    task.bytesDone = await File(task.filePath).length();
    task.status = DownloadTaskStatus.completed;
    _fileIndex[task.trackId] = task.filePath;
    unawaited(_saveIndex());
    _logger.info('Copied ${task.track.title} -> ${task.filePath}');
  }

  // ------------------------------------------------------------ WAV utils

  static Uint8List _wavHeaderBytes(int sampleRate, int channels, int dataSize) {
    final bd = ByteData(44);
    bd.setUint32(0, 0x52494646, Endian.big); // "RIFF"
    bd.setUint32(4, 36 + dataSize, Endian.little);
    bd.setUint32(8, 0x57415645, Endian.big); // "WAVE"
    bd.setUint32(12, 0x666d7420, Endian.big); // "fmt "
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * channels * 2, Endian.little);
    bd.setUint16(32, channels * 2, Endian.little);
    bd.setUint16(34, 16, Endian.little);
    bd.setUint32(36, 0x64617461, Endian.big); // "data"
    bd.setUint32(40, dataSize, Endian.little);
    return bd.buffer.asUint8List();
  }

  static Uint8List _uint32le(int value) {
    final bd = ByteData(4);
    bd.setUint32(0, value, Endian.little);
    return bd.buffer.asUint8List();
  }
}
