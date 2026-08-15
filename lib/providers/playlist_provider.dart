import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/audio_storage_service.dart';
import 'package:asmr_hub/services/log_service.dart';

class PlaylistProvider extends ChangeNotifier {
  final AudioStorageService _storageService = AudioStorageService();
  List<Playlist> _playlists = [];
  bool _isLoading = false;

  List<Playlist> get playlists => List.unmodifiable(_playlists);
  bool get isLoading => _isLoading;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      _playlists = await _storageService.loadCustomPlaylists();
    } catch (e, stack) {
      LogService().error('Error loading playlists', e, stack);
      _playlists = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> createPlaylist(String name, {String? description}) async {
    final newPlaylist = Playlist(
      id: const Uuid().v4(),
      name: name,
      description: description,
      tracks: [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _playlists.add(newPlaylist);
    await _savePlaylists();
    notifyListeners();
  }

  Future<void> deletePlaylist(String id) async {
    _playlists.removeWhere((p) => p.id == id);
    await _savePlaylists();
    notifyListeners();
  }

  Future<void> addTrackToPlaylist(String playlistId, AudioTrack track) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _playlists[index];
      // Check if track already exists
      if (!playlist.tracks.any((t) => t.id == track.id)) {
        final updatedTracks = List<AudioTrack>.from(playlist.tracks)
          ..add(track);
        _playlists[index] = Playlist(
          id: playlist.id,
          name: playlist.name,
          description: playlist.description,
          coverArt:
              playlist.coverArt ??
              track.albumArt, // Use first track art as cover if none
          tracks: updatedTracks,
          createdAt: playlist.createdAt,
          updatedAt: DateTime.now(),
        );
        await _savePlaylists();
        notifyListeners();
      }
    }
  }

  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackId,
  ) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final playlist = _playlists[index];
      final updatedTracks = List<AudioTrack>.from(playlist.tracks)
        ..removeWhere((t) => t.id == trackId);

      _playlists[index] = Playlist(
        id: playlist.id,
        name: playlist.name,
        description: playlist.description,
        coverArt: updatedTracks.isEmpty
            ? null
            : (playlist.coverArt ?? updatedTracks.first.albumArt),
        tracks: updatedTracks,
        createdAt: playlist.createdAt,
        updatedAt: DateTime.now(),
      );
      await _savePlaylists();
      notifyListeners();
    }
  }

  Future<void> _savePlaylists() async {
    await _storageService.saveCustomPlaylists(_playlists);
  }
}
