import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/sources/asmrone/asmr_one_auth.dart';
import 'package:asmr_hub/sources/base/source_scraper.dart';

/// asmr.one scraper (api.asmr-200.com).
///
/// Works and their tracks are browsable anonymously; playlists require a
/// logged-in account (the playlist belongs to the user).
///
/// Endpoints:
///   work detail    GET /api/work/{id}
///   tracks         GET /api/tracks/{workId}
///   playlist       GET /api/playlist/get-playlist-works?id={uuid}  (auth)
///   media stream   mediaStreamUrl from a track (guest-accessible)
class AsmrOneScraper implements SourceScraper {
  static const String _api = 'https://api.asmr-200.com/api';

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// Extracts the playlist uuid from a URL, or null.
  String? extractPlaylistId(String url) {
    final m = RegExp(r'playlist[?&]id=([0-9a-fA-F-]{36})').firstMatch(url);
    return m?.group(1);
  }

  /// Fetches the logged-in user's playlists. Returns (id, name) tuples.
  /// Requires login (Authorization bearer token).
  Future<List<({String id, String name})>> fetchUserPlaylists() async {
    final result = <({String id, String name})>[];
    if (!AsmrOneAuth.instance.isLoggedIn) return result;
    try {
      final json = await _getJson(
        '/playlist/get-playlists',
        query: {'page': 1, 'pageSize': 100, 'filterBy': 'all'},
        auth: true,
      );
      final playlists = json['playlists'] as List<dynamic>? ?? [];
      for (final p in playlists) {
        if (p is! Map<String, dynamic>) continue;
        final id = p['id']?.toString() ?? '';
        final name = p['name']?.toString() ?? '';
        if (id.isNotEmpty && name.isNotEmpty) {
          result.add((id: id, name: name));
        }
      }
    } catch (e) {
      // The caller logs; return what we have.
      rethrow;
    }
    return result;
  }

  /// Extracts the work id from a URL (asmr.one/work/{id}), or null.
  int? extractWorkId(String url) {
    final m = RegExp(r'/work/(\d+)').firstMatch(url);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  Future<dynamic> _getJson(
    String path, {
    Map<String, dynamic>? query,
    bool auth = false,
  }) async {
    final uri = Uri.parse(
      '$_api$path',
    ).replace(queryParameters: query?.map((k, v) => MapEntry(k, v.toString())));
    final headers = <String, String>{
      'User-Agent': _ua,
      'Referer': 'https://asmr.one/',
      if (auth) ...AsmrOneAuth.instance.headers,
    };
    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('asmr.one API ${response.statusCode}: $path');
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  /// Fetches the track tree of a work and flattens it into playable tracks.
  Future<List<AudioTrack>> _workTracks(
    int workId, {
    String? workTitle,
    String? circleName,
    String? cover,
  }) async {
    final json = await _getJson('/tracks/$workId');
    final tree = (json is List)
        ? json
        : (json['tracks'] as List<dynamic>? ?? []);
    final tracks = <AudioTrack>[];
    _collectTracks(tree, workId, workTitle, circleName, cover, tracks);
    return tracks;
  }

  void _collectTracks(
    List<dynamic> nodes,
    int workId,
    String? workTitle,
    String? circleName,
    String? cover,
    List<AudioTrack> out,
  ) {
    for (final node in nodes) {
      if (node is! Map<String, dynamic>) continue;
      final type = node['type']?.toString() ?? '';
      if (type == 'folder') {
        _collectTracks(
          node['children'] as List<dynamic>? ?? [],
          workId,
          workTitle,
          circleName,
          cover,
          out,
        );
      } else if (type == 'audio') {
        final hash = node['hash']?.toString() ?? '';
        final title = node['title']?.toString() ?? '';
        final streamUrl = node['mediaStreamUrl']?.toString() ?? '';
        final durationMs = ((node['duration'] as num?) ?? 0) * 1000;
        if (hash.isEmpty) continue;
        // Skip video renditions (mp4); keep audio files only.
        if (!RegExp(
          r'\.(mp3|wav|flac|m4a|aac|ogg|opus)$',
          caseSensitive: false,
        ).hasMatch(title)) {
          continue;
        }
        out.add(
          AudioTrack(
            id: 'asmrone:$workId:$hash',
            title: title.isEmpty ? 'Track' : title,
            artist: circleName ?? 'asmr.one',
            albumArt: cover,
            duration: Duration(milliseconds: durationMs.round()),
            streamUrl: streamUrl,
            sourceTypeId: 'asmrone',
            metadata: {
              'workId': workId,
              'hash': hash,
              if (workTitle != null) 'workTitle': workTitle,
            },
          ),
        );
      }
    }
  }

  /// Fetches work metadata (title, circle, cover).
  Future<(String, String, String)> _workInfo(int workId) async {
    try {
      final json = await _getJson('/work/$workId');
      final d = json['work'] as Map<String, dynamic>? ?? json;
      return (
        d['title']?.toString() ?? '',
        d['name']?.toString() ?? '',
        d['cover']?.toString() ?? '',
      );
    } catch (_) {
      return ('', '', '');
    }
  }

  @override
  Future<List<AudioTrack>> scrapePlaylist(String url) async {
    final playlistId = extractPlaylistId(url);
    if (playlistId != null) {
      if (!AsmrOneAuth.instance.isLoggedIn) {
        throw Exception('asmr.one login required to open playlists');
      }
      // GET /api/playlist/get-playlist-works?id={uuid}&page=1&pageSize=N
      final json = await _getJson(
        '/playlist/get-playlist-works',
        query: {'id': playlistId, 'page': 1, 'pageSize': 100},
        auth: true,
      );
      final works = json['works'] as List<dynamic>? ?? [];
      final tracks = <AudioTrack>[];
      for (final w in works) {
        if (w is! Map<String, dynamic>) continue;
        final id = (w['id'] as num?)?.toInt();
        if (id == null) continue;
        final title = w['title']?.toString() ?? '';
        final cover = w['cover']?.toString() ?? '';
        final circle = w['name']?.toString() ?? '';
        tracks.addAll(
          await _workTracks(
            id,
            workTitle: title,
            circleName: circle,
            cover: cover,
          ),
        );
      }
      return tracks;
    }

    final workId = extractWorkId(url);
    if (workId != null) {
      final info = await _workInfo(workId);
      return _workTracks(
        workId,
        workTitle: info.$1,
        circleName: info.$2,
        cover: info.$3,
      );
    }
    throw Exception('Unrecognized asmr.one URL: $url');
  }

  @override
  Future<AudioTrack> scrapeVideo(String url) async {
    final workId = extractWorkId(url);
    if (workId == null) {
      throw Exception('Unrecognized asmr.one work URL: $url');
    }
    final info = await _workInfo(workId);
    return AudioTrack(
      id: 'asmrone:$workId',
      title: info.$1.isEmpty ? 'asmr.one Work $workId' : info.$1,
      artist: info.$2.isEmpty ? 'asmr.one' : info.$2,
      albumArt: info.$3.isEmpty ? null : info.$3,
      duration: Duration.zero,
      streamUrl: '',
      sourceTypeId: 'asmrone',
      metadata: {'workId': workId},
    );
  }

  @override
  Future<String> scrapeStreamUrl(String trackId, {String? quality}) async {
    // asmrone:{workId}:{hash} — resolve the mediaStreamUrl from the API.
    final parts = trackId.split(':');
    if (parts.length < 3 || parts[0] != 'asmrone') {
      throw Exception('Invalid asmr.one track id: $trackId');
    }
    final workId = int.tryParse(parts[1]);
    final hash = parts.sublist(2).join(':');
    if (workId == null) {
      throw Exception('Invalid asmr.one track id: $trackId');
    }
    final json = await _getJson('/tracks/$workId');
    final tree = (json is List)
        ? json
        : (json['tracks'] as List<dynamic>? ?? []);
    String? url;
    void find(List<dynamic> nodes) {
      for (final node in nodes) {
        if (node is! Map<String, dynamic>) continue;
        if (node['type'] == 'folder') {
          find(node['children'] as List<dynamic>? ?? []);
        } else if (node['type'] == 'audio' &&
            node['hash']?.toString() == hash) {
          url = node['mediaStreamUrl']?.toString();
          return;
        }
      }
    }

    find(tree);
    final result = url;
    if (result == null || result.isEmpty) {
      throw Exception('Track not found: $trackId');
    }
    return result;
  }
}
