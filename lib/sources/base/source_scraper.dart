import 'package:asmr_hub/models/audio_models.dart';

abstract class SourceScraper {
  Future<List<AudioTrack>> scrapePlaylist(String url);
  Future<AudioTrack> scrapeVideo(String url);

  /// Resolves the stream URL for a track. [id] is the source track id
  /// (a room id for live sources). [quality] optionally overrides the
  /// user's default quality preference (on-demand media only).
  Future<String> scrapeStreamUrl(String id, {String? quality});
}
