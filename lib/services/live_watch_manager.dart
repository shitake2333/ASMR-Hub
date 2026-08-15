import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/audio_source.dart';
import 'package:asmr_hub/services/audio_source_manager.dart';
import 'package:asmr_hub/services/live_recorder.dart';
import 'package:asmr_hub/services/log_service.dart';

/// A live room being monitored for background recording.
class LiveWatchRoom {
  final String sourceTypeId;
  final String roomId;
  String title;
  bool enabled;

  /// When the current stream started (null when offline / unknown).
  DateTime? liveSince;

  /// When the current recording of this room started.
  DateTime? recordingSince;

  LiveWatchRoom({
    required this.sourceTypeId,
    required this.roomId,
    required this.title,
    this.enabled = true,
    this.liveSince,
    this.recordingSince,
  });

  String get key => '$sourceTypeId:$roomId';

  bool get isRecording => LiveRecorder().isRecordingKey(key);

  Map<String, dynamic> toJson() => {
    'sourceTypeId': sourceTypeId,
    'roomId': roomId,
    'title': title,
    'enabled': enabled,
  };

  factory LiveWatchRoom.fromJson(Map<String, dynamic> json) => LiveWatchRoom(
    sourceTypeId: json['sourceTypeId']?.toString() ?? 'bilibili',
    roomId: json['roomId']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    enabled: json['enabled'] != false,
  );
}

/// Background live-room watchdog.
///
/// Monitors a list of live rooms (persisted in preferences). Every few
/// minutes it probes each enabled room: when the room goes live and is not
/// recording yet, recording starts automatically; when the room goes
/// offline, the recording stops. Playback is not required.
class LiveWatchManager extends ChangeNotifier {
  static final LiveWatchManager instance = LiveWatchManager._();
  LiveWatchManager._();

  static const String _prefsKey = 'live_watch_rooms_v1';
  static const Duration _checkInterval = Duration(minutes: 3);

  final LogService _logger = LogService();
  final List<LiveWatchRoom> _rooms = [];
  Timer? _timer;
  bool _checking = false;

  List<LiveWatchRoom> get rooms => List.unmodifiable(_rooms);

  /// Loads persisted rooms and starts the watchdog.
  Future<void> start() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        _rooms
          ..clear()
          ..addAll(
            list
                .map((e) => LiveWatchRoom.fromJson(e as Map<String, dynamic>))
                .where((r) => r.roomId.isNotEmpty),
          );
      }
    } catch (e) {
      _logger.warning('Failed to load live watch rooms: $e');
    }
    _timer?.cancel();
    _timer = Timer.periodic(_checkInterval, (_) => unawaited(checkAll()));
    unawaited(checkAll());
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(_rooms.map((r) => r.toJson()).toList()),
      );
    } catch (e) {
      _logger.warning('Failed to save live watch rooms: $e');
    }
  }

  /// Adds a room by URL (detects the source from the URL). Returns the room
  /// or null when the URL is not a supported live room.
  Future<LiveWatchRoom?> addRoomByUrl(String url) async {
    final manager = AudioSourceManager();
    LiveWatchRoom? room;
    if (url.contains('bilibili.com')) {
      final bili = manager
          .getSources()
          .where((s) => s.sourceTypeId == 'bilibili')
          .firstOrNull;
      if (bili == null) return null;
      final scraper = (bili as dynamic).scraper;
      final roomId = scraper.extractLiveRoomId(url)?.toString();
      if (roomId != null) {
        room = LiveWatchRoom(
          sourceTypeId: 'bilibili',
          roomId: roomId,
          title: 'Bilibili Live $roomId',
        );
      }
    } else if (url.contains('douyu.com') || url.contains('douyutv.com')) {
      final douyu = manager
          .getSources()
          .where((s) => s.sourceTypeId == 'douyu')
          .firstOrNull;
      if (douyu == null) return null;
      final scraper = (douyu as dynamic).scraper;
      final roomId = await scraper.resolveRoomId(url);
      if (roomId != null) {
        room = LiveWatchRoom(
          sourceTypeId: 'douyu',
          roomId: roomId,
          title: 'Douyu Live $roomId',
        );
      }
    }
    if (room == null) return null;
    // Avoid duplicates.
    _rooms.removeWhere((r) => r.key == room!.key);
    _rooms.add(room);
    notifyListeners();
    await _save();
    unawaited(_checkRoom(room));
    return room;
  }

  /// Adds a room by live-card track (used by the record buttons in the live
  /// room UI and the player). Recording starts immediately when the room is
  /// online; otherwise the room is watched until it goes live.
  Future<LiveWatchRoom?> addRoomByTrack(AudioTrack track) async {
    final roomId = track.metadata?['roomId']?.toString() ?? track.id;
    if (roomId.isEmpty) return null;
    final room = LiveWatchRoom(
      sourceTypeId: track.sourceTypeId,
      roomId: roomId,
      title: track.title,
      enabled: true,
    );
    _rooms.removeWhere((r) => r.key == room.key);
    _rooms.add(room);
    notifyListeners();
    await _save();
    unawaited(_checkRoom(room));
    return room;
  }

  /// The watched room for a live-card track, if any.
  LiveWatchRoom? roomForTrack(AudioTrack track) {
    final roomId = track.metadata?['roomId']?.toString() ?? track.id;
    for (final r in _rooms) {
      if (r.sourceTypeId == track.sourceTypeId && r.roomId == roomId) {
        return r;
      }
    }
    return null;
  }

  /// Toggles recording for a live-card track: starts watching (and records
  /// right away when online), or stops the recording and watching.
  Future<void> toggleForTrack(AudioTrack track) async {
    final existing = roomForTrack(track);
    if (existing != null) {
      existing.enabled = !existing.enabled;
      if (!existing.enabled) {
        await LiveRecorder().stop(existing.key);
        existing.recordingSince = null;
      } else {
        notifyListeners();
        unawaited(_checkRoom(existing));
      }
      notifyListeners();
      await _save();
      return;
    }
    await addRoomByTrack(track);
  }

  /// Removes a watched room by its session key.
  Future<void> removeRoomByKey(String key) async {
    final index = _rooms.indexWhere((r) => r.key == key);
    if (index >= 0) {
      await removeRoom(index);
    }
  }

  Future<void> removeRoom(int index) async {
    if (index < 0 || index >= _rooms.length) return;
    final room = _rooms[index];
    // Stop any in-progress recording of this room.
    await LiveRecorder().stop(room.key);
    _rooms.removeAt(index);
    notifyListeners();
    await _save();
  }

  Future<void> toggleEnabled(int index) async {
    if (index < 0 || index >= _rooms.length) return;
    final room = _rooms[index];
    room.enabled = !room.enabled;
    if (!room.enabled) {
      await LiveRecorder().stop(room.key);
    }
    notifyListeners();
    await _save();
  }

  /// Probes every enabled room and starts/stops recordings accordingly.
  Future<void> checkAll() async {
    if (_checking) return;
    _checking = true;
    try {
      for (final room in _rooms) {
        if (!room.enabled) continue;
        await _checkRoom(room);
      }
    } finally {
      _checking = false;
    }
  }

  /// Rooms whose [_checkRoom] is currently running (prevents concurrent
  /// checks of the same room from double-starting a recording).
  final Set<String> _checkingRooms = {};

  Future<void> _checkRoom(LiveWatchRoom room) async {
    // Skip if another check of this room is already in flight.
    if (!_checkingRooms.add(room.key)) return;
    try {
      await _checkRoomInner(room);
    } finally {
      _checkingRooms.remove(room.key);
    }
  }

  Future<void> _checkRoomInner(LiveWatchRoom room) async {
    final manager = AudioSourceManager();
    AudioSource? source;
    for (final s in manager.getSources()) {
      if (s.sourceTypeId == room.sourceTypeId) {
        source = s;
        break;
      }
    }
    if (source == null || !source.supportsLiveRecording) return;

    try {
      final live = await source.isRoomLive(room.roomId);
      if (live) {
        // Refresh the title from the room info when possible.
        try {
          final track = await source.parseFromUrl(
            '${room.sourceTypeId == 'bilibili' ? 'https://live.bilibili.com' : 'https://www.douyu.com'}/'
            '${room.roomId}',
          );
          if (track != null && track.title.isNotEmpty) {
            room.title = track.title;
          }
        } catch (_) {
          // keep existing title
        }
        // Track when the stream started (polling granularity is fine).
        room.liveSince ??= DateTime.now();
        if (!room.isRecording) {
          final ok = await source.startRecording(
            AudioTrack(
              id: room.roomId,
              title: room.title,
              artist: source.sourceName,
              duration: Duration.zero,
              streamUrl: '',
              sourceTypeId: room.sourceTypeId,
              metadata: {
                'isLive': true,
                'isLiveCard': true,
                'roomId': room.roomId,
              },
            ),
          );
          if (ok) {
            room.recordingSince = DateTime.now();
            _logger.info(
              'Watchdog: started recording ${room.sourceTypeId} room ${room.roomId}',
            );
          } else {
            _logger.warning(
              'Watchdog: failed to start recording for ${room.key}',
            );
          }
        }
      } else {
        room.liveSince = null;
        if (room.isRecording) {
          // Room went offline: stop this room's recording.
          await LiveRecorder().stop(room.key);
          room.recordingSince = null;
          _logger.info(
            'Watchdog: room ${room.roomId} offline, recording stopped',
          );
        }
      }
      notifyListeners();
    } catch (e) {
      _logger.warning('Watchdog check failed for ${room.key}: $e');
    }
  }
}
