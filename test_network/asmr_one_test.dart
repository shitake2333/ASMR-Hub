// Verify the asmr.one scraper: work URL -> track list with playable URLs.
// Run: flutter test test/asmr_one_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_hub/sources/asmrone/asmr_one_scraper.dart';

void main() {
  test('asmr.one work URL resolves to playable tracks', () async {
    final scraper = AsmrOneScraper();
    final tracks = await scraper.scrapePlaylist('https://asmr.one/work/1657200');
    expect(tracks, isNotEmpty, reason: 'work must expose tracks');
    stdout.writeln('tracks: ${tracks.length}');
    for (final t in tracks.take(5)) {
      stdout.writeln(
        '  ${t.title} | ${t.artist} | ${t.duration.inSeconds}s | ${t.streamUrl}',
      );
    }
    // At least one track must have a playable stream URL.
    final withUrl = tracks.where((t) => t.streamUrl.isNotEmpty);
    expect(withUrl, isNotEmpty, reason: 'tracks must have mediaStreamUrl');
    expect(withUrl.first.streamUrl, contains('http'));
    // Duration must be parsed from the API.
    final withDuration = tracks.where((t) => t.duration > Duration.zero);
    expect(withDuration, isNotEmpty, reason: 'tracks must report duration');
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('asmr.one playlist id extraction', () {
    const url =
        'https://asmr.one/playlist?id=3fd297a0-b925-4523-b611-6271b035ef75';
    expect(
      AsmrOneScraper().extractPlaylistId(url),
      '3fd297a0-b925-4523-b611-6271b035ef75',
    );
  });
}
