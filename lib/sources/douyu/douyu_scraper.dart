import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/audio_duration_probe.dart';
import 'package:asmr_hub/services/preferences_service.dart';
import 'package:asmr_hub/sources/base/source_scraper.dart';
import 'package:asmr_hub/sources/douyu/douyu_auth.dart';
import 'package:asmr_hub/sources/douyu/douyu_sign.dart';

class DouyuScraper implements SourceScraper {
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0';

  /// Visitor cookie jar: Douyu issues cookies on any page request and some
  /// rooms require them (or the login cookie) to return JSON instead of an
  /// HTML hint page.
  static final Map<String, String> _cookies = {};

  /// Request headers for Douyu endpoints: browser UA, referer and the
  /// visitor/login cookie when available.
  Map<String, String> _reqHeaders(String roomId) {
    final cookie = DouyuAuth.instance.cookie;
    final parts = <String>[
      if (cookie != null && cookie.isNotEmpty) cookie,
      if (_cookies.isNotEmpty)
        _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
    ];
    final cookieHeader = parts.isEmpty ? null : parts.join('; ');
    return {
      'User-Agent': _ua,
      'Referer': 'https://www.douyu.com/$roomId',
      if (cookieHeader != null) 'Cookie': cookieHeader,
    };
  }

  /// Merges set-cookie headers from a response into the visitor jar.
  void _mergeSetCookie(http.Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null) return;
    // Split on commas only when followed by "key=" so Expires dates (which
    // contain commas) are not treated as cookie separators.
    for (final part in raw.split(RegExp(r',(?=[^,]*=)'))) {
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      final key = part.substring(0, idx).trim();
      if (key.isEmpty || key.contains(' ')) continue;
      if (RegExp(
        r'^(Expires|Path|Domain|Max-Age|SameSite|Secure|HttpOnly|Version)$',
        caseSensitive: false,
      ).hasMatch(key)) {
        continue;
      }
      var value = part.substring(idx + 1);
      final semi = value.indexOf(';');
      if (semi >= 0) value = value.substring(0, semi);
      _cookies[key] = value;
    }
  }

  /// Extract a numeric room id from a Douyu URL, or null.
  String? extractRoomId(String url) {
    final direct = RegExp(r'douyu(?:tv)?\.com/(\d+)').firstMatch(url);
    if (direct != null) return direct.group(1);
    final ridParam = RegExp(r'[?&]rid=(\d+)').firstMatch(url);
    if (ridParam != null) return ridParam.group(1);
    return null;
  }

  /// Resolve room id (also handles short-name URLs like douyu.com/pigff).
  Future<String?> resolveRoomId(String urlOrName) async {
    final direct = extractRoomId(urlOrName);
    if (direct != null) return direct;
    // Try resolving short name through the betard endpoint.
    final name = Uri.tryParse(urlOrName)?.pathSegments.lastOrNull;
    if (name == null || name.isEmpty) return null;
    try {
      final response = await http.get(
        Uri.parse('https://www.douyu.com/betard/$name'),
        headers: _reqHeaders(name),
      );
      _mergeSetCookie(response);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final room = (json as Map<String, dynamic>)['room'];
        if (room is Map<String, dynamic>) {
          return room['room_id']?.toString();
        }
      }
    } catch (e) {
      // Fall through
    }
    return null;
  }

  /// Fetch room info from betard endpoint.
  Future<Map<String, dynamic>> _fetchRoomInfo(String roomId) async {
    final response = await http.get(
      Uri.parse('https://www.douyu.com/betard/$roomId'),
      headers: _reqHeaders(roomId),
    );
    _mergeSetCookie(response);
    if (response.statusCode != 200) {
      throw Exception('Douyu betard failed: ${response.statusCode}');
    }
    // Unknown/restricted rooms return an HTML hint page instead of JSON.
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('json')) {
      throw Exception(
        'Douyu room not found or inaccessible (may require login): $roomId',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final room = json['room'] as Map<String, dynamic>?;
    if (room == null) {
      throw Exception('Douyu room not found: $roomId');
    }
    return room;
  }

  /// Public room-info accessor (used by the source for recording titles).
  Future<Map<String, dynamic>> fetchRoomInfoForRecording(String roomId) {
    return _fetchRoomInfo(roomId);
  }

  /// Public page-meta accessor (fallback for live-status probing).
  Future<
    ({
      String title,
      String cover,
      String owner,
      String avatar,
      bool isLive,
      DateTime? liveTime,
    })
  >
  fetchPageMetaForRecording(String roomId) {
    return _fetchPageMeta(roomId);
  }

  /// Get the live stream URL for a room.
  Future<String> _getStreamUrl(String roomId) async {
    // Sanity check via betard (offline / VOD loop). The betard API is
    // rate-limited for some rooms; in that case skip the check — the H5
    // play endpoint below reports its own errors.
    try {
      final room = await _fetchRoomInfo(roomId);
      final showStatus = room['show_status'];
      final videoLoop = room['videoLoop'];
      if (showStatus != 1) {
        throw Exception('Douyu room is offline');
      }
      if (videoLoop == 1) {
        throw Exception('Douyu room is playing VOD loop');
      }
    } catch (e) {
      if (e is Exception && e.toString().contains('offline')) rethrow;
      if (e is Exception && e.toString().contains('VOD')) rethrow;
      // Rate-limited betard: continue to the H5 play flow.
    }

    // Fetch the obfuscated signing script.
    final encResponse = await http.get(
      Uri.parse('https://www.douyu.com/swf_api/homeH5Enc?rids=$roomId'),
      headers: _reqHeaders(roomId),
    );
    _mergeSetCookie(encResponse);
    if (encResponse.statusCode != 200) {
      throw Exception('Failed to fetch Douyu signing script');
    }
    final decoded = jsonDecode(encResponse.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected Douyu signing response');
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Unexpected Douyu signing data');
    }
    final crptext = data['room$roomId']?.toString();
    if (crptext == null || crptext.isEmpty) {
      throw Exception('Douyu signing script not found');
    }

    final sign = DouyuSign.getSign(crptext, roomId);
    final body =
        '$sign&cdn=&rate=-1&ver=Douyu_223061205&iar=1&ive=1&hevc=0&fa=0';

    final playResponse = await http.post(
      Uri.parse('https://www.douyu.com/lapi/live/getH5Play/$roomId'),
      headers: {
        ..._reqHeaders(roomId),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );
    _mergeSetCookie(playResponse);
    if (playResponse.statusCode != 200) {
      throw Exception('Douyu getH5Play failed: ${playResponse.statusCode}');
    }
    final playJson = jsonDecode(playResponse.body) as Map<String, dynamic>;
    if (playJson['error'] != 0) {
      throw Exception(
        'Douyu getH5Play error ${playJson['error']}: ${playJson['msg']}',
      );
    }
    final playData = playJson['data'] as Map<String, dynamic>;
    final rtmpUrl = playData['rtmp_url']?.toString() ?? '';
    final rtmpLive = playData['rtmp_live']?.toString() ?? '';
    if (rtmpUrl.isEmpty || rtmpLive.isEmpty) {
      throw Exception('Douyu returned an empty stream URL');
    }
    return '$rtmpUrl/$rtmpLive';
  }

  @override
  Future<List<AudioTrack>> scrapePlaylist(String url) async {
    // Unified live-room model (same structure as Bilibili): a pinned live
    // card track (always present, with the actual online state) followed by
    // local recordings of this room.
    final roomId = await resolveRoomId(url);
    if (roomId == null) {
      throw Exception('Unrecognized Douyu URL: $url');
    }
    final tracks = <AudioTrack>[];

    String title = '';
    String? owner;
    var isLive = false;
    String? coverUrl;
    String? avatarUrl;
    DateTime? liveTime;
    try {
      final room = await _fetchRoomInfo(roomId);
      title = room['room_name']?.toString() ?? '';
      owner = room['owner_name']?.toString();
      isLive = room['show_status'] == 1 && room['videoLoop'] != 1;
      coverUrl = room['room_pic']?.toString();
      avatarUrl = room['owner_avatar']?.toString();
      final showTime = room['show_time'];
      if (showTime is num && showTime > 0) {
        liveTime = DateTime.fromMillisecondsSinceEpoch(
          (showTime * 1000).round(),
        );
      }
    } catch (e) {
      // betard is rate-limited for some rooms; fall back to the room page
      // which embeds the full room JSON.
      final meta = await _fetchPageMeta(roomId);
      title = meta.title;
      owner = meta.owner;
      isLive = meta.isLive;
      coverUrl = meta.cover.isEmpty ? null : meta.cover;
      avatarUrl = meta.avatar.isEmpty ? null : meta.avatar;
      liveTime = meta.liveTime;
    }
    if (title.isEmpty) {
      final recordings = await loadRecordings(roomId);
      if (recordings.isNotEmpty) {
        title = recordings.first.title;
      }
    }
    if (title.isEmpty) {
      title = 'Douyu Live $roomId';
    }
    tracks.add(
      AudioTrack(
        id: roomId,
        title: title,
        artist: owner ?? 'Douyu',
        albumArt: (coverUrl == null || coverUrl.isEmpty) ? null : coverUrl,
        duration: Duration.zero,
        streamUrl: '',
        sourceTypeId: 'douyu',
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

    tracks.addAll(await loadRecordings(roomId));
    return tracks;
  }

  @override
  Future<AudioTrack> scrapeVideo(String url) async {
    final roomId = await resolveRoomId(url);
    if (roomId == null) {
      throw Exception('Unrecognized Douyu URL: $url');
    }
    String title = '';
    String? owner;
    var isLive = false;
    String? coverUrl;
    String? avatarUrl;
    DateTime? liveTime;
    try {
      final room = await _fetchRoomInfo(roomId);
      title = room['room_name']?.toString() ?? '';
      owner = room['owner_name']?.toString();
      isLive = room['show_status'] == 1 && room['videoLoop'] != 1;
      coverUrl = room['room_pic']?.toString();
      avatarUrl = room['owner_avatar']?.toString();
      final showTime = room['show_time'];
      if (showTime is num && showTime > 0) {
        liveTime = DateTime.fromMillisecondsSinceEpoch(
          (showTime * 1000).round(),
        );
      }
    } catch (e) {
      final meta = await _fetchPageMeta(roomId);
      title = meta.title;
      owner = meta.owner;
      isLive = meta.isLive;
      coverUrl = meta.cover.isEmpty ? null : meta.cover;
      avatarUrl = meta.avatar.isEmpty ? null : meta.avatar;
      liveTime = meta.liveTime;
    }
    if (title.isEmpty) title = 'Douyu Live $roomId';
    return AudioTrack(
      id: roomId,
      title: title,
      artist: owner ?? 'Unknown',
      albumArt: coverUrl,
      duration: Duration.zero,
      streamUrl: '',
      sourceTypeId: 'douyu',
      metadata: {
        'isLive': isLive,
        'isLiveCard': true,
        'roomId': roomId,
        if (coverUrl != null && coverUrl.isNotEmpty) 'coverUrl': coverUrl,
        if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatarUrl': avatarUrl,
        if (liveTime != null) 'liveTime': liveTime.millisecondsSinceEpoch,
      },
    );
  }

  /// Falls back to the room page when the betard API is rate-limited: the
  /// page embeds a full room JSON (title, owner, avatar, cover, live status,
  /// live start time), so the card can still show accurate info.
  Future<
    ({
      String title,
      String cover,
      String owner,
      String avatar,
      bool isLive,
      DateTime? liveTime,
    })
  >
  _fetchPageMeta(String roomId) async {
    try {
      final response = await http.get(
        Uri.parse('https://www.douyu.com/$roomId'),
        headers: _reqHeaders(roomId),
      );
      _mergeSetCookie(response);
      if (response.statusCode != 200) {
        return (
          title: '',
          cover: '',
          owner: '',
          avatar: '',
          isLive: false,
          liveTime: null,
        );
      }
      // The room JSON is embedded with escaped quotes; unescape them.
      final body = response.body.replaceAll(r'\"', '"');
      String grab(String key) {
        final m = RegExp('"$key"\\s*:\\s*"([^"]*)"').firstMatch(body);
        return m?.group(1) ?? '';
      }

      final title = grab('room_name');
      final owner = grab('owner_name');
      // Newer douyu pages no longer embed `room_pic`; the live screenshot
      // (`rpic.douyucdn.cn/asrpic/...`) doubles as the room cover and is also
      // exposed as og:image. The file is actually JPEG despite the `.avif`
      // path suffix.
      var cover = grab('room_pic');
      if (cover.isEmpty) {
        final asrpic = RegExp(
          r'https://rpic\.douyucdn\.cn/asrpic/[^\s"\\]+',
        ).firstMatch(body);
        if (asrpic != null) {
          cover = asrpic.group(0)!;
        }
      }
      if (cover.isEmpty) {
        final og = RegExp(r'og:image"\s+content="([^"]+)"').firstMatch(body);
        if (og != null) {
          cover = og.group(1)!;
        }
      }
      if (cover.isEmpty) {
        final roomCover = RegExp(
          r'https://apic\.douyucdn\.cn/cover/roomCover/[^\s"\\]+',
        ).firstMatch(body);
        if (roomCover != null) {
          cover = roomCover.group(0)!;
        }
      }
      // Owner avatar (used as the live-card icon).
      var avatar = grab('owner_avatar');
      if (avatar.isEmpty) {
        final av = RegExp(
          r'https://apic\.douyucdn\.cn/upload/avatar_v3/[^\s"\\]+',
        ).firstMatch(body);
        if (av != null) {
          avatar = av.group(0)!;
        }
      }
      final showStatus = RegExp(
        r'"show_status"\s*:\s*(\d+)',
      ).firstMatch(body)?.group(1);
      final videoLoop = RegExp(
        r'"videoLoop"\s*:\s*(\d+)',
      ).firstMatch(body)?.group(1);
      final isLive = showStatus == '1' && videoLoop != '1';

      DateTime? liveTime;
      final showTime = RegExp(
        r'"show_time"\s*:\s*(\d+)',
      ).firstMatch(body)?.group(1);
      final ts = int.tryParse(showTime ?? '');
      if (ts != null && ts > 0) {
        liveTime = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      }

      return (
        title: title,
        cover: cover,
        owner: owner,
        avatar: avatar,
        isLive: isLive,
        liveTime: liveTime,
      );
    } catch (e) {
      return (
        title: '',
        cover: '',
        owner: '',
        avatar: '',
        isLive: false,
        liveTime: null,
      );
    }
  }

  @override
  Future<String> scrapeStreamUrl(String trackId, {String? quality}) async {
    return _getStreamUrl(trackId);
  }

  // --------------------------------------------------------- recordings

  /// Directory where recordings of [roomId] are stored.
  Future<String> recordingsDir(String roomId) async {
    final base = await PreferencesService().getDownloadPath();
    final sep = Platform.pathSeparator;
    return '$base${sep}douyu_recordings$sep$roomId';
  }

  /// Builds a safe recording file name from a live title.
  String recordingFileName(String title) {
    final sanitized = title
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    final ts = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${ts.year}${two(ts.month)}${two(ts.day)}_'
        '${two(ts.hour)}${two(ts.minute)}${two(ts.second)}';
    final base = sanitized.isEmpty ? 'recording' : sanitized;
    return '$base-$stamp.flv';
  }

  /// Scans the local recordings of a room into audio tracks (same naming
  /// convention as Bilibili recordings: title + '-' + timestamp + ext).
  Future<List<AudioTrack>> loadRecordings(String roomId) async {
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
        final stat = await file.stat();
        if (stat.size < 1024) continue;
        final duration = await AudioDurationProbe.probeFile(file.path);
        final match = RegExp(
          r'^(.*?)[-_](\d{8})[-_](\d{6})(\.\w+)?$',
        ).firstMatch(file.path.split(Platform.pathSeparator).last);
        var title = file.path.split(Platform.pathSeparator).last;
        var recordedAt = '';
        if (match != null) {
          title = match.group(1)!.trim();
          final date = match.group(2)!;
          final time = match.group(3)!;
          recordedAt =
              '${date.substring(0, 4)}-${date.substring(4, 6)}-${date.substring(6, 8)} '
              '${time.substring(0, 2)}:${time.substring(2, 4)}:${time.substring(4, 6)}';
        }
        tracks.add(
          AudioTrack(
            id: file.path,
            title: title,
            artist: recordedAt.isEmpty ? 'Recording' : recordedAt,
            duration: duration,
            streamUrl: file.path,
            sourceTypeId: 'douyu',
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
      return [];
    }
  }
}
