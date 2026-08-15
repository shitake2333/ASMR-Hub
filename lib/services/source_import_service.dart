import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:asmr_hub/models/asmr_source.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/sources/asmrone/asmr_one_auth.dart';
import 'package:asmr_hub/sources/asmrone/asmr_one_scraper.dart';
import 'package:asmr_hub/sources/bilibili/bilibili_api.dart';
import 'package:asmr_hub/sources/bilibili/bilibili_auth.dart';
import 'package:asmr_hub/sources/dlsite/dlsite_auth.dart';
import 'package:asmr_hub/sources/douyu/douyu_auth.dart';

/// One importable entry discovered from a logged-in account.
class ImportedSource {
  final String name;
  final String url;
  final String sourceTypeId;
  final List<String> tags;

  /// Optional extra line shown under the name (e.g. media count).
  final String? subtitle;

  const ImportedSource({
    required this.name,
    required this.url,
    required this.sourceTypeId,
    this.tags = const [],
    this.subtitle,
  });

  ASMRSource toAsmrSource() => ASMRSource(
    id: '$sourceTypeId:$url',
    name: name,
    url: url,
    sourceTypeId: sourceTypeId,
    tags: tags,
    addedDate: DateTime.now(),
  );
}

/// A discoverable category: one platform + one content type (e.g. "Bilibili
/// favorites", "asmr.one playlists"). [entries] are the items the user can
/// pick from (loaded lazily on the second step).
class ImportGroup {
  /// Stable id, e.g. 'bilibili_favorites'.
  final String id;

  /// Source platform id, e.g. 'bilibili'.
  final String sourceTypeId;

  /// Localized-ish category title (may be raw; UI localizes known ids).
  final String title;

  /// Whether the platform is logged in (group is importable).
  final bool available;
  final List<ImportedSource> entries;

  const ImportGroup({
    required this.id,
    required this.sourceTypeId,
    required this.title,
    this.available = true,
    this.entries = const [],
  });
}

/// Discovers importable sources (favorites, followed live channels,
/// playlists) from the logged-in platforms, grouped by platform + type.
class SourceImportService {
  final LogService _logger = LogService();

  /// Lists the importable categories. Each group carries availability (the
  /// platform is logged in) but no entries; entries load lazily via
  /// [loadGroupEntries] (step 2 of the picker).
  Future<List<ImportGroup>> discoverGroups() async {
    return [
      ImportGroup(
        id: 'bilibili_favorites',
        sourceTypeId: 'bilibili',
        title: 'Bilibili Favorites',
        available: BilibiliAuth.instance.isLoggedIn,
      ),
      ImportGroup(
        id: 'bilibili_followings',
        sourceTypeId: 'bilibili',
        title: 'Bilibili Followings',
        available: BilibiliAuth.instance.isLoggedIn,
      ),
      ImportGroup(
        id: 'asmrone_playlists',
        sourceTypeId: 'asmrone',
        title: 'asmr.one Playlists',
        available: AsmrOneAuth.instance.isLoggedIn,
      ),
      ImportGroup(
        id: 'douyu_follows',
        sourceTypeId: 'douyu',
        title: 'Douyu Follows',
        available: DouyuAuth.instance.isLoggedIn,
      ),
      ImportGroup(
        id: 'dlsite_library',
        sourceTypeId: 'dlsite',
        title: 'DLsite Purchased',
        available: DLSiteAuth.instance.isLoggedIn,
      ),
    ];
  }

  /// Loads the entries of one group (step 2 of the picker).
  Future<List<ImportedSource>> loadGroupEntries(String groupId) async {
    switch (groupId) {
      case 'bilibili_favorites':
        return _bilibiliFavorites();
      case 'bilibili_followings':
        return _bilibiliFollowings();
      case 'asmrone_playlists':
        return _asmrOnePlaylists();
      case 'douyu_follows':
        return _douyuFollows();
      case 'dlsite_library':
        return _dlsiteLibrary();
      default:
        return const [];
    }
  }

  Future<List<ImportedSource>> _bilibiliFavorites() async {
    final result = <ImportedSource>[];
    final auth = BilibiliAuth.instance;
    if (!auth.isLoggedIn) return result;
    final uid = int.tryParse(auth.currentUser?.id ?? '');
    if (uid == null || uid <= 0) return result;
    try {
      final api = BilibiliApi();
      final folders = await api.fetchFavoriteFolders(uid);
      for (final f in folders) {
        result.add(
          ImportedSource(
            name: f.title,
            url: 'https://www.bilibili.com/medialist/play/ml${f.id}',
            sourceTypeId: 'bilibili',
            tags: ['favorite'],
            subtitle: '${f.mediaCount} videos',
          ),
        );
      }
    } catch (e) {
      _logger.error('Discover Bilibili favorites failed', e);
    }
    return result;
  }

  /// Bilibili followed users, mapped to their live room source
  /// (live.bilibili.com/{mid}). Not every follow is a streamer, but the live
  /// room URL resolves for the ones that are.
  Future<List<ImportedSource>> _bilibiliFollowings() async {
    final result = <ImportedSource>[];
    final auth = BilibiliAuth.instance;
    if (!auth.isLoggedIn) return result;
    final uid = int.tryParse(auth.currentUser?.id ?? '');
    if (uid == null || uid <= 0) return result;
    try {
      final api = BilibiliApi();
      final followings = await api.fetchFollowings(uid);
      for (final f in followings) {
        result.add(
          ImportedSource(
            name: f.name,
            url: 'https://live.bilibili.com/${f.mid}',
            sourceTypeId: 'bilibili',
            tags: ['follow'],
            subtitle: 'mid ${f.mid}',
          ),
        );
      }
    } catch (e) {
      _logger.error('Discover Bilibili followings failed', e);
    }
    return result;
  }

  Future<List<ImportedSource>> _asmrOnePlaylists() async {
    final result = <ImportedSource>[];
    final auth = AsmrOneAuth.instance;
    if (!auth.isLoggedIn) return result;
    try {
      final playlists = await AsmrOneScraper().fetchUserPlaylists();
      for (final p in playlists) {
        final name = switch (p.name) {
          '__SYS_PLAYLIST_LIKED' => '我喜欢的音声',
          '__SYS_PLAYLIST_MARKED' => '我标记的音声',
          _ => p.name,
        };
        result.add(
          ImportedSource(
            name: name,
            url: 'https://asmr.one/playlist?id=${p.id}',
            sourceTypeId: 'asmrone',
            tags: ['playlist'],
          ),
        );
      }
    } catch (e) {
      _logger.error('Discover asmr.one playlists failed', e);
    }
    return result;
  }

  Future<List<ImportedSource>> _douyuFollows() async {
    final result = <ImportedSource>[];
    final auth = DouyuAuth.instance;
    if (!auth.isLoggedIn) return result;
    final uid = auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return result;
    try {
      final follows = await DouyuFollowsFetcher().fetchFollowedRooms(uid);
      for (final f in follows) {
        result.add(
          ImportedSource(
            name: f.name,
            url: 'https://www.douyu.com/${f.roomId}',
            sourceTypeId: 'douyu',
            tags: ['follow'],
            subtitle: 'room ${f.roomId}',
          ),
        );
      }
    } catch (e) {
      _logger.error('Discover Douyu follows failed', e);
    }
    return result;
  }

  Future<List<ImportedSource>> _dlsiteLibrary() async {
    final result = <ImportedSource>[];
    final auth = DLSiteAuth.instance;
    if (!auth.isLoggedIn) return result;
    try {
      final works = await DlsiteLibraryFetcher().fetchPurchased();
      for (final w in works) {
        result.add(
          ImportedSource(
            name: w.name,
            url: w.url,
            sourceTypeId: 'dlsite',
            tags: ['library'],
          ),
        );
      }
    } catch (e) {
      _logger.error('Discover DLsite library failed', e);
    }
    return result;
  }
}

/// Fetches the followed live rooms of a Douyu user from the myFollow page
/// (the SPA loads the list via an internal API; we parse whatever the page
/// embeds and give up gracefully if nothing is found).
class DouyuFollowsFetcher {
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  Future<List<({String roomId, String name})>> fetchFollowedRooms(
    String uid,
  ) async {
    final result = <({String roomId, String name})>[];
    try {
      final cookie = DouyuAuth.instance.cookie;
      final response = await http
          .get(
            Uri.parse('https://www.douyu.com/directory/myFollow'),
            headers: {
              'User-Agent': _ua,
              'Cookie': cookie ?? '',
              'Referer': 'https://www.douyu.com/follow',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return result;
      final body = response.body.replaceAll(r'\"', '"');
      // Try the embedded JSON: pairs of "room_id" / "nickname".
      final roomIds = RegExp(
        r'room_id"?\s*[:=]\s*"?(\d+)',
      ).allMatches(body).map((m) => m.group(1)!).toSet();
      final names = RegExp(
        r'nickname"?\s*[:=]\s*"?([^"\\]+)',
      ).allMatches(body).map((m) => m.group(1)!).toList();
      final idList = roomIds.toList();
      for (var i = 0; i < idList.length; i++) {
        final name = i < names.length ? names[i] : 'Douyu Room ${idList[i]}';
        result.add((roomId: idList[i], name: name));
      }
    } catch (e) {
      // The page is client-rendered; an empty result is fine.
    }
    return result;
  }
}

/// Fetches the purchased work list of a DLsite user from the mypage.
class DlsiteLibraryFetcher {
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  Future<List<({String name, String url})>> fetchPurchased() async {
    final result = <({String name, String url})>[];
    try {
      final cookie = DLSiteAuth.instance.cookie;
      if (cookie == null || cookie.isEmpty) return result;
      // The purchased-goods page for RJ works (成人向 /maniax).
      final response = await http
          .get(
            Uri.parse('https://www.dlsite.com/maniax/mypage/order'),
            headers: {
              'User-Agent': _ua,
              'Cookie': cookie,
              'Referer': 'https://www.dlsite.com/',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return result;
      final body = utf8.decode(response.bodyBytes);
      // Work links look like /work/=/product/RJ012345.html
      final links = RegExp(r'/work/=/product/(RJ\d+)\.html').allMatches(body);
      final seen = <String>{};
      for (final m in links) {
        final rj = m.group(1)!;
        if (seen.contains(rj)) continue;
        seen.add(rj);
        // Try to grab the adjacent title text.
        final start = m.start;
        final ctxStart = start > 200 ? start - 200 : 0;
        final ctx = body.substring(ctxStart, start);
        final titleMatch = RegExp(r'>(.*?)</a>').allMatches(ctx).lastOrNull;
        final title = titleMatch?.group(1)?.trim() ?? 'RJ$rj';
        result.add((
          name: title,
          url: 'https://www.dlsite.com/work/=/product/$rj.html',
        ));
      }
    } catch (e) {
      // The mypage may need a different login state; return what we have.
    }
    return result;
  }
}
