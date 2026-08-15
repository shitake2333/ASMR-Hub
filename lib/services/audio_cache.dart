import 'package:path/path.dart' as p;

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/download_manager.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/services/preferences_service.dart';

/// Resolves on-disk cached/downloaded files for tracks and computes the
/// auto-cache target path. Playback prefers a downloaded file (real audio
/// file, no network, no re-decoding) over the network stream.
class AudioCache {
  /// The downloaded file for [track] (via the download index), or null.
  static Future<String?> downloadedFileFor(AudioTrack track) async {
    try {
      return await DownloadManager.instance.downloadedFileFor(track);
    } catch (e) {
      LogService().warning('downloadedFileFor failed: $e');
      return null;
    }
  }

  /// Target path in the download folder for [track] with extension [ext]
  /// (mirrors DownloadManager.targetFileFor).
  static Future<String?> cacheFilePath(AudioTrack? track, String ext) async {
    if (track == null) return null;
    try {
      final base = await PreferencesService().getDownloadPath();
      final safeTitle = track.title
          .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
          .trim();
      final name = (safeTitle.isEmpty ? track.id : safeTitle).replaceAll(
        RegExp(r'[<>:"/\\|?*\x00-\x1F]'),
        '_',
      );
      return p.join(base, track.sourceTypeId, '$name.$ext');
    } catch (e) {
      LogService().warning('Cannot resolve download path: $e');
      return null;
    }
  }
}
