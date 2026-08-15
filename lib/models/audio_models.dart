/// Audio file information model
class AudioTrack {
  final String id;
  final String title;
  final String artist;
  final String? albumArt;
  final Duration duration;
  final String streamUrl;
  final String sourceTypeId;
  final String? description;
  final Map<String, dynamic>? metadata;

  AudioTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.albumArt,
    required this.duration,
    required this.streamUrl,
    required this.sourceTypeId,
    this.description,
    this.metadata,
  });

  factory AudioTrack.fromJson(Map<String, dynamic> json) {
    return AudioTrack(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      artist: json['artist']?.toString() ?? '',
      albumArt: json['albumArt']?.toString(),
      duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
      streamUrl: json['streamUrl']?.toString() ?? '',
      sourceTypeId: json['sourceTypeId']?.toString() ?? 'unknown',
      description: json['description']?.toString(),
      metadata: json['metadata'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'albumArt': albumArt,
      'duration': duration.inSeconds,
      'streamUrl': streamUrl,
      'sourceTypeId': sourceTypeId,
      'description': description,
      'metadata': metadata,
    };
  }
}

/// Playlist model
class Playlist {
  final String id;
  final String name;
  final String? description;
  final String? coverArt;
  final List<AudioTrack> tracks;
  final DateTime createdAt;
  final DateTime updatedAt;

  Playlist({
    required this.id,
    required this.name,
    this.description,
    this.coverArt,
    required this.tracks,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      coverArt: json['coverArt']?.toString(),
      tracks: (json['tracks'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((trackJson) => AudioTrack.fromJson(trackJson))
          .toList(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'coverArt': coverArt,
      'tracks': tracks.map((track) => track.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

/// Audio source configuration
class AudioSourceConfig {
  final String id;
  final String name;
  final String sourceTypeId;
  final String endpoint;
  final Map<String, String>? headers;
  final Map<String, dynamic>? parameters;
  final bool isEnabled;
  final bool enableCache;

  AudioSourceConfig({
    required this.id,
    required this.name,
    required this.sourceTypeId,
    required this.endpoint,
    this.headers,
    this.parameters,
    this.isEnabled = true,
    this.enableCache = false,
  });

  factory AudioSourceConfig.fromJson(Map<String, dynamic> json) {
    return AudioSourceConfig(
      id: json['id'],
      name: json['name'],
      sourceTypeId: json['sourceTypeId'] ?? 'unknown',
      endpoint: json['endpoint'],
      headers: json['headers']?.cast<String, String>(),
      parameters: json['parameters'],
      isEnabled: json['isEnabled'] ?? true,
      enableCache: json['enableCache'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'sourceTypeId': sourceTypeId,
      'endpoint': endpoint,
      'headers': headers,
      'parameters': parameters,
      'isEnabled': isEnabled,
      'enableCache': enableCache,
    };
  }
}
