// Debug: compare the Douyu signing flow for two rooms.
// Run: flutter test test/douyu_sign_debug_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:asmr_hub/sources/douyu/douyu_sign.dart';

const _ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

Future<void> _testRoom(String roomId) async {
  stdout.writeln('===== room $roomId =====');
  // Collect visitor cookies first (some rooms require them).
  final cookieJar = <String, String>{};
  void merge(http.Response r) {
    final raw = r.headers['set-cookie'];
    if (raw == null) return;
    for (final part in raw.split(',')) {
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      final key = part.substring(0, idx).trim();
      var value = part.substring(idx + 1);
      final semi = value.indexOf(';');
      if (semi >= 0) value = value.substring(0, semi);
      cookieJar[key] = value;
    }
  }

  final home = await http.get(
    Uri.parse('https://www.douyu.com/'),
    headers: {'User-Agent': _ua},
  );
  merge(home);
  final page0 = await http.get(
    Uri.parse('https://www.douyu.com/$roomId'),
    headers: {'User-Agent': _ua, 'Referer': 'https://www.douyu.com/'},
  );
  merge(page0);
  final cookieHeader = cookieJar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  stdout.writeln('visitor cookies: $cookieHeader');

  final enc = await http.get(
    Uri.parse('https://www.douyu.com/swf_api/homeH5Enc?rids=$roomId'),
    headers: {
      'User-Agent': _ua,
      'Referer': 'https://www.douyu.com/$roomId',
      if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
    },
  );
  merge(enc);
  stdout.writeln('homeH5Enc status=${enc.statusCode} ct=${enc.headers['content-type']}');
  final encJson = jsonDecode(enc.body) as Map<String, dynamic>;
  stdout.writeln('encJson error=${encJson['error']} msg=${encJson['msg']}');
  final data = encJson['data'] as Map<String, dynamic>?;
  final crptext = data?['room$roomId']?.toString();
  if (crptext == null || crptext.isEmpty) {
    stdout.writeln('NO CRYPTEXT');
    return;
  }
  stdout.writeln('crptext len=${crptext.length} head=${crptext.substring(0, 120)}');

  final sign = DouyuSign.getSign(crptext, roomId);
  stdout.writeln('sign: $sign');

  // Try both the given id and (when found) the real room id from the page.
  final ids = <String>[roomId];
  try {
    final page = await http.get(
      Uri.parse('https://www.douyu.com/$roomId'),
      headers: {'User-Agent': _ua, 'Referer': 'https://www.douyu.com/'},
    );
    final body = page.body.replaceAll(r'\"', '"');
    final realId = RegExp(r'"room_id"\s*:\s*(\d+)').firstMatch(body)?.group(1);
    if (realId != null && realId != roomId) {
      stdout.writeln('page real room_id=$realId');
      ids.add(realId);
    }
  } catch (_) {}

  for (final id in ids) {
    final s = DouyuSign.getSign(crptext, id);
    final body = '$s&cdn=&rate=-1&ver=Douyu_223061205&iar=1&ive=1&hevc=0&fa=0';
    final play = await http.post(
      Uri.parse('https://www.douyu.com/lapi/live/getH5Play/$id'),
      headers: {
        'User-Agent': _ua,
        'Referer': 'https://www.douyu.com/$roomId',
        'Content-Type': 'application/x-www-form-urlencoded',
        if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
      },
      body: body,
    );
    stdout.writeln('raw body head: ${play.body.substring(0, play.body.length > 300 ? 300 : play.body.length)}');
    final decoded = jsonDecode(play.body);
    final playJson = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'error': 'parse', 'msg': 'non-map: ${decoded.runtimeType}'};
    stdout.writeln(
      'getH5Play/$id error=${playJson['error']} msg=${playJson['msg']}',
    );
    final playData = playJson['data'];
    if (playData is Map<String, dynamic>) {
      final rtmpUrl = playData['rtmp_url']?.toString() ?? '';
      final rtmpLive = playData['rtmp_live']?.toString() ?? '';
      stdout.writeln('rtmp_url=$rtmpUrl rtmp_live=$rtmpLive');
    } else {
      stdout.writeln('data type: ${playData.runtimeType} = $playData');
    }
  }
}

void main() {
  test('douyu sign flow debug', () async {
    await _testRoom('3484');
    await _testRoom('92020');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
