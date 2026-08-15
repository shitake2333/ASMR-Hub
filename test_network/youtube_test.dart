// Verify the YouTube scraper: video URL -> track, stream URL resolution,
// playlist URL -> tracks.
// Run: flutter test test/youtube_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'package:asmr_hub/sources/youtube/youtube_scraper.dart';

void main() {
  test('youtube video resolves to a track with a playable stream', () async {
    final scraper = YouTubeScraper();
    final track = await scraper.scrapeVideo(
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    );
    expect(track.title, isNotEmpty);
    stdout.writeln('video: ${track.title} | ${track.artist} | '
        '${track.duration.inSeconds}s');
    final url = await scraper.scrapeStreamUrl(track.id);
    stdout.writeln('stream url head: ${url.substring(0, url.length > 80 ? 80 : url.length)}');
    expect(url.startsWith('http'), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('youtube playlist URL resolves to tracks', () async {
    final scraper = YouTubeScraper();
    // Diagnose: does the playlist metadata resolve at all?
    final yt = YoutubeExplode();
    final pl = await yt.playlists.get(
      'PLr6__5dJbDueMBy0VwW7HvISc-Q-Pt9ry',
    );
    stdout.writeln('playlist title: "${pl.title}"');
    final count = await yt.playlists.getVideos(
      'PLr6__5dJbDueMBy0VwW7HvISc-Q-Pt9ry',
    ).length;
    stdout.writeln('getVideos length: $count');
    yt.close();

    final tracks = await scraper.scrapePlaylist(
      'https://www.youtube.com/playlist?list=PLr6__5dJbDueMBy0VwW7HvISc-Q-Pt9ry',
    );
    expect(tracks, isNotEmpty, reason: 'playlist must have videos');
    stdout.writeln('scraper tracks: ${tracks.length}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
