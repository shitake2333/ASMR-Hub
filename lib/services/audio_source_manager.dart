import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/audio_source.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/sources/asmrone/asmr_one_source.dart';
import 'package:asmr_hub/sources/bilibili/bilibili_source.dart';
import 'package:asmr_hub/sources/dlsite/dlsite_source.dart';
import 'package:asmr_hub/sources/douyu/douyu_source.dart';
import 'package:asmr_hub/sources/local/local_source.dart';
import 'package:asmr_hub/sources/twitch/twitch_source.dart';
import 'package:asmr_hub/sources/youtube/youtube_source.dart';

/// Audio source manager
class AudioSourceManager {
  static final AudioSourceManager _instance = AudioSourceManager._internal();
  factory AudioSourceManager() => _instance;
  AudioSourceManager._internal();

  static const String _configsKey = 'audio_source_configs_v1';

  final Map<String, AudioSource> _sources = {};
  final List<AudioSourceConfig> _configs = [];
  final LogService _logger = LogService();
  bool _isInitialized = false;

  /// In-flight initialization future; concurrent callers await the same one
  /// instead of racing through the (mutable) config/source lists.
  Future<void>? _initializing;

  /// Initialize audio source manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    // Serialize concurrent initialize() calls (multiple providers call this
    // during app startup).
    final inFlight = _initializing;
    if (inFlight != null) return inFlight;

    final future = _doInitialize();
    _initializing = future;
    try {
      await future;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _doInitialize() async {
    // Register all audio sources
    _registerSources();

    // Load configurations
    await _loadConfigs();

    // Initialize enabled audio sources
    await _initializeSources();

    // Only mark initialized after all steps succeed (allows retry on error).
    _isInitialized = true;
  }

  /// Register audio source
  void _registerSources() {
    registerSource(LocalAudioSource());
    registerSource(YouTubeSource());
    registerSource(BilibiliSource());
    registerSource(DLSiteSource());
    registerSource(DouyuSource());
    registerSource(AsmrOneSource());
    registerSource(TwitchSource());
  }

  /// Register single audio source
  void registerSource(AudioSource source) {
    _sources[source.sourceTypeId] = source;
  }

  /// Get all registered sources
  List<AudioSource> getSources() {
    return _sources.values.toList();
  }

  /// Load configurations (from local storage or default)
  Future<void> _loadConfigs() async {
    _configs.clear();
    // Restore persisted configs (custom sources / toggle states), then merge
    // with built-in defaults so a missing stored entry still initializes.
    final Map<String, AudioSourceConfig> merged = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_configsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final e in list) {
          if (e is Map<String, dynamic>) {
            final cfg = AudioSourceConfig.fromJson(e);
            merged[cfg.sourceTypeId] = cfg;
          }
        }
      }
    } catch (e) {
      _logger.error('Failed to load persisted source configs', e);
    }

    // Built-in defaults (persisted entries win).
    final defaults = <AudioSourceConfig>[
      AudioSourceConfig(
        id: 'local',
        name: 'Local Files',
        sourceTypeId: 'local',
        endpoint: '',
        parameters: {'rootDirectory': '/storage/emulated/0/Music'},
        isEnabled: true,
      ),
      AudioSourceConfig(
        id: 'youtube',
        name: 'YouTube',
        sourceTypeId: 'youtube',
        endpoint: 'https://www.googleapis.com/youtube/v3',
        parameters: {
          'apiKey': '', // User configuration required
        },
        isEnabled: true,
      ),
      AudioSourceConfig(
        id: 'bilibili',
        name: 'Bilibili',
        sourceTypeId: 'bilibili',
        endpoint: 'https://api.bilibili.com',
        isEnabled: true,
      ),
      AudioSourceConfig(
        id: 'dlsite',
        name: 'DLSite',
        sourceTypeId: 'dlsite',
        endpoint: 'https://www.dlsite.com',
        isEnabled: true,
      ),
      AudioSourceConfig(
        id: 'douyu',
        name: 'Douyu',
        sourceTypeId: 'douyu',
        endpoint: 'https://www.douyu.com',
        isEnabled: true,
      ),
      AudioSourceConfig(
        id: 'asmrone',
        name: 'asmr.one',
        sourceTypeId: 'asmrone',
        endpoint: 'https://api.asmr-200.com',
        isEnabled: true,
      ),
      AudioSourceConfig(
        id: 'twitch',
        name: 'Twitch',
        sourceTypeId: 'twitch',
        endpoint: 'https://www.twitch.tv',
        isEnabled: true,
      ),
    ];
    for (final cfg in defaults) {
      merged.putIfAbsent(cfg.sourceTypeId, () => cfg);
    }
    _configs.addAll(merged.values);
  }

  /// Initialize audio sources
  Future<void> _initializeSources() async {
    for (final config in _configs) {
      if (config.isEnabled && _sources.containsKey(config.sourceTypeId)) {
        final source = _sources[config.sourceTypeId]!;
        try {
          final initialized = await source.initialize(config);
          if (!initialized) {
            _logger.error(
              'Failed to initialize audio source: ${config.name}',
              null,
              StackTrace.current,
            );
          }
        } catch (e, stack) {
          _logger.error(
            'Exception initializing audio source: ${config.name}',
            e,
            stack,
          );
        }
      }
    }
  }

  /// Parse URL to get audio info
  Future<AudioTrack?> parseUrl(String url) async {
    for (final source in _sources.values) {
      bool canHandle;
      try {
        canHandle = source.canHandleUrl(url);
      } catch (e, stack) {
        _logger.error('canHandleUrl failed for ${source.sourceName}', e, stack);
        continue;
      }
      if (!canHandle) continue;
      try {
        final track = await source.parseFromUrl(url);
        if (track != null) return track;
      } catch (e, stack) {
        _logger.error('Failed to parse URL ${source.sourceName}', e, stack);
      }
    }
    return null;
  }

  /// Get playlist
  Future<List<AudioTrack>> getPlaylist(String url) async {
    for (final source in _sources.values) {
      bool canHandle;
      try {
        canHandle = source.canHandleUrl(url);
      } catch (e, stack) {
        _logger.error('canHandleUrl failed for ${source.sourceName}', e, stack);
        continue;
      }
      if (!canHandle || !source.supportsPlaylists) continue;
      try {
        return await source.getPlaylist(url);
      } catch (e, stack) {
        _logger.error('Failed to get playlist ${source.sourceName}', e, stack);
      }
    }
    throw AudioSourceException('Unsupported playlist URL', 'unknown');
  }

  /// Get stream URL
  Future<String> getStreamUrl(AudioTrack track, {String? quality}) async {
    final source = _sources[track.sourceTypeId];
    if (source == null) {
      throw AudioSourceException(
        'Unsupported audio source type',
        track.sourceTypeId,
      );
    }

    if (track.streamUrl.isNotEmpty) {
      return track.streamUrl;
    }

    return await source.getStreamUrl(track.id, quality: quality);
  }

  /// Download audio
  Future<void> download(AudioTrack track) async {
    final source = _sources[track.sourceTypeId];
    if (source == null) {
      throw AudioSourceException(
        'Unsupported audio source type',
        track.sourceTypeId,
      );
    }
    await source.download(track);
  }

  /// Get recommendations
  Future<List<AudioTrack>> getRecommendations({int limit = 20}) async {
    final results = <AudioTrack>[];

    for (final source in _sources.values) {
      try {
        final tracks = await source.getRecommendations(
          limit: limit ~/ _sources.length,
        );
        results.addAll(tracks);
      } catch (e, stack) {
        _logger.error(
          'Failed to get recommendations ${source.sourceName}',
          e,
          stack,
        );
      }
    }

    return results.take(limit).toList();
  }

  /// Get audio source list
  List<AudioSource> getAvailableSources() {
    return _sources.values.where((source) {
      final config = _configs.firstWhere(
        (c) => c.sourceTypeId == source.sourceTypeId,
        orElse: () => AudioSourceConfig(
          id: '',
          name: '',
          sourceTypeId: source.sourceTypeId,
          endpoint: '',
          isEnabled: false,
        ),
      );
      return config.isEnabled;
    }).toList();
  }

  /// Check audio source availability
  Future<Map<String, bool>> checkSourcesAvailability() async {
    final results = <String, bool>{};

    for (final entry in _sources.entries) {
      try {
        final isAvailable = await entry.value.checkAvailability();
        results[entry.key] = isAvailable;
      } catch (e) {
        results[entry.key] = false;
      }
    }

    return results;
  }

  /// Update audio source configuration
  Future<void> updateSourceConfig(AudioSourceConfig config) async {
    final index = _configs.indexWhere((c) => c.id == config.id);
    if (index != -1) {
      _configs[index] = config;

      // Re-initialize this audio source
      final source = _sources[config.sourceTypeId];
      if (source != null && config.isEnabled) {
        await source.initialize(config);
      }
    }
  }

  /// Add custom audio source configuration
  Future<void> addCustomSource(AudioSourceConfig config) async {
    _configs.add(config);
    await _saveConfigs();
  }

  /// Save configuration to local storage (persisted so custom sources and
  /// enabled/disabled states survive restarts).
  Future<void> _saveConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _configsKey,
        jsonEncode(_configs.map((c) => c.toJson()).toList()),
      );
    } catch (e) {
      _logger.error('Failed to save source configs', e);
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    for (final source in _sources.values) {
      try {
        await source.dispose();
      } catch (e) {
        _logger.error('Failed to dispose source ${source.sourceTypeId}', e);
      }
    }
    _sources.clear();
    _configs.clear();
    // Allow re-initialization after dispose (idempotent-safe).
    _isInitialized = false;
  }
}
