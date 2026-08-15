import 'package:asmr_hub/models/audio_models.dart';
import 'package:asmr_hub/services/audio_source_manager.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/services/preferences_service.dart';

/// Resolves the playback URL + HTTP headers for a track. Keeps the
/// per-source header rules in one place (Bilibili/Douyu/DLsite/asmr.one/
/// Twitch all need custom Referer/User-Agent/Client-ID headers for their
/// anti-hotlink CDNs).
class LiveStreamUrl {
  static const Map<String, String> biliHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://www.bilibili.com/',
  };

  static const Map<String, String> douyuHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://www.douyu.com/',
  };

  static const Map<String, String> dlsiteHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://play.dlsite.com/',
  };

  static const Map<String, String> asmrOneHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://asmr.one/',
  };

  static const Map<String, String> twitchHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Client-ID': 'kimne78kx3ncx6brgo4mv6wki5h1ko',
  };

  /// Headers for a track's stream URL, based on its source type.
  static Map<String, String>? headersFor(AudioTrack track) {
    switch (track.sourceTypeId) {
      case 'bilibili':
        return biliHeaders;
      case 'douyu':
        return douyuHeaders;
      case 'dlsite':
        return dlsiteHeaders;
      case 'asmrone':
        return asmrOneHeaders;
      case 'twitch':
        return twitchHeaders;
      default:
        return null;
    }
  }

  /// Whether [url] is an HTTP(S) URL.
  static bool isHttp(String url) => url.startsWith('http');

  /// Fetches the stream URL for [track] at the current quality preference.
  static Future<String> resolve(
    AudioSourceManager sourceManager,
    AudioTrack track, {
    String? quality,
  }) async {
    try {
      return await sourceManager.getStreamUrl(
        track,
        quality: quality ?? PreferencesService().getAudioQuality(),
      );
    } catch (e, stack) {
      LogService().error('Failed to resolve stream URL', e, stack);
      rethrow;
    }
  }
}
