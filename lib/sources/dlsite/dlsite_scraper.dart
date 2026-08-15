import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/sources/base/source_scraper.dart';
import 'package:asmr_hub/sources/dlsite/dlsite_auth.dart';

/// DLSite scraper.
///
/// Work info (title/cover) comes from the public product page. The audio
/// tracks themselves come from the DLsite Play API:
///
///   1. `play.dl.dlsite.com/api/v3/download/sign/cookie?workno={RJ}`
///      -> a signed download token ({url, expires}) — requires login.
///   2. `{url}ziptree.json` -> the file tree (track list).
///   3. `{url}optimized/{optimized_name}` -> the playable (optimized) file.
///
/// Track ids are `dlsite:{RJ}:{hashname}`; the stream URL is resolved fresh
/// on every play so the signed token never goes stale.
class DLSiteScraper implements SourceScraper {
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  final LogService _logger = LogService();

  String? getValidRjCode(String rjCode) {
    final regex = RegExp(
      r'play\.dlsite\.com/work/(RJ\d{6,})',
      caseSensitive: false,
    );
    final regexShort = RegExp(r'(RJ\d{6,})', caseSensitive: false);
    final m = regex.firstMatch(rjCode);
    if (m != null) return m.group(1);
    final ms = regexShort.firstMatch(rjCode);
    return ms?.group(1);
  }

  @override
  Future<List<AudioTrack>> scrapePlaylist(String url) async {
    final rj = getValidRjCode(url);
    if (rj == null) {
      throw Exception('Unrecognized DLSite URL: $url');
    }

    if (!DLSiteAuth.instance.isLoggedIn) {
      throw Exception('DLSite login required to fetch audio tracks');
    }

    final info = await _fetchWorkInfo(rj);
    final token = await _fetchToken(rj);
    final (playfile, tree) = await _fetchZiptree(token);

    final tracks = <AudioTrack>[];
    for (final entry in tree) {
      final playFile = playfile[entry.hashname];
      if (playFile == null) continue;
      final optimized = playFile['optimized'];
      if (optimized is! Map<String, dynamic>) continue; // not playable audio
      final name = optimized['name']?.toString() ?? '';
      if (name.isEmpty) continue;

      // Build a readable title from the tree path.
      final fileName = entry.path.split('/').last;
      final title = fileName.replaceAll(
        RegExp(r'\.(m4a|mp3|mp4|wav|aac)$'),
        '',
      );
      tracks.add(
        AudioTrack(
          id: 'dlsite:$rj:${entry.hashname}',
          title: title.isEmpty ? fileName : title,
          artist: info.$3.isEmpty ? 'DLsite' : info.$3,
          albumArt: info.$2.isEmpty ? null : info.$2,
          duration: Duration.zero,
          streamUrl: '',
          sourceTypeId: 'dlsite',
          metadata: {
            'rj': rj,
            'hashname': entry.hashname,
            'workTitle': info.$1,
          },
        ),
      );
    }
    return tracks;
  }

  @override
  Future<AudioTrack> scrapeVideo(String url) async {
    final rj = getValidRjCode(url);
    if (rj == null) {
      throw Exception('Unrecognized DLSite URL: $url');
    }
    final info = await _fetchWorkInfo(rj);
    return AudioTrack(
      id: rj,
      title: info.$1,
      artist: info.$3.isEmpty ? 'DLsite' : info.$3,
      albumArt: info.$2.isEmpty ? null : info.$2,
      duration: Duration.zero,
      streamUrl: '',
      sourceTypeId: 'dlsite',
      metadata: {'rj': rj},
    );
  }

  @override
  Future<String> scrapeStreamUrl(String trackId, {String? quality}) async {
    // dlsite:{RJ}:{hashname}
    final parts = trackId.split(':');
    if (parts.length < 3 || parts[0] != 'dlsite') {
      throw Exception('Invalid DLSite track id: $trackId');
    }
    final rj = parts[1];
    final hashname = parts.sublist(2).join(':');
    if (!DLSiteAuth.instance.isLoggedIn) {
      throw Exception('DLSite login required to play audio');
    }
    final token = await _fetchToken(rj);
    final (playfile, _) = await _fetchZiptree(token);
    final playFile = playfile[hashname];
    if (playFile == null) {
      throw Exception('Track not found: $hashname');
    }
    final optimized = playFile['optimized'];
    if (optimized is! Map<String, dynamic>) {
      throw Exception('Track has no playable file: $hashname');
    }
    final name = optimized['name']?.toString() ?? '';
    if (name.isEmpty) {
      throw Exception('Track has no playable file name: $hashname');
    }
    return '${token}optimized/$name';
  }

  // ---------------------------------------------------------------- internals

  /// Fetches the product page and extracts (title, cover, maker).
  Future<(String, String, String)> _fetchWorkInfo(String rj) async {
    try {
      final response = await http.get(
        Uri.parse('https://www.dlsite.com/maniax/work/=/product_id/$rj.html'),
        headers: {'User-Agent': _ua, 'Accept-Language': 'ja-JP'},
      );
      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        final ogTitle = RegExp(
          r'property="og:title"\s+content="([^"]+)"',
        ).firstMatch(body);
        final ogImage = RegExp(
          r'property="og:image"\s+content="([^"]+)"',
        ).firstMatch(body);
        var title = ogTitle?.group(1) ?? '';
        // "标题 [社团] | DLsite" — strip the trailing site suffix and maker.
        final siteIdx = title.indexOf(' | DLsite');
        if (siteIdx >= 0) title = title.substring(0, siteIdx);
        var maker = '';
        final makerMatch = RegExp(r'\[([^\]]+)\]$').firstMatch(title);
        if (makerMatch != null) {
          maker = makerMatch.group(1)!;
          title = title.substring(0, makerMatch.start).trim();
        }
        return (title.trim(), ogImage?.group(1) ?? '', maker);
      }
    } catch (e) {
      _logger.warning('Failed to fetch DLsite work info: $e');
    }
    return ('RJ$rj', '', '');
  }

  /// Requests a fresh signed download token.
  Future<String> _fetchToken(String rj) async {
    final cookie = DLSiteAuth.instance.cookie;
    if (cookie == null || cookie.isEmpty) {
      throw Exception('DLSite login required');
    }
    final response = await http.get(
      Uri.parse(
        'https://play.dl.dlsite.com/api/v3/download/sign/cookie?workno=$rj',
      ),
      headers: {
        'User-Agent': _ua,
        'Referer': 'https://play.dlsite.com/',
        'Cookie': cookie,
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        'DLSite token failed (${response.statusCode}) — '
        'work may not be purchased or the session expired',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final url = json['url']?.toString() ?? '';
    if (url.isEmpty) {
      throw Exception('DLSite token response missing url');
    }
    return url;
  }

  /// Fetches ziptree.json; returns (playfile map, tree entries).
  Future<(Map<String, Map<String, dynamic>>, List<_TreeEntry>)> _fetchZiptree(
    String tokenUrl,
  ) async {
    final response = await http.get(
      Uri.parse('${tokenUrl}ziptree.json'),
      headers: {'User-Agent': _ua, 'Referer': 'https://play.dlsite.com/'},
    );
    if (response.statusCode != 200) {
      throw Exception('DLSite ziptree failed (${response.statusCode})');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final playfile = <String, Map<String, dynamic>>{};
    final pf = json['playfile'] as Map<String, dynamic>? ?? {};
    pf.forEach((k, v) {
      if (v is Map<String, dynamic>) playfile[k] = v;
    });
    final tree = <_TreeEntry>[];
    final rawTree = json['tree'] as List<dynamic>? ?? [];
    for (final e in rawTree) {
      if (e is Map<String, dynamic>) {
        _parseTreeEntry(e, tree);
      }
    }
    return (playfile, tree);
  }

  void _parseTreeEntry(Map<String, dynamic> data, List<_TreeEntry> out) {
    final type = data['type']?.toString() ?? '';
    if (type == 'file') {
      out.add(
        _TreeEntry(
          hashname: data['hashname']?.toString() ?? '',
          path: data['name']?.toString() ?? '',
        ),
      );
    } else if (type == 'folder') {
      final parent = data['path']?.toString() ?? '';
      final children = data['children'] as List<dynamic>? ?? [];
      for (final c in children) {
        if (c is Map<String, dynamic>) {
          final childPath = c['name']?.toString() ?? '';
          _parseTreeEntry({
            ...c,
            'path': parent.isNotEmpty ? '$parent/$childPath' : childPath,
          }, out);
        }
      }
    }
  }
}

class _TreeEntry {
  final String hashname;
  final String path;

  _TreeEntry({required this.hashname, required this.path});
}
