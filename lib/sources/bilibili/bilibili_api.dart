import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/sources/bilibili/bilibili_auth.dart';

/// Video info from the Bilibili view API.
class BilibiliVideoInfo {
  final String bvid;
  final String title;
  final String owner;
  final int cid;
  final String? pic;
  final int duration; // seconds

  const BilibiliVideoInfo({
    required this.bvid,
    required this.title,
    required this.owner,
    required this.cid,
    this.pic,
    required this.duration,
  });
}

/// Live room info.
class BilibiliLiveRoomInfo {
  final int roomId;
  final String title;
  final String? ownerName;
  final int liveStatus; // 0 offline, 1 live, 2 rotating
  final String? coverUrl;
  final String? avatarUrl; // owner avatar (live-card icon)
  final DateTime? liveTime; // when the stream started (null when offline)

  const BilibiliLiveRoomInfo({
    required this.roomId,
    required this.title,
    this.ownerName,
    required this.liveStatus,
    this.coverUrl,
    this.avatarUrl,
    this.liveTime,
  });

  bool get isLive => liveStatus == 1;
}

/// Bilibili API client (anonymous access).
class BilibiliApi {
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const String _referer = 'https://www.bilibili.com/';

  final LogService _logger = LogService();

  // WBI signing cache.
  String? _mixinKey;
  DateTime? _mixinKeyTime;

  Map<String, String> get _headers => {
    'User-Agent': _ua,
    'Referer': _referer,
    // Attach the login cookie when available: unlocks higher audio
    // quality, charged/paid content and per-user features.
    if (BilibiliAuth.instance.cookie case final cookie?) 'Cookie': cookie,
  };

  Future<Map<String, dynamic>> _getJson(
    String url, {
    Map<String, dynamic>? query,
  }) async {
    final uri = Uri.parse(
      url,
    ).replace(queryParameters: query?.map((k, v) => MapEntry(k, v.toString())));
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Bilibili API ${response.statusCode}: $url');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map<String, dynamic>) {
      throw Exception('Bilibili API returned unexpected shape: $url');
    }
    return data;
  }

  // ------------------------------------------------------------ WBI sign

  static const List<int> _mixinKeyEncTab = [
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
    37,
    48,
    7,
    16,
    24,
    55,
    40,
    61,
    26,
    17,
    0,
    1,
    60,
    51,
    30,
    4,
    22,
    25,
    54,
    21,
    56,
    59,
    6,
    63,
    57,
    62,
    11,
    36,
    20,
    34,
    44,
    52,
  ];

  static String _getMixinKey(String orig) {
    final sb = StringBuffer();
    for (final i in _mixinKeyEncTab) {
      if (i < orig.length) sb.write(orig[i]);
    }
    return sb.toString().substring(0, 32);
  }

  Future<String> _getMixinKeyCached() async {
    final now = DateTime.now();
    if (_mixinKey != null &&
        _mixinKeyTime != null &&
        now.difference(_mixinKeyTime!) < const Duration(hours: 12)) {
      return _mixinKey!;
    }
    final data = await _getJson('https://api.bilibili.com/x/web-interface/nav');
    final wbiMap = data['data'];
    if (wbiMap is! Map<String, dynamic>) {
      throw Exception('Bilibili nav returned no wbi data');
    }
    final wbi = wbiMap['wbi_img'];
    if (wbi is! Map<String, dynamic>) {
      throw Exception('Bilibili nav returned no wbi_img');
    }
    String keyFromUrl(String? url) {
      if (url == null) return '';
      final parts = url.split('/');
      final last = parts.last;
      return last.split('.')[0];
    }

    final imgKey = keyFromUrl(wbi['img_url']?.toString());
    final subKey = keyFromUrl(wbi['sub_url']?.toString());
    _mixinKey = _getMixinKey('$imgKey$subKey');
    _mixinKeyTime = now;
    return _mixinKey!;
  }

  /// Builds a signed query string for WBI-protected endpoints.
  Future<String> _wbiQuery(Map<String, dynamic> params) async {
    final mixinKey = await _getMixinKeyCached();
    final wts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final all = {...params, 'wts': wts};
    final keys = all.keys.toList()..sort();
    final query = keys
        .map(
          (k) =>
              '${Uri.encodeQueryComponent(k)}='
              '${Uri.encodeQueryComponent(all[k].toString())}',
        )
        .join('&');
    final wRid = md5.convert(utf8.encode('$query$mixinKey')).toString();
    return '$query&w_rid=$wRid';
  }

  // ------------------------------------------------------------- videos

  /// Fetches video metadata. Accepts bvid (BV...) or av id.
  Future<BilibiliVideoInfo> fetchVideoInfo(String bvidOrAv) async {
    final query = <String, dynamic>{};
    if (bvidOrAv.startsWith('BV')) {
      query['bvid'] = bvidOrAv;
    } else {
      final aid = bvidOrAv.replaceAll(RegExp('[^0-9]'), '');
      query['aid'] = int.tryParse(aid) ?? 0;
    }
    final data = await _getJson(
      'https://api.bilibili.com/x/web-interface/view',
      query: query,
    );
    if (data['code'] != 0) {
      final code = data['code'];
      final msg = data['message']?.toString() ?? '';
      if (code == 62002) {
        throw Exception(
          'Bilibili video unavailable (62002): the video is deleted, '
          'private, or requires a paid membership. $msg',
        );
      }
      throw Exception('Bilibili view failed: $code $msg');
    }
    final d = data['data'] as Map<String, dynamic>;
    final owner = d['owner'] as Map<String, dynamic>? ?? const {};
    return BilibiliVideoInfo(
      bvid: d['bvid']?.toString() ?? bvidOrAv,
      title: d['title']?.toString() ?? '',
      owner: owner['name']?.toString() ?? '',
      cid: (d['cid'] as num?)?.toInt() ?? 0,
      pic: d['pic']?.toString(),
      duration: (d['duration'] as num?)?.toInt() ?? 0,
    );
  }

  /// DASH audio stream ids by quality: 64k, 132k, 192k, 320k (Dolby), FLAC.
  static const Map<String, int> _qualityStreamId = {
    '64': 30216,
    '132': 30232,
    '192': 30280,
    '320': 30250,
    'flac': 30252,
  };

  /// Fetches the DASH audio stream URL for a video, honouring the requested
  /// [quality] ('auto' picks the highest available bandwidth).
  Future<String> fetchAudioUrl(
    String bvid,
    int cid, {
    String quality = 'auto',
  }) async {
    // FLAC requires the extra fnval bit (16 | 2048); other qualities use
    // plain DASH. Non-members simply get no FLAC stream and fall back.
    final fnval = quality == 'flac' ? 2064 : 16;
    final data = await _getJson(
      'https://api.bilibili.com/x/player/playurl',
      query: {'bvid': bvid, 'cid': cid, 'fnval': fnval, 'fourk': 1},
    );
    if (data['code'] != 0) {
      final code = data['code'];
      final msg = data['message']?.toString() ?? '';
      if (code == -403 || msg.contains('充电')) {
        throw Exception(
          'Bilibili playurl: this video requires a paid membership '
          '(充电专属). code=$code $msg',
        );
      }
      throw Exception('Bilibili playurl failed: $code $msg');
    }
    final dash =
        (data['data'] as Map<String, dynamic>?)?['dash']
            as Map<String, dynamic>?;
    final audio = dash?['audio'] as List<dynamic>? ?? const [];
    if (audio.isEmpty) {
      throw Exception('No audio stream available for $bvid');
    }
    final streams = audio.map((a) => a as Map<String, dynamic>).toList();

    Map<String, dynamic> pick;
    if (quality == 'auto') {
      // Highest bandwidth.
      pick = streams.reduce(
        (a, b) => (a['bandwidth'] as num? ?? 0) >= (b['bandwidth'] as num? ?? 0)
            ? a
            : b,
      );
    } else if (quality == 'flac') {
      // Prefer a FLAC stream, else highest bandwidth.
      Map<String, dynamic>? flac;
      for (final s in streams) {
        final id = s['id'] as num?;
        final codecs = s['codecs']?.toString() ?? '';
        if (id == _qualityStreamId['flac'] || codecs.contains('flac')) {
          flac = s;
          break;
        }
      }
      if (flac != null) {
        pick = flac;
      } else {
        pick = streams.reduce(
          (a, b) =>
              (a['bandwidth'] as num? ?? 0) >= (b['bandwidth'] as num? ?? 0)
              ? a
              : b,
        );
      }
    } else {
      // Exact stream id, else the stream whose bandwidth is closest to the
      // target bitrate.
      final targetId = _qualityStreamId[quality];
      Map<String, dynamic>? exact;
      for (final s in streams) {
        final sid = s['id'];
        if (sid is num && sid == targetId) {
          exact = s;
          break;
        }
      }
      if (exact != null) {
        pick = exact;
      } else {
        final targetBw = (int.tryParse(quality) ?? 192) * 1000;
        pick = streams.reduce((a, b) {
          final da = ((a['bandwidth'] as num? ?? 0) - targetBw).abs();
          final db = ((b['bandwidth'] as num? ?? 0) - targetBw).abs();
          return da <= db ? a : b;
        });
      }
    }

    final baseUrl = pick['baseUrl']?.toString();
    if (baseUrl == null || baseUrl.isEmpty) {
      throw Exception('Empty audio URL for $bvid');
    }
    return baseUrl;
  }

  // ------------------------------------------------------------ seasons

  /// Fetches all archives of a UGC season (合集).
  Future<List<BilibiliVideoInfo>> fetchSeasonArchives({
    required int seasonId,
    required int mid,
  }) async {
    final results = <BilibiliVideoInfo>[];
    var pageNum = 1;
    const pageSize = 30;
    while (true) {
      final data = await _getJson(
        'https://api.bilibili.com/x/polymer/web-space/seasons_archives_list',
        query: {
          'mid': mid,
          'season_id': seasonId,
          'page_num': pageNum,
          'page_size': pageSize,
          'sort_reverse': false,
        },
      );
      if (data['code'] != 0) {
        throw Exception(
          'Bilibili season failed: ${data['code']} ${data['message']}',
        );
      }
      final d = data['data'] as Map<String, dynamic>;
      final archives = d['archives'] as List<dynamic>? ?? const [];
      for (final a in archives) {
        final m = a as Map<String, dynamic>;
        results.add(
          BilibiliVideoInfo(
            bvid: m['bvid']?.toString() ?? '',
            title: m['title']?.toString() ?? '',
            owner:
                (m['owner'] as Map<String, dynamic>?)?['name']?.toString() ??
                '',
            cid: (m['cid'] as num?)?.toInt() ?? 0,
            pic: m['pic']?.toString(),
            duration: (m['duration'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      final page = d['page'] as Map<String, dynamic>? ?? const {};
      final total = (page['total'] as num?)?.toInt() ?? 0;
      if (results.length >= total || archives.isEmpty) break;
      pageNum++;
    }
    return results;
  }

  // ---------------------------------------------------------- favorites

  /// Fetches the list of favorite folders (收藏夹) of user [uid].
  /// Returns (id, title, mediaCount) tuples. Requires login for private
  /// folders; public folders are visible without it.
  Future<List<({int id, String title, int mediaCount})>> fetchFavoriteFolders(
    int uid,
  ) async {
    final folders = <({int id, String title, int mediaCount})>[];
    try {
      final query = await _wbiQuery({'up_mid': uid, 'platform': 'web'});
      final data = await _getJson(
        'https://api.bilibili.com/x/v3/fav/folder/created/list-all?$query',
      );
      if (data['code'] != 0) {
        _logger.warning(
          'Bilibili favorite folders failed: ${data['code']} ${data['message']}',
        );
        return folders;
      }
      final list = data['data']?['list'] as List<dynamic>? ?? [];
      for (final f in list) {
        final ff = f as Map<String, dynamic>;
        final id = (ff['id'] as num?)?.toInt() ?? 0;
        final title = ff['title']?.toString() ?? '';
        final count = (ff['media_count'] as num?)?.toInt() ?? 0;
        if (id > 0 && title.isNotEmpty) {
          folders.add((id: id, title: title, mediaCount: count));
        }
      }
    } catch (e) {
      _logger.error('Bilibili favorite folders failed', e);
    }
    return folders;
  }

  /// Fetches the followed users (关注列表) of [uid]. The list includes both
  /// video uploaders and live streamers; each entry carries the user's uid,
  /// name and face (avatar). Requires login (the follow list is private).
  Future<List<({int mid, String name, String face})>> fetchFollowings(
    int uid, {
    int maxPages = 5,
  }) async {
    final result = <({int mid, String name, String face})>[];
    try {
      var pn = 1;
      while (true) {
        final data = await _getJson(
          'https://api.bilibili.com/x/relation/followings',
          query: {'vmid': uid, 'pn': pn, 'ps': 30, 'order': 'attention'},
        );
        if (data['code'] != 0) break;
        final list = data['data']?['list'] as List<dynamic>? ?? [];
        if (list.isEmpty) break;
        for (final u in list) {
          final uu = u as Map<String, dynamic>;
          final mid = (uu['mid'] as num?)?.toInt() ?? 0;
          final name = uu['uname']?.toString() ?? '';
          if (mid > 0 && name.isNotEmpty) {
            result.add((
              mid: mid,
              name: name,
              face: uu['face']?.toString() ?? '',
            ));
          }
        }
        final hasMore =
            data['data']?['re_version'] != null || list.length >= 30;
        if (!hasMore || pn >= maxPages) break;
        pn++;
      }
    } catch (e) {
      _logger.error('Bilibili followings failed', e);
    }
    return result;
  }

  /// Fetches videos of a favorite folder (收藏夹), via WBI API first and
  /// falling back to the medialist page if the API returns no media.
  Future<List<BilibiliVideoInfo>> fetchFavoriteList(int mediaId) async {
    final videos = <BilibiliVideoInfo>[];
    try {
      // Fetch all pages (20 per page) of the folder.
      const pageSize = 20;
      var page = 1;
      while (true) {
        final query = await _wbiQuery({
          'media_id': mediaId,
          'pn': page,
          'ps': pageSize,
          'platform': 'web',
        });
        final data = await _getJson(
          'https://api.bilibili.com/x/v3/fav/resource/list?$query',
        );
        if (data['code'] != 0) break;
        final d = data['data'] as Map<String, dynamic>?;
        final medias = d?['medias'] as List<dynamic>?;
        final hasMore = d?['has_more'] as bool? ?? false;
        if (medias == null || medias.isEmpty) break;
        for (final m in medias) {
          final mm = m as Map<String, dynamic>;
          final title = mm['title']?.toString() ?? '';
          // "已失效视频" (deleted/invalid) entries cannot be played;
          // skip them instead of surfacing a broken track.
          if (title == '已失效视频' || title.contains('已失效')) continue;
          // The cid lives in ugc.first_cid (not a top-level "cid").
          final ugc = mm['ugc'] as Map<String, dynamic>?;
          final cid = ((ugc?['first_cid'] ?? mm['cid']) as num?)?.toInt() ?? 0;
          videos.add(
            BilibiliVideoInfo(
              bvid: mm['bvid']?.toString() ?? mm['bv_id']?.toString() ?? '',
              title: title,
              owner:
                  (mm['upper'] as Map<String, dynamic>?)?['name']?.toString() ??
                  '',
              cid: cid,
              pic: mm['cover']?.toString(),
              duration: (mm['duration'] as num?)?.toInt() ?? 0,
            ),
          );
        }
        if (!hasMore) break;
        page++;
        // Safety cap to avoid runaway loops.
        if (page > 50) break;
      }
      if (videos.isNotEmpty) return videos;
    } catch (e) {
      _logger.error('Bilibili favorite API failed', e);
    }

    // Fallback: parse the medialist page.
    final pageVideos = await _fetchFavoriteFromPage(mediaId);
    if (videos.isEmpty && pageVideos.isNotEmpty) return pageVideos;
    return videos;
  }

  Future<List<BilibiliVideoInfo>> _fetchFavoriteFromPage(int mediaId) async {
    final response = await http.get(
      Uri.parse('https://www.bilibili.com/medialist/play/ml$mediaId'),
      headers: _headers,
    );
    if (response.statusCode != 200) return [];
    final body = utf8.decode(response.bodyBytes);
    final match = RegExp(
      r'__INITIAL_STATE__=(\{.*?\})</script>',
      dotAll: true,
    ).firstMatch(body);
    if (match == null) return [];
    try {
      final state = jsonDecode(match.group(1)!);
      final mediaList =
          (state as Map<String, dynamic>)['mediaList'] as Map<String, dynamic>?;
      final medias = mediaList?['medias'] as List<dynamic>? ?? const [];
      final videos = <BilibiliVideoInfo>[];
      for (final m in medias) {
        final mm = m as Map<String, dynamic>;
        final title = mm['title']?.toString() ?? '';
        if (title == '已失效视频' || title.contains('已失效')) continue;
        final ugc = mm['ugc'] as Map<String, dynamic>?;
        final cid = ((ugc?['first_cid'] ?? mm['cid']) as num?)?.toInt() ?? 0;
        videos.add(
          BilibiliVideoInfo(
            bvid: mm['bvid']?.toString() ?? mm['bv_id']?.toString() ?? '',
            title: title,
            owner:
                (mm['upper'] as Map<String, dynamic>?)?['name']?.toString() ??
                '',
            cid: cid,
            pic: mm['cover']?.toString(),
            duration: (mm['duration'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      return videos;
    } catch (e) {
      return [];
    }
  }

  // -------------------------------------------------------------- live

  /// Fetches live room info (title, live status).
  Future<BilibiliLiveRoomInfo> fetchLiveRoomInfo(int roomId) async {
    final data = await _getJson(
      'https://api.live.bilibili.com/room/v1/Room/get_info',
      query: {'room_id': roomId},
    );
    if (data['code'] != 0) {
      throw Exception(
        'Bilibili room failed: ${data['code']} ${data['message']}',
      );
    }
    final d = data['data'] as Map<String, dynamic>;
    DateTime? liveTime;
    final liveTimeRaw = d['live_time']?.toString();
    if (liveTimeRaw != null && liveTimeRaw.isNotEmpty) {
      liveTime = DateTime.tryParse(liveTimeRaw)?.toLocal();
      if (liveTime == null) {
        final ts = int.tryParse(liveTimeRaw);
        if (ts != null && ts > 0) {
          liveTime = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
        }
      }
    }
    return BilibiliLiveRoomInfo(
      roomId: roomId,
      title: d['title']?.toString() ?? 'Bilibili Live $roomId',
      ownerName: d['uname']?.toString(),
      liveStatus: (d['live_status'] as num?)?.toInt() ?? 0,
      coverUrl: d['user_cover']?.toString() ?? d['keyframe']?.toString(),
      avatarUrl: d['user_face']?.toString(),
      liveTime: liveTime,
    );
  }

  /// Fetches the live stream URL (FLV preferred, HLS fallback).
  Future<String> fetchLiveStreamUrl(int roomId) async {
    // 1. Resolve the real room id.
    var realRoomId = roomId;
    try {
      final init = await _getJson(
        'https://api.live.bilibili.com/room/v1/Room/room_init',
        query: {'id': roomId},
      );
      if (init['code'] == 0) {
        realRoomId =
            ((init['data'] as Map<String, dynamic>)['room_id'] as num?)
                ?.toInt() ??
            roomId;
      }
    } catch (e) {
      // keep original id
    }

    // 2. Get the play URL.
    final play = await _getJson(
      'https://api.live.bilibili.com/room/v1/Room/playUrl',
      query: {'cid': realRoomId, 'platform': 'h5', 'qn': '10000'},
    );
    if (play['code'] != 0) {
      throw Exception('Bilibili playUrl failed: ${play['code']}');
    }
    final durl =
        (play['data'] as Map<String, dynamic>?)?['durl'] as List<dynamic>?;
    if (durl == null || durl.isEmpty) {
      throw Exception('No live stream URL for room $roomId');
    }
    return (durl.first as Map<String, dynamic>)['url']?.toString() ?? '';
  }
}
