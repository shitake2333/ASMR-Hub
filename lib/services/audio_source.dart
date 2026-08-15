import 'package:flutter/widgets.dart';

import 'package:asmr_hub/models/audio_models.dart';

/// Abstract audio source interface
abstract class AudioSource {
  /// Audio source type ID
  String get sourceTypeId;

  /// Audio source name
  String get sourceName;

  /// Audio source icon (IconData)
  IconData get icon;

  /// Audio source icon (SVG Asset Path)
  String? get iconAsset;

  /// Get icon Widget
  Widget getIcon(
    BuildContext context, {
    String? path,
    double? size,
    Color? color,
  });

  /// Whether it is a live source
  bool get isLive;

  /// Whether search is supported
  bool get supportsSearch;

  /// Whether playlists are supported
  bool get supportsPlaylists;

  /// Whether authentication is required
  bool get requiresAuth;

  /// Search
  Future<List<AudioTrack>> search(String query, {int limit = 20});

  /// Initialize audio source
  Future<bool> initialize(AudioSourceConfig config);

  /// Get audio stream URL. [quality] optionally overrides the default
  /// quality preference for on-demand media.
  Future<String> getStreamUrl(String trackId, {String? quality});

  /// Get playlist
  Future<List<AudioTrack>> getPlaylist(String playlistUrl);

  /// Get recommendations
  Future<List<AudioTrack>> getRecommendations({int limit = 20});

  /// Verify if URL is supported
  bool canHandleUrl(String url);

  /// Parse audio info from URL
  Future<AudioTrack?> parseFromUrl(String url);

  /// Get detailed audio info
  Future<AudioTrack?> getTrackInfo(String trackId);

  /// Check if audio source is available
  Future<bool> checkAvailability();

  /// Download audio
  Future<void> download(AudioTrack track);

  /// Whether this source can record live streams to local files.
  bool get supportsLiveRecording;

  /// Whether a live recording is currently in progress.
  bool get isRecording;

  /// Starts recording the live stream of [liveTrack]. Returns true on
  /// success. Only valid when [supportsLiveRecording] is true.
  Future<bool> startRecording(AudioTrack liveTrack);

  /// Stops the in-progress recording.
  Future<void> stopRecording();

  /// Local recordings of the live room of [liveTrack].
  Future<List<AudioTrack>> loadRecordings(AudioTrack liveTrack);

  /// Whether the live room [roomId] is currently streaming.
  Future<bool> isRoomLive(String roomId);

  /// User-facing help text describing this source: what it is, which URL
  /// formats it accepts (single items, playlists, live rooms, ...), and any
  /// login requirements. Shown in the add-source dialog's help popup.
  /// Null/empty hides the help button.
  String? get helpText;

  /// Dispose resources
  Future<void> dispose();
}

/// Audio source exception
class AudioSourceException implements Exception {
  final String message;
  final String sourceTypeId;
  final AudioSourceExceptionType type;
  final dynamic originalError;

  AudioSourceException(
    this.message,
    this.sourceTypeId, {
    this.type = AudioSourceExceptionType.general,
    this.originalError,
  });

  @override
  String toString() {
    return 'AudioSourceException($sourceTypeId, $type): $message';
  }
}

enum AudioSourceExceptionType {
  general,
  unsupportedUrl,
  networkError,
  authRequired,
  notFound,
  playlistUrl,
}
