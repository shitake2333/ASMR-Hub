import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/audio_duration_probe.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/services/preferences_service.dart';
import 'package:asmr_hub/sources/base/source_scraper.dart';
import 'package:asmr_hub/sources/bilibili/bilibili_api.dart';

/// Bilibili URL types.
enum BilibiliUrlType {
  /// Single video: /video/BVxxx, av{id}
  video,

  /// UGC season (合集): /channel/collectiondetail?sid=, /list/ml{id}
  season,

  /// Favorite folder (收藏夹): /medialist/play/ml{id}, /favlist?fid=
  favorite,

  /// Live room: live.bilibili.com/{room}
  live,

  unknown,
}

class BilibiliScraper implements SourceScraper {
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  final BilibiliApi _api = BilibiliApi();
  final LogService _logger = LogService();

  // ------------------------------------------------------------ URL detect

  BilibiliUrlType detectUrlType(String url) {
    if (url.contains('live.bilibili.com')) return BilibiliUrlType.live;
    if (url.contains('/video/') ||
        RegExp(r'av\d+', caseSensitive: false).hasMatch(url)) {
      return BilibiliUrlType.video;
    }
    if (url.contains('collectiondetail') ||
        url.contains('/list/ml') ||
        url.contains('channel/collection') ||
        url.contains('/lists') ||
        RegExp(r'[?&]sid=\d+').hasMatch(url)) {
      return BilibiliUrlType.season;
    }
    if (url.contains('medialist/play/ml') ||
        url.contains('favlist') ||
        url.contains('medialist')) {
      return BilibiliUrlType.favorite;
    }
    return BilibiliUrlType.unknown;
  }

  /// Extracts the bvid (BV...) or av id from a video URL.
  String? extractVideoId(String url) {
    final bv = RegExp(r'BV[0-9A-Za-z]{10}').firstMatch(url);
    if (bv != null) return bv.group(0);
    final av = RegExp(r'av(\d+)', caseSensitive: false).firstMatch(url);
    if (av != null) return av.group(0)!;
    return null;
  }

  int? extractLiveRoomId(String url) {
    final m = RegExp(r'live\.bilibili\.com/(\d+)').firstMatch(url);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Extracts season id and owner mid from a season URL.
  ({int seasonId, int? mid})? extractSeason(String url) {
    final sid = RegExp(r'[?&]sid=(\d+)').firstMatch(url);
    if (sid != null) {
      final mid = RegExp(r'space\.bilibili\.com/(\d+)').firstMatch(url);
      return (
        seasonId: int.parse(sid.group(1)!),
        mid: mid == null ? null : int.tryParse(mid.group(1)!),
      );
    }
    final ml = RegExp(r'/list/ml(\d+)').firstMatch(url);
    if (ml != null) {
      return (seasonId: int.parse(ml.group(1)!), mid: null);
    }
    return null;
  }

  /// Extracts the favorite folder id.
  int? extractFavoriteId(String url) {
    final ml = RegExp(r'medialist/play/ml(\d+)').firstMatch(url);
    if (ml != null) return int.tryParse(ml.group(1)!);
    final fid = RegExp(r'[?&]fid=(\d+)').firstMatch(url);
    if (fid != null) return int.tryParse(fid.group(1)!);
    return null;
  }

  // ------------------------------------------------------------- scraping

  @override
  Future<List<AudioTrack>> scrapePlaylist(String url) async {
    final type = detectUrlType(url);
    switch (type) {
      case BilibiliUrlType.season:
        return _scrapeSeason(url);
      case BilibiliUrlType.favorite:
        return _scrapeFavorite(url);
      case BilibiliUrlType.live:
        return _scrapeLiveRoom(url);
      case BilibiliUrlType.video:
        final track = await scrapeVideo(url);
        return [track];
      case BilibiliUrlType.unknown:
        return [];
    }
  }

  @override
  Future<AudioTrack> scrapeVideo(String url) async {
    final type = detectUrlType(url);
    if (type == BilibiliUrlType.live) {
      return _liveTrack(url);
    }
    if (type == BilibiliUrlType.video) {
      final id = extractVideoId(url);
      if (id != null) {
        final info = await _api.fetchVideoInfo(id);
        return AudioTrack(
          id: 'video:${info.bvid}:${info.cid}',
          title: info.title,
          artist: info.owner,
          albumArt: info.pic,
          duration: Duration(seconds: info.duration),
          streamUrl: '',
          sourceTypeId: 'bilibili',
          metadata: {'isLive': false},
        );
      }
    }
    throw Exception('Unrecognized Bilibili URL: $url');
  }

  @override
  Future<String> scrapeStreamUrl(String trackId, {String? quality}) async {
    if (trackId.startsWith('video:')) {
      // video:{bvid}:{cid}
      final parts = trackId.split(':');
      if (parts.length >= 3) {
        final bvid = parts[1];
        var cid = int.tryParse(parts[2]) ?? 0;
        if (bvid.startsWith('BV')) {
          if (cid <= 0) {
            // cid may be missing (e.g. tracks built from the favorite API);
            // resolve it from the view API.
            final info = await _api.fetchVideoInfo(bvid);
            cid = info.cid;
          }
          if (cid > 0) {
            return _api.fetchAudioUrl(
              bvid,
              cid,
              quality: quality ?? PreferencesService().getAudioQuality(),
            );
          }
        }
      }
      throw Exception('Invalid Bilibili video track id: $trackId');
    }
    final roomId = int.tryParse(trackId);
    if (roomId != null) {
      return _api.fetchLiveStreamUrl(roomId);
    }
    throw Exception('Invalid Bilibili track id: $trackId');
  }

  // ------------------------------------------------------------ seasons

  Future<List<AudioTrack>> _scrapeSeason(String url) async {
    final season = extractSeason(url);
    if (season == null) {
      throw Exception('Unrecognized Bilibili season URL: $url');
    }
    var mid = season.mid;
    // The archives API needs the owner mid; try to resolve it from the
    // season id if not present in the URL.
    mid ??= await _resolveMidFromSeason(season.seasonId);
    if (mid == null) {
      throw Exception('Cannot resolve season owner: $url');
    }
    final videos = await _api.fetchSeasonArchives(
      seasonId: season.seasonId,
      mid: mid,
    );
    return videos.map(_videoToTrack).toList();
  }

  Future<int?> _resolveMidFromSeason(int seasonId) async {
    try {
      // seasons_archives_list reports the owner mid in its response.
      final response = await http
          .get(
            Uri.parse(
              'https://api.bilibili.com/x/polymer/web-space/seasons_archives_list'
              '?season_id=$seasonId&page_num=1&page_size=1',
            ),
            headers: {
              'User-Agent': _ua,
              'Referer': 'https://www.bilibili.com/',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['code'] == 0) {
          final mid = (data['data'] as Map<String, dynamic>?)?['mid'];
          if (mid is num && mid > 0) return mid.toInt();
        }
      }
    } catch (e) {
      _logger.error('Failed to resolve season mid', e);
    }
    return null;
  }

  // ---------------------------------------------------------- favorites

  Future<List<AudioTrack>> _scrapeFavorite(String url) async {
    final fid = extractFavoriteId(url);
    if (fid == null) {
      throw Exception('Unrecognized Bilibili favorite URL: $url');
    }
    final videos = await _api.fetchFavoriteList(fid);
    if (videos.isEmpty) {
      throw Exception('Favorite folder is empty or private: $url');
    }
    return videos.map(_videoToTrack).toList();
  }

  AudioTrack _videoToTrack(BilibiliVideoInfo info) {
    return AudioTrack(
      id: 'video:${info.bvid}:${info.cid}',
      title: info.title,
      artist: info.owner,
      albumArt: info.pic,
      duration: Duration(seconds: info.duration),
      streamUrl: '',
      sourceTypeId: 'bilibili',
      metadata: {'isLive': false},
    );
  }

  // --------------------------------------------------------------- live

  /// Fetches live room info (title, live status).
  Future<BilibiliLiveRoomInfo> fetchLiveRoomInfo(int roomId) {
    return _api.fetchLiveRoomInfo(roomId);
  }

  Future<AudioTrack> _liveTrack(String url) async {
    final roomId = extractLiveRoomId(url);
    if (roomId == null) {
      throw Exception('Unrecognized Bilibili live URL: $url');
    }
    final info = await _api.fetchLiveRoomInfo(roomId);
    final title = info.title.isEmpty
        ? 'Bilibili Live ${info.roomId}'
        : info.title;
    return AudioTrack(
      id: info.roomId.toString(),
      title: title,
      artist: info.ownerName ?? 'Bilibili',
      albumArt: (info.coverUrl == null || info.coverUrl!.isEmpty)
          ? null
          : info.coverUrl,
      duration: Duration.zero,
      streamUrl: '',
      sourceTypeId: 'bilibili',
      metadata: {
        'isLive': info.isLive,
        'isLiveCard': true,
        'roomId': info.roomId,
        if (info.coverUrl != null && info.coverUrl!.isNotEmpty)
          'coverUrl': info.coverUrl,
        if (info.avatarUrl != null && info.avatarUrl!.isNotEmpty)
          'avatarUrl': info.avatarUrl,
        if (info.liveTime != null)
          'liveTime': info.liveTime!.millisecondsSinceEpoch,
      },
    );
  }

  /// Playlist for a live room: a pinned "current live room" card track
  /// (whether online or not, so the UI always shows the room state) plus all
  /// locally recorded replays of this room.
  Future<List<AudioTrack>> _scrapeLiveRoom(String url) async {
    final roomId = extractLiveRoomId(url);
    if (roomId == null) {
      throw Exception('Unrecognized Bilibili live URL: $url');
    }
    final tracks = <AudioTrack>[];

    // Pinned live-room card: always present, so the UI can show the room
    // state (online/offline) and the recording toggle. When the current
    // title is unavailable, fall back to the most recent recording's title.
    String title = '';
    String? owner;
    var isLive = false;
    String? coverUrl;
    String? avatarUrl;
    DateTime? liveTime;
    try {
      final info = await _api.fetchLiveRoomInfo(roomId);
      title = info.title;
      owner = info.ownerName;
      isLive = info.isLive;
      coverUrl = info.coverUrl;
      avatarUrl = info.avatarUrl;
      liveTime = info.liveTime;
    } catch (e) {
      _logger.error('Failed to fetch live room info', e);
    }
    if (title.isEmpty) {
      final recordings = await loadRecordings(roomId);
      if (recordings.isNotEmpty) {
        title = recordings.first.title;
      }
    }
    if (title.isEmpty) {
      title = 'Bilibili Live $roomId';
    }
    tracks.add(
      AudioTrack(
        id: roomId.toString(),
        title: title,
        artist: owner ?? 'Bilibili',
        albumArt: (coverUrl == null || coverUrl.isEmpty) ? null : coverUrl,
        duration: Duration.zero,
        streamUrl: '',
        sourceTypeId: 'bilibili',
        metadata: {
          'isLive': isLive,
          'isLiveCard': true,
          'roomId': roomId,
          if (coverUrl != null && coverUrl.isNotEmpty) 'coverUrl': coverUrl,
          if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatarUrl': avatarUrl,
          if (liveTime != null) 'liveTime': liveTime.millisecondsSinceEpoch,
        },
      ),
    );

    // Recorded replays from the local recordings directory.
    tracks.addAll(await loadRecordings(roomId));

    return tracks;
  }

  // --------------------------------------------------------- recordings

  /// Directory where recordings of [roomId] are stored.
  Future<String> recordingsDir(int roomId) async {
    final base = await PreferencesService().getDownloadPath();
    final sep = Platform.pathSeparator;
    return '$base${sep}bilibili_recordings$sep$roomId';
  }

  /// Builds a safe file name from a live title.
  /// [extension] is the file suffix including the dot (default `.flv`).
  String recordingFileName(String title, {String extension = '.flv'}) {
    final sanitized = title
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    final ts = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${ts.year}${two(ts.month)}${two(ts.day)}_'
        '${two(ts.hour)}${two(ts.minute)}${two(ts.second)}';
    final base = sanitized.isEmpty ? 'recording' : sanitized;
    return '$base-$stamp$extension';
  }

  /// Splits a recording file name into (title, recorded-at time).
  /// The recorded time is formatted for the list subtitle.
  static (String, String) parseRecordingName(String fileName) {
    final match = RegExp(
      r'^(.*?)[-_](\d{8})[-_](\d{6})(\.\w+)?$',
    ).firstMatch(fileName);
    if (match == null) {
      return (fileName, '');
    }
    final title = match.group(1)!.trim();
    final date = match.group(2)!;
    final time = match.group(3)!;
    final formatted =
        '${date.substring(0, 4)}-${date.substring(4, 6)}-${date.substring(6, 8)} '
        '${time.substring(0, 2)}:${time.substring(2, 4)}:${time.substring(4, 6)}';
    return (title.isEmpty ? fileName : title, formatted);
  }

  /// Scans the local recordings of a room into audio tracks.
  Future<List<AudioTrack>> loadRecordings(int roomId) async {
    final dir = await recordingsDir(roomId);
    final directory = Directory(dir);
    if (!await directory.exists()) return [];
    try {
      final files = await directory
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      files.sort((a, b) => b.path.compareTo(a.path));
      final tracks = <AudioTrack>[];
      for (final file in files) {
        // Skip junk files (e.g. accidental m3u8 playlist dumps < 1 KB).
        final stat = await file.stat();
        if (stat.size < 1024) continue;
        final duration = await AudioDurationProbe.probeFile(file.path);
        final (title, recordedAt) = parseRecordingName(
          file.path.split(Platform.pathSeparator).last,
        );
        tracks.add(
          AudioTrack(
            id: file.path,
            title: title,
            artist: recordedAt.isEmpty ? 'Recording' : recordedAt,
            duration: duration,
            streamUrl: file.path,
            sourceTypeId: 'bilibili',
            metadata: {
              'isLive': false,
              'isRecording': true,
              'roomId': roomId,
              'fileSize': stat.size,
            },
          ),
        );
      }
      return tracks;
    } catch (e) {
      _logger.error('Failed to load recordings for room $roomId', e);
      return [];
    }
  }
}
