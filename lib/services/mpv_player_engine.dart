import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'package:asmr_hub/services/log_service.dart';

/// Thin wrapper around media_kit's [Player] (libmpv) that adapts it to the
/// app's playback model.
///
/// The native [Player] is created lazily on the first [open] so that
/// constructing this engine never fails (e.g. in widget tests where libmpv
/// is unavailable). If the native library cannot be loaded, the engine
/// becomes a silent no-op ([isAvailable] == false).
class MpvPlayerEngine {
  Player? _player;
  bool _available = false;
  StreamSubscription? _playingSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _completedSub;
  StreamSubscription? _bufferingSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _logSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _completed = false;
  bool _paused = false;
  String? _error;

  /// Callbacks wired by the provider.
  void Function()? onPositionChanged;
  void Function()? onDurationChanged;
  void Function()? onPlaybackStateChanged;
  void Function()? onCompleted;

  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _playing && !_paused;
  bool get isBuffering => _buffering;
  bool get isPaused => _paused;
  bool get isCompleted => _completed;
  String? get error => _error;

  /// True when the native libmpv player is operational.
  bool get isAvailable => _available;

  /// Exposes the raw media_kit player platform (used by tests to read mpv
  /// properties). Null when the player has not been created.
  dynamic get platformForTest => _player?.platform;

  MpvPlayerEngine();

  /// Lazily creates the native player and wires its event streams. Returns
  /// false when libmpv is unavailable (e.g. headless tests).
  bool _ensurePlayer() {
    if (_player != null) return _available;
    try {
      final player = Player();
      _player = player;
      _available = true;

      _playingSub = player.stream.playing.listen((playing) {
        _playing = playing;
        onPlaybackStateChanged?.call();
      });
      _positionSub = player.stream.position.listen((pos) {
        _position = pos;
        onPositionChanged?.call();
      });
      _durationSub = player.stream.duration.listen((dur) {
        _duration = dur;
        onDurationChanged?.call();
      });
      _bufferingSub = player.stream.buffering.listen((b) {
        _buffering = b;
        onPlaybackStateChanged?.call();
      });
      _completedSub = player.stream.completed.listen((_) {
        _completed = true;
        onCompleted?.call();
      });
      _errorSub = player.stream.error.listen((e) {
        _error = e;
        LogService().error('[mpv] $e');
        onPlaybackStateChanged?.call();
      });
      _logSub = player.stream.log.listen((l) {
        final msg = l.prefix.isNotEmpty ? '${l.prefix}: ${l.text}' : l.text;
        LogService().info('[mpv] $msg');
      });
    } catch (e) {
      _available = false;
      _player = null;
      LogService().error('[mpv] libmpv unavailable', e);
    }
    return _available;
  }

  /// Opens [url] for playback. [headers] are sent with HTTP(S) requests
  /// (e.g. Bilibili Referer / Douyu cookie). [start] controls whether
  /// playback begins immediately (default true).
  Future<void> open(
    String url, {
    Map<String, String>? headers,
    bool start = true,
  }) async {
    if (!_ensurePlayer()) return;
    _completed = false;
    _error = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    await _player!.open(Media(url, httpHeaders: headers ?? {}), play: start);
    onPositionChanged?.call();
    onDurationChanged?.call();
    onPlaybackStateChanged?.call();
  }

  Future<void> play() async {
    if (!_ensurePlayer()) return;
    _paused = false;
    await _player!.play();
    onPlaybackStateChanged?.call();
  }

  Future<void> pause() async {
    if (!_ensurePlayer()) return;
    _paused = true;
    await _player!.pause();
    onPlaybackStateChanged?.call();
  }

  Future<void> stop() async {
    if (!_ensurePlayer()) return;
    _paused = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _completed = false;
    await _player!.stop();
    onPositionChanged?.call();
    onDurationChanged?.call();
    onPlaybackStateChanged?.call();
  }

  Future<void> seek(Duration position) async {
    if (!_ensurePlayer()) return;
    await _player!.seek(position);
    _position = position;
    onPositionChanged?.call();
  }

  Future<void> setVolume(double volume) async {
    if (!_ensurePlayer()) return;
    // media_kit's volume is 0-100 (mpv native); our model is 0-1.
    await _player!.setVolume(volume.clamp(0.0, 1.0) * 100.0);
  }

  Future<void> setRate(double rate) async {
    if (!_ensurePlayer()) return;
    await _player!.setRate(rate);
  }

  /// Applies an mpv audio filter chain (lavfi), e.g. for limiter/low-pass.
  Future<void> setAudioFilter(String? chain) async {
    if (!_ensurePlayer()) return;
    try {
      final p = _player!.platform;
      if (p == null) return;
      await (p as dynamic).setProperty('af', chain ?? '');
    } catch (e) {
      LogService().error('Failed to set mpv af filter: $chain', e);
    }
  }

  /// Resets a consumed "completed" flag (called before starting the next
  /// track so an old completion does not trigger playNext spuriously).
  void resetCompleted() {
    _completed = false;
  }

  Future<void> dispose() async {
    await _playingSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _completedSub?.cancel();
    await _bufferingSub?.cancel();
    await _errorSub?.cancel();
    await _logSub?.cancel();
    _playingSub = null;
    _positionSub = null;
    _durationSub = null;
    _completedSub = null;
    _bufferingSub = null;
    _errorSub = null;
    _logSub = null;
    final player = _player;
    _player = null;
    _available = false;
    if (player != null) {
      await player.dispose();
    }
  }
}
