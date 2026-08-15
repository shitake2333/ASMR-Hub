import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:asmr_hub/models/asmr_source.dart';
import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/log_service.dart';

class AudioStorageService {
  static const String _playlistFileName = 'playlist_cache.json';
  static const String _customPlaylistsFileName = 'custom_playlists.json';
  static const String _stateFileName = 'player_state_cache.json';
  static const String _sourcesFileName = 'asmr_sources.json';
  final LogService _logger = LogService();

  Future<String> get _localPath async {
    final directory = await getApplicationSupportDirectory();
    return directory.path;
  }

  Future<File> get _playlistFile async {
    final path = await _localPath;
    return File('$path/$_playlistFileName');
  }

  Future<File> get _customPlaylistsFile async {
    final path = await _localPath;
    return File('$path/$_customPlaylistsFileName');
  }

  Future<File> get _stateFile async {
    final path = await _localPath;
    return File('$path/$_stateFileName');
  }

  Future<File> get _sourcesFile async {
    final path = await _localPath;
    return File('$path/$_sourcesFileName');
  }

  /// Atomically writes [contents] to [file]: writes to a temp file in the
  /// same directory, then renames over the target. A crash mid-write leaves
  /// the previous file intact instead of a truncated one.
  Future<void> _atomicWrite(File file, String contents) async {
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(file.path);
  }

  Future<void> savePlaylist(List<Map<String, String>> playlist) async {
    try {
      final file = await _playlistFile;
      await _atomicWrite(file, jsonEncode(playlist));
    } catch (e, stack) {
      _logger.error('Error saving playlist', e, stack);
    }
  }

  Future<List<Map<String, String>>?> loadPlaylist() async {
    try {
      final file = await _playlistFile;
      if (!await file.exists()) return null;
      final contents = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(contents);
      return jsonList
          .whereType<Map<String, dynamic>>()
          .map((e) => e.map((k, v) => MapEntry(k, v?.toString() ?? '')))
          .toList();
    } catch (e, stack) {
      _logger.error('Error loading playlist', e, stack);
      return null;
    }
  }

  Future<void> saveCustomPlaylists(List<Playlist> playlists) async {
    try {
      final file = await _customPlaylistsFile;
      final jsonList = playlists.map((p) => p.toJson()).toList();
      await _atomicWrite(file, jsonEncode(jsonList));
    } catch (e, stack) {
      _logger.error('Error saving custom playlists', e, stack);
    }
  }

  Future<List<Playlist>> loadCustomPlaylists() async {
    try {
      final file = await _customPlaylistsFile;
      if (!await file.exists()) return [];
      final contents = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(contents);
      return jsonList.map((e) => Playlist.fromJson(e)).toList();
    } catch (e, stack) {
      _logger.error('Error loading custom playlists', e, stack);
      return [];
    }
  }

  Future<void> savePlayerState(Map<String, dynamic> state) async {
    try {
      final file = await _stateFile;
      await _atomicWrite(file, jsonEncode(state));
    } catch (e, stack) {
      _logger.error('Error saving player state', e, stack);
    }
  }

  Future<Map<String, dynamic>?> loadPlayerState() async {
    try {
      final file = await _stateFile;
      if (!await file.exists()) return null;
      final contents = await file.readAsString();
      return jsonDecode(contents) as Map<String, dynamic>;
    } catch (e, stack) {
      _logger.error('Error loading player state', e, stack);
      return null;
    }
  }

  Future<void> saveSources(List<ASMRSource> sources) async {
    try {
      final file = await _sourcesFile;
      final jsonList = sources.map((s) => s.toJson()).toList();
      await _atomicWrite(file, jsonEncode(jsonList));
    } catch (e, stack) {
      _logger.error('Error saving sources', e, stack);
    }
  }

  Future<List<ASMRSource>> loadSources() async {
    try {
      final file = await _sourcesFile;
      if (!await file.exists()) return [];
      final contents = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(contents);
      return jsonList.map((e) => ASMRSource.fromJson(e)).toList();
    } catch (e, stack) {
      _logger.error('Error loading sources', e, stack);
      return [];
    }
  }
}
