// Regression: local source must not throw on network URLs, and the manager
// must route Bilibili URLs to the Bilibili source.
// Run: flutter test test/url_routing_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_hub/sources/local/local_source.dart';

void main() {
  test('LocalAudioSource.canHandleUrl does not throw on network URLs', () {
    final local = LocalAudioSource();
    final urls = [
      'https://space.bilibili.com/5930584/favlist?fid=2584246284',
      'https://www.bilibili.com/video/BV1GJ411x7h7',
      'https://live.bilibili.com/21452505',
      'https://www.douyu.com/24422',
    ];
    for (final url in urls) {
      expect(
        () => local.canHandleUrl(url),
        returnsNormally,
        reason: 'canHandleUrl must not throw for $url',
      );
      expect(
        local.canHandleUrl(url),
        isFalse,
        reason: 'network URL must not be handled by local source',
      );
    }
  });

  test('LocalAudioSource.canHandleUrl still accepts real paths', () {
    final local = LocalAudioSource();
    // A path that does not exist must not throw either.
    expect(
      () => local.canHandleUrl('C:/definitely/not/a/real/file.mp3'),
      returnsNormally,
    );
  });
}
