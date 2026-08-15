import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/audio_cache.dart';
import 'package:asmr_hub/services/audio_source.dart' as source_api;
import 'package:asmr_hub/services/audio_source_manager.dart';
import 'package:asmr_hub/services/live_stream_url.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/services/mpv_player_engine.dart';
import 'package:asmr_hub/services/preferences_service.dart';

/// Audio playback state
enum PlaybackState { stopped, playing, paused, buffering, error }

/// Loop mode
enum LoopMode { off, all, one }

/// Audio player provider.
///
/// The heavy lifting (decoding, buffering, seeking, live HLS/FLV, custom
/// HTTP headers) is delegated to [MpvPlayerEngine] (libmpv). This class
/// owns the app-level playback model: track routing, playlist, loop/shuffle,
/// live-card heartbeat, sleep timer and persisted state.
class AudioPlayerProvider extends ChangeNotifier {
  final AudioSourceManager _sourceManager = AudioSourceManager();
  final MpvPlayerEngine _engine = MpvPlayerEngine();

  // Playback state
  PlaybackState _playbackState = PlaybackState.stopped;
  AudioTrack? _currentTrack;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;
  bool _isMuted = false;
  double _previousVolume = 1.0;
  bool _hasUserInteracted = false;
  bool _isInitializing = false;
  Timer? _positionTicker;
  int _autoSaveCounter = 0;

  // Playlist
  List<AudioTrack> _currentPlaylist = [];
  int _currentIndex = 0;
  bool _isShuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;

  // Live streaming
  bool _liveMode = false;

  /// Saved playback position restored on startup; applied on first play.
  Duration? _resumePosition;

  /// Title of the live-card track whose room was offline when [play] was
  /// attempted (set instead of starting playback). The UI shows a snackbar
  /// and calls [clearLiveBlocked].
  String? _liveBlockedTitle;

  String? get liveBlockedTitle => _liveBlockedTitle;

  void clearLiveBlocked() {
    if (_liveBlockedTitle != null) {
      _liveBlockedTitle = null;
      notifyListeners();
    }
  }

  /// Live-card heartbeat: caches online/offline state of every live-card
  /// track (keyed by track id) and auto-plays the current live-card when its
  /// room comes online.
  final Map<String, bool> _liveCardOnline = {};
  Timer? _liveHeartbeat;
  static const Duration _liveHeartbeatInterval = Duration(seconds: 30);

  bool isLiveCardOnline(String trackId) => _liveCardOnline[trackId] ?? false;

  /// Whether a live stream is actually active (a live-card track that was
  /// blocked because the room was offline does not count).
  bool get isLiveActive => _liveMode && _playbackState == PlaybackState.playing;

  // Sleep timer
  Timer? _sleepTimer;
  DateTime? _sleepTimerEndTime;
  Duration? _sleepTimerDuration;

  // Getters
  PlaybackState get playbackState => _playbackState;
  AudioTrack? get currentTrack => _currentTrack;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  bool get isMuted => _isMuted;
  bool get isPlaying => _playbackState == PlaybackState.playing;
  bool get isPaused => _playbackState == PlaybackState.paused;

  List<AudioTrack> get currentPlaylist => List.unmodifiable(_currentPlaylist);
  int get currentIndex => _currentIndex;
  bool get isShuffleEnabled => _isShuffleEnabled;
  LoopMode get loopMode => _loopMode;

  bool get isSleepTimerActive => _sleepTimer != null && _sleepTimer!.isActive;
  Duration? get sleepTimerRemaining {
    if (_sleepTimerEndTime == null) return null;
    final remaining = _sleepTimerEndTime!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration? get sleepTimerDuration => _sleepTimerDuration;
  DateTime? get sleepTimerEndTime => _sleepTimerEndTime;

  String get quality => PreferencesService().getAudioQuality();

  static const String _prefsKeyPlaylist = 'audio_player_playlist';
  static const String _prefsKeyIndex = 'audio_player_index';
  static const String _prefsKeyPosition = 'audio_player_position';
  static const String _prefsKeyVolume = 'audio_player_volume';
  static const String _prefsKeyShuffle = 'audio_player_shuffle';
  static const String _prefsKeyLoopMode = 'audio_player_loop_mode';

  /// Initialize
  Future<void> initialize() async {
    if (_isInitializing) return;
    _isInitializing = true;

    await _sourceManager.initialize();

    // Wire engine events.
    _engine.onPositionChanged = _onEnginePosition;
    _engine.onDurationChanged = _onEngineDuration;
    _engine.onPlaybackStateChanged = _onEnginePlayback;
    _engine.onCompleted = _onEngineCompleted;

    await loadState();

    // Start position ticker (drives the 5 s auto-save and UI clock).
    _positionTicker?.cancel();
    _autoSaveCounter = 0;
    _positionTicker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _autoSaveCounter++;
      if (_autoSaveCounter >= 50) {
        _autoSaveCounter = 0;
        unawaited(saveState());
      }
    });

    _startLiveHeartbeat();

    _isInitializing = false;
  }

  void _onEnginePosition() {
    _position = _engine.position;
    notifyListeners();
  }

  void _onEngineDuration() {
    _duration = _engine.duration;
    notifyListeners();
  }

  void _onEnginePlayback() {
    // Map engine state to our model: buffering while opening, playing when
    // the engine is playing, paused otherwise.
    if (_engine.isBuffering) {
      if (_playbackState != PlaybackState.paused) {
        _setPlaybackState(PlaybackState.buffering);
      }
    } else if (_engine.isPlaying) {
      _setPlaybackState(PlaybackState.playing);
    } else if (_engine.isPaused) {
      _setPlaybackState(PlaybackState.paused);
    } else if (_playbackState == PlaybackState.playing ||
        _playbackState == PlaybackState.buffering) {
      // Engine stopped unexpectedly.
      _setPlaybackState(PlaybackState.stopped);
    }
  }

  void _onEngineCompleted() {
    _engine.resetCompleted();
    _onTrackFinished();
  }

  void _onTrackFinished() {
    if (_loopMode == LoopMode.one) {
      play(_currentTrack);
    } else {
      playNext(autoPlay: true);
    }
  }

  /// Applies an mpv audio filter chain (lavfi) from the effects provider.
  Future<void> setAudioFilter(String? chain) => _engine.setAudioFilter(chain);

  /// Play audio
  Future<void> play([AudioTrack? track]) async {
    _hasUserInteracted = true;
    LogService().info(
      'play() called: track=${track?.title ?? '(resume)'} '
      'id=${track?.id ?? '-'}',
    );
    try {
      if (track != null) {
        // Live-card tracks: verify the room is streaming before playing.
        if (track.metadata?['isLiveCard'] == true) {
          final roomId = track.metadata?['roomId']?.toString() ?? track.id;
          if (roomId.isNotEmpty) {
            try {
              final source = _liveSourceFor(track.sourceTypeId);
              final live = source == null
                  ? true
                  : await source.isRoomLive(roomId);
              if (!live) {
                _liveBlockedTitle = track.title;
                LogService().warning(
                  'Live room offline, blocked playback: $roomId',
                );
                notifyListeners();
                return;
              }
            } catch (e) {
              LogService().warning(
                'Live status check failed, allowing playback: $e',
              );
            }
          }
        }

        _currentTrack = track;

        final index = _currentPlaylist.indexWhere((t) => t.id == track.id);
        if (index != -1) {
          _currentIndex = index;
        }

        await stop();

        // Prefer a downloaded file when one exists (no network, no decode).
        final isLiveCard = track.metadata?['isLiveCard'] == true;
        if (!isLiveCard) {
          final localFile = await AudioCache.downloadedFileFor(track);
          if (localFile != null) {
            LogService().info('play: using downloaded file: $localFile');
            await _openUrl(localFile, track, isLive: false);
            await _applyResumePosition(track);
            return;
          }
        }

        // Resolve the network stream URL + headers.
        final streamUrl = await LiveStreamUrl.resolve(_sourceManager, track);
        LogService().info(
          'streamUrl: $streamUrl '
          '(source=${track.sourceTypeId}, '
          'isLive=${track.metadata?['isLive'] == true}, '
          'duration=${track.duration.inSeconds}s)',
        );

        final isLive =
            track.metadata?['isLive'] == true ||
            streamUrl.endsWith('.m3u8') ||
            streamUrl.contains('.flv') ||
            track.metadata?['isLiveCard'] == true;

        final headers = LiveStreamUrl.headersFor(track);
        _liveMode = isLive;
        _duration = isLive ? Duration.zero : track.duration;

        _setPlaybackState(PlaybackState.buffering);
        await _openUrl(streamUrl, track, isLive: isLive, headers: headers);
        await _applyResumePosition(track);
        return;
      }

      // Resume: engine already has the current media loaded.
      if (_engine.isPlaying) {
        _setPlaybackState(PlaybackState.playing);
        return;
      }
      if (_currentTrack != null) {
        await _engine.play();
        _setPlaybackState(PlaybackState.playing);
        return;
      }
      // Nothing loaded: replay current track if available.
      if (_currentTrack != null) {
        await play(_currentTrack);
      }
    } catch (e, stack) {
      _setPlaybackState(PlaybackState.error);
      LogService().error('Playback failed', e, stack);
    }
  }

  /// Opens [url] in the mpv engine.
  Future<void> _openUrl(
    String url,
    AudioTrack? track, {
    bool isLive = false,
    Map<String, String>? headers,
  }) async {
    await _engine.open(url, headers: headers);
    await _engine.setVolume(_isMuted ? 0 : _volume);
    if (isLive) {
      _setPlaybackState(PlaybackState.playing);
    }
  }

  /// Applies the position restored from the previous session.
  Future<void> _applyResumePosition(AudioTrack? track) async {
    final pos = _resumePosition;
    if (pos == null || pos <= Duration.zero) return;
    if (track != null &&
        _currentTrack != null &&
        track.id != _currentTrack!.id) {
      _resumePosition = null;
      return;
    }
    _resumePosition = null;
    if (_liveMode) return; // live streams cannot seek
    try {
      await _engine.seek(pos);
    } catch (_) {}
    _position = pos;
    notifyListeners();
  }

  /// Switches audio quality for the current on-demand track.
  Future<void> replayWithQuality(String quality) async {
    await PreferencesService().setAudioQuality(quality);
    final track = _currentTrack;
    if (track == null) return;
    if (track.metadata?['isLiveCard'] == true ||
        track.metadata?['isLive'] == true) {
      return; // live: quality is not applicable
    }
    final pos = _position;
    _resumePosition = pos;
    await play(track);
  }

  /// Pause playback
  Future<void> pause() async {
    await _engine.pause();
    _setPlaybackState(PlaybackState.paused);
  }

  /// Stop playback
  Future<void> stop() async {
    _liveMode = false;
    await _engine.stop();
    _position = Duration.zero;
    _setPlaybackState(PlaybackState.stopped);
    notifyListeners();
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    if (_liveMode) return; // live streams can't seek
    await _engine.seek(position);
    _position = position;
    notifyListeners();
  }

  /// Set volume
  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    if (_volume > 0) {
      _isMuted = false;
      _previousVolume = _volume;
    }
    _engine.setVolume(_volume);
    notifyListeners();
  }

  /// Toggle mute
  void toggleMute() {
    _isMuted = !_isMuted;
    if (_isMuted) {
      _previousVolume = _volume;
      _volume = 0;
    } else {
      _volume = _previousVolume;
      if (_volume == 0) _volume = 0.5;
    }
    _engine.setVolume(_volume);
    notifyListeners();
  }

  /// Play next
  Future<void> playNext({bool autoPlay = false}) async {
    if (_currentPlaylist.isEmpty) return;

    if (_isShuffleEnabled) {
      _currentIndex =
          (DateTime.now().millisecondsSinceEpoch % _currentPlaylist.length);
    } else {
      if (autoPlay &&
          _loopMode == LoopMode.off &&
          _currentIndex == _currentPlaylist.length - 1) {
        await stop();
        return;
      }
      _currentIndex = (_currentIndex + 1) % _currentPlaylist.length;
    }

    await play(_currentPlaylist[_currentIndex]);
  }

  /// Play previous
  Future<void> playPrevious() async {
    if (_currentPlaylist.isEmpty) return;

    if (_isShuffleEnabled) {
      _currentIndex =
          (DateTime.now().millisecondsSinceEpoch % _currentPlaylist.length);
    } else {
      _currentIndex = _currentIndex > 0
          ? _currentIndex - 1
          : _currentPlaylist.length - 1;
    }

    await play(_currentPlaylist[_currentIndex]);
  }

  /// Set playlist
  void setPlaylist(List<AudioTrack> playlist, {int startIndex = 0}) {
    _hasUserInteracted = true;
    _currentPlaylist = playlist;
    _currentIndex = startIndex.clamp(0, playlist.length - 1);
    notifyListeners();
  }

  /// Add to playlist
  void addToPlaylist(AudioTrack track) {
    _hasUserInteracted = true;
    _currentPlaylist.add(track);
    notifyListeners();
  }

  /// Remove from playlist
  void removeFromPlaylist(int index) {
    _hasUserInteracted = true;
    if (index >= 0 && index < _currentPlaylist.length) {
      _currentPlaylist.removeAt(index);
      if (_currentIndex >= _currentPlaylist.length) {
        _currentIndex = _currentPlaylist.length - 1;
      }
      notifyListeners();
    }
  }

  /// Clear playlist
  void clearPlaylist() {
    _hasUserInteracted = true;
    _currentPlaylist.clear();
    _currentIndex = 0;
    stop(); // Fire and forget
    _currentTrack = null;
    notifyListeners();
  }

  /// Toggle shuffle
  void toggleShuffle() {
    _isShuffleEnabled = !_isShuffleEnabled;
    notifyListeners();
  }

  /// Toggle loop mode
  void toggleLoopMode() {
    switch (_loopMode) {
      case LoopMode.off:
        _loopMode = LoopMode.all;
        break;
      case LoopMode.all:
        _loopMode = LoopMode.one;
        break;
      case LoopMode.one:
        _loopMode = LoopMode.off;
        break;
    }
    notifyListeners();
  }

  /// Set sleep timer
  void setSleepTimer(Duration duration) {
    cancelSleepTimer();
    _sleepTimerDuration = duration;
    _sleepTimerEndTime = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () async {
      // Stop playback when the timer fires; keep the app running.
      await stop();
      _setPlaybackState(PlaybackState.stopped);
      notifyListeners();
    });
    notifyListeners();
  }

  /// Cancel sleep timer
  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEndTime = null;
    _sleepTimerDuration = null;
    notifyListeners();
  }

  /// Checks every live-card track in the playlist against the source's live
  /// status, and auto-plays the current live-card once its room is online.
  Future<void> checkLiveCards() async {
    final liveTracks = <AudioTrack>[];
    for (final t in _currentPlaylist) {
      if (t.metadata?['isLiveCard'] == true || t.metadata?['isLive'] == true) {
        liveTracks.add(t);
      }
    }
    final cur = _currentTrack;
    if (cur != null &&
        (cur.metadata?['isLiveCard'] == true ||
            cur.metadata?['isLive'] == true) &&
        !liveTracks.any((t) => t.id == cur.id)) {
      liveTracks.add(cur);
    }
    if (liveTracks.isEmpty) return;

    var changed = false;
    for (final t in liveTracks) {
      final roomId = t.metadata?['roomId']?.toString() ?? t.id;
      if (roomId.isEmpty) continue;
      final source = _liveSourceFor(t.sourceTypeId);
      if (source == null) continue;
      bool online;
      try {
        online = await source.isRoomLive(roomId);
      } catch (e) {
        LogService().warning('Live check failed for $roomId: $e');
        continue;
      }
      if (_liveCardOnline[t.id] != online) {
        _liveCardOnline[t.id] = online;
        changed = true;
        LogService().info(
          'Live heartbeat: ${t.title} ${online ? 'ONLINE' : 'OFFLINE'}',
        );
        if (online &&
            cur != null &&
            cur.id == t.id &&
            _playbackState != PlaybackState.playing &&
            _playbackState != PlaybackState.paused &&
            _playbackState != PlaybackState.buffering) {
          LogService().info('Live heartbeat: auto-playing ${t.title}');
          unawaited(play(t));
        }
      }
    }
    if (changed) notifyListeners();
  }

  void _startLiveHeartbeat() {
    _liveHeartbeat?.cancel();
    _liveHeartbeat = Timer.periodic(
      _liveHeartbeatInterval,
      (_) => unawaited(checkLiveCards()),
    );
    unawaited(checkLiveCards());
  }

  /// Save playback state
  Future<void> saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (_currentPlaylist.isNotEmpty) {
        final playlistJson = jsonEncode(
          _currentPlaylist.map((t) => t.toJson()).toList(),
        );
        await prefs.setString(_prefsKeyPlaylist, playlistJson);
      } else {
        await prefs.remove(_prefsKeyPlaylist);
      }

      await prefs.setInt(_prefsKeyIndex, _currentIndex);
      await prefs.setInt(_prefsKeyPosition, _position.inMilliseconds);
      await prefs.setDouble(_prefsKeyVolume, _volume);
      await prefs.setBool(_prefsKeyShuffle, _isShuffleEnabled);
      await prefs.setInt(_prefsKeyLoopMode, _loopMode.index);
    } catch (e, stack) {
      LogService().error('Failed to save playback state', e, stack);
    }
  }

  /// Load playback state
  Future<void> loadState() async {
    if (_hasUserInteracted) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      if (_hasUserInteracted) return;

      if (prefs.containsKey(_prefsKeyVolume)) {
        _volume = prefs.getDouble(_prefsKeyVolume) ?? 1.0;
      }

      _isShuffleEnabled = prefs.getBool(_prefsKeyShuffle) ?? false;
      final loopModeIndex = prefs.getInt(_prefsKeyLoopMode) ?? 0;
      if (loopModeIndex >= 0 && loopModeIndex < LoopMode.values.length) {
        _loopMode = LoopMode.values[loopModeIndex];
      }

      final playlistJson = prefs.getString(_prefsKeyPlaylist);
      if (playlistJson != null) {
        try {
          final List<dynamic> decoded = jsonDecode(playlistJson);
          _currentPlaylist = decoded
              .map((json) => AudioTrack.fromJson(json))
              .toList();

          _currentIndex = prefs.getInt(_prefsKeyIndex) ?? 0;
          if (_currentIndex < 0 || _currentIndex >= _currentPlaylist.length) {
            _currentIndex = 0;
          }

          final positionMs = prefs.getInt(_prefsKeyPosition) ?? 0;
          final savedPosition = Duration(milliseconds: positionMs);

          if (_currentPlaylist.isNotEmpty) {
            if (_hasUserInteracted) return;

            _currentTrack = _currentPlaylist[_currentIndex];

            // Restore as a paused display state; actual loading happens on
            // play(). Live-card tracks and network/decoded sources simply
            // remember the resume position.
            _position = savedPosition;
            _duration = _currentTrack!.duration;
            _resumePosition = savedPosition;
            _setPlaybackState(PlaybackState.paused);
            notifyListeners();
          }
        } catch (e) {
          LogService().error('Failed to load playlist', e, StackTrace.current);
        }
      }
      notifyListeners();
    } catch (e, stack) {
      LogService().error('Failed to load playback state', e, stack);
    }
  }

  /// Set playback state
  void _setPlaybackState(PlaybackState state) {
    _playbackState = state;
    notifyListeners();
  }

  /// The source registered under [sourceTypeId], or null.
  source_api.AudioSource? _liveSourceFor(String sourceTypeId) {
    for (final s in _sourceManager.getSources()) {
      if (s.sourceTypeId == sourceTypeId) return s;
    }
    return null;
  }

  /// Shutdown player and release resources
  Future<void> shutdown() async {
    _positionTicker?.cancel();
    _liveHeartbeat?.cancel();
    _sleepTimer?.cancel();
    try {
      await _engine.dispose().timeout(const Duration(seconds: 2));
    } catch (_) {
      // ignore timeout/error
    }
  }

  @override
  void dispose() {
    _positionTicker?.cancel();
    _liveHeartbeat?.cancel();
    _sleepTimer?.cancel();
    _engine.dispose();
    _sourceManager.dispose();
    super.dispose();
  }
}

/// Audio source provider
class AudioSourceProvider extends ChangeNotifier {
  final AudioSourceManager _sourceManager = AudioSourceManager();

  List<AudioTrack> _searchResults = [];
  String _lastQuery = '';
  Map<String, bool> _sourceAvailability = {};

  // Getters
  List<AudioTrack> get searchResults => List.unmodifiable(_searchResults);
  bool get isSearching => false;
  String get lastQuery => _lastQuery;
  Map<String, bool> get sourceAvailability =>
      Map.unmodifiable(_sourceAvailability);

  /// Initialize
  Future<void> initialize() async {
    await _sourceManager.initialize();
    await checkSourcesAvailability();
  }

  /// Parse URL
  Future<AudioTrack?> parseUrl(String url) async {
    try {
      return await _sourceManager.parseUrl(url);
    } catch (e, stack) {
      LogService().error('Failed to parse URL', e, stack);
      return null;
    }
  }

  /// Download audio
  Future<void> download(AudioTrack track) async {
    try {
      await _sourceManager.download(track);
    } catch (e, stack) {
      LogService().error('Failed to download audio', e, stack);
      rethrow;
    }
  }

  /// Get playlist
  Future<List<AudioTrack>> getPlaylist(String url) async {
    try {
      return await _sourceManager.getPlaylist(url);
    } catch (e, stack) {
      LogService().error('Failed to get playlist', e, stack);
      return [];
    }
  }

  /// Get recommendations
  Future<List<AudioTrack>> getRecommendations() async {
    try {
      return await _sourceManager.getRecommendations();
    } catch (e, stack) {
      LogService().error('Failed to get recommendations', e, stack);
      return [];
    }
  }

  /// Check audio source availability
  Future<void> checkSourcesAvailability() async {
    try {
      _sourceAvailability = await _sourceManager.checkSourcesAvailability();
      notifyListeners();
    } catch (e, stack) {
      LogService().error('Failed to check audio source availability', e, stack);
    }
  }

  /// Clear search results
  void clearSearchResults() {
    _searchResults = [];
    _lastQuery = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _sourceManager.dispose();
    super.dispose();
  }
}
