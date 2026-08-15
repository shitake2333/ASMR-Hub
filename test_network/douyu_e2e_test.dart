// End-to-end verification of the Douyu source against the live site.
// Run: flutter test test/douyu_e2e_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_hub/sources/douyu/douyu_source.dart';

void main() {
  const roomUrl = 'https://www.douyu.com/24422';

  test('DouyuSource parses room URL', () async {
    final source = DouyuSource();
    expect(source.canHandleUrl(roomUrl), isTrue);
    expect(source.canHandleUrl('https://example.com/foo'), isFalse);

    final track = await source.parseFromUrl(roomUrl);
    expect(track, isNotNull);
    expect(track!.sourceTypeId, 'douyu');
    expect(track.metadata?['isLive'], isTrue);
    expect(track.id, isNotEmpty);
  });

  test('DouyuSource fetches live stream URL', () async {
    final source = DouyuSource();
    final track = await source.parseFromUrl(roomUrl);
    expect(track, isNotNull);

    final streamUrl = await source.getStreamUrl(track!.id);
    expect(streamUrl, isNotEmpty);
    expect(streamUrl, startsWith('http'));
    // Douyu currently serves FLV streams.
    expect(streamUrl.contains('.flv') || streamUrl.contains('m3u8'), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
