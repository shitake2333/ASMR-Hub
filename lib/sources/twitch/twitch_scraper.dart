import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/services/preferences_service.dart';
import 'package:asmr_hub/sources/base/source_scraper.dart';

/// Twitch API client (anonymous).
///
/// Streams are fetched anonymously via Twitch's public GQL endpoint
/// (PlaybackAccessToken) + the usher playlist service. No login required for
/// audio-only playback of public channels.
class TwitchScraper extends SourceScraper {
  final LogService _logger = LogService();

  static const String _clientId = 'kimne78kx3ncx6brgo4mv6wki5h1ko';
  static const String _gql = 'https://gql.twitch.tv/gql';
  static const String _usher = 'https://usher.ttvnw.net';
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// The persisted-query hash for PlaybackAccessToken (streamlink's value).
  static const String _playbackHash =
      'ed230aa1e33e07eebb8928504583da78a5173989fadfb1ac94be06a04f3cdbe9';

  Map<String, String> get _headers => {
    'User-Agent': _ua,
    'Client-ID': _clientId,
  };

  /// Extracts the channel login (lowercase name) from a Twitch URL, or null.
  String? extractChannel(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final host = uri.host;
    if (!host.contains('twitch.tv')) return null;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return null;
    // Known non-channel prefixes.
    const prefixes = {'directory', 'downloads', 'videos', 'subscriptions'};
    if (prefixes.contains(segs.first)) return null;
    return segs.first.toLowerCase();
  }

  /// Fetches the stream playback access token (value + signature) for a
  /// live channel. Returns null when the channel is offline or unknown.
  Future<({String value, String signature})?> fetchAccessToken(
    String channel,
  ) async {
    final body = jsonEncode({
      'operationName': 'PlaybackAccessToken',
      'extensions': {
        'persistedQuery': {'version': 1, 'sha256Hash': _playbackHash},
      },
      'variables': {
        'isLive': true,
        'login': channel,
        'isVod': false,
        'vodID': '',
        'playerType': 'embed',
        'platform': 'site',
      },
    });
    try {
      final resp = await http.post(
        Uri.parse(_gql),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: body,
      );
      if (resp.statusCode != 200) {
        _logger.warning('Twitch GQL token failed: ${resp.statusCode}');
        return null;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['errors'] != null) return null; // offline/not found
      final tok =
          (data['data'] as Map<String, dynamic>?)?['streamPlaybackAccessToken']
              as Map<String, dynamic>?;
      if (tok == null) return null;
      final value = tok['value']?.toString();
      final signature = tok['signature']?.toString();
      if (value == null || signature == null || value.isEmpty) return null;
      return (value: value, signature: signature);
    } catch (e) {
      _logger.warning('Twitch GQL token error: $e');
      return null;
    }
  }

  /// Fetches the channel's HLS master playlist and returns the URL of the
  /// audio-only variant (empty when offline).
  Future<String> fetchAudioStreamUrl(String channel) async {
    final token = await fetchAccessToken(channel);
    if (token == null) return '';

    final rand = Random().nextInt(999999);
    final params =
        'platform=web&p=$rand&allow_source=true&allow_audio_only=true'
        '&playlist_include_framerate=true&supported_codecs=h264'
        '&sig=${token.signature}&token=${Uri.encodeQueryComponent(token.value)}'
        '&fast_bread=true';
    final url = '$_usher/api/v2/channel/hls/$channel.m3u8?$params';

    final resp = await http.get(Uri.parse(url), headers: _headers);
    if (resp.statusCode != 200) {
      _logger.warning('Twitch usher failed: ${resp.statusCode}');
      return '';
    }
    final master = resp.body;
    // Prefer audio_only; fall back to the lowest-bandwidth variant.
    final lines = master.split('\n');
    String? audioUrl;
    String? fallbackUrl;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#EXT-X-STREAM-INF')) {
        final next = i + 1 < lines.length ? lines[i + 1].trim() : '';
        if (next.startsWith('http')) {
          if (line.contains('audio_only')) {
            audioUrl ??= next;
          } else {
            fallbackUrl ??= next;
          }
        }
      }
    }
    return audioUrl ?? fallbackUrl ?? '';
  }

  /// Whether [channel] is currently live (StreamMetadata query).
  Future<bool> isChannelLive(String channel) async {
    try {
      final body = jsonEncode({
        'operationName': 'StreamMetadata',
        'extensions': {
          'persistedQuery': {
            'version': 1,
            'sha256Hash':
                'b57f9b910f8cd1a4659d894fe7550ccc81ec9052c01e438b290fd66a040b9b93',
          },
        },
        'variables': {'channelLogin': channel, 'includeIsDJ': true},
      });
      final resp = await http.post(
        Uri.parse(_gql),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: body,
      );
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final stream =
          ((data['data'] as Map<String, dynamic>?)?['user']
              as Map<String, dynamic>?)?['stream'];
      return stream != null;
    } catch (e) {
      _logger.warning('Twitch stream check error: $e');
      return false;
    }
  }

  // ------------------------------------------------------------- scraper

  @override
  Future<List<AudioTrack>> scrapePlaylist(String url) async {
    final channel = extractChannel(url);
    if (channel == null) {
      throw Exception('Unrecognized Twitch URL: $url');
    }
    final live = await isChannelLive(channel);
    return [
      AudioTrack(
        id: channel,
        title: 'Twitch Live $channel',
        artist: 'Twitch',
        duration: Duration.zero,
        streamUrl: '',
        sourceTypeId: 'twitch',
        metadata: {'isLive': live, 'isLiveCard': true, 'roomId': channel},
      ),
    ];
  }

  @override
  Future<AudioTrack> scrapeVideo(String url) async {
    final channel = extractChannel(url);
    if (channel == null) {
      throw Exception('Unrecognized Twitch URL: $url');
    }
    final live = await isChannelLive(channel);
    return AudioTrack(
      id: channel,
      title: 'Twitch Live $channel',
      artist: 'Twitch',
      duration: Duration.zero,
      streamUrl: '',
      sourceTypeId: 'twitch',
      metadata: {'isLive': live, 'isLiveCard': true, 'roomId': channel},
    );
  }

  @override
  Future<String> scrapeStreamUrl(String trackId, {String? quality}) async {
    // trackId is the channel login.
    return fetchAudioStreamUrl(trackId);
  }

  // ---------------------------------------------------------- recordings

  /// Directory where recordings of [channel] are stored (under the user's
  /// download folder so they are easy to find).
  Future<String> recordingsDir(String channel) async {
    final base = await PreferencesService().getDownloadPath();
    final sep = Platform.pathSeparator;
    return '$base${sep}twitch_recordings$sep$channel';
  }

  String recordingFileName(String title) {
    final safe = title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    return '${safe.isEmpty ? 'twitch' : safe}_$ts.mp3';
  }

  Future<List<AudioTrack>> loadRecordings(String channel) async {
    final dir = await recordingsDir(channel);
    final d = Directory(dir);
    if (!await d.exists()) return [];
    final tracks = <AudioTrack>[];
    await for (final f in d.list()) {
      if (f is! File) continue;
      final name = f.path.split(Platform.pathSeparator).last;
      tracks.add(
        AudioTrack(
          id: 'twitch-rec:$channel:$name',
          title: name.replaceAll(RegExp(r'_\d{4}-\d{2}-\d{2}.*\.mp3$'), ''),
          artist: 'Twitch',
          duration: Duration.zero,
          streamUrl: f.path,
          sourceTypeId: 'twitch',
          metadata: {'isRecording': true},
        ),
      );
    }
    return tracks;
  }
}
