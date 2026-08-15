import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:asmr_hub/services/mpv_player_engine.dart';

/// Integration test for the mpv engine (real libmpv on the host):
///  - opens a large local MP3
///  - reports duration + advancing position
///  - seek works
///  - lavfi audio filter applies without error
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Skip when libmpv is unavailable (e.g. CI without the native library).
  final canInit = _tryEnsure();
  if (!canInit) {
    test('mpv engine (skipped: libmpv unavailable)', () {}, skip: true);
    return;
  }

  test('mpv engine plays a large local file with seek + filter', () async {
    final files = Directory(r'D:\data\asmr_hub\bilibili')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.mp3'))
        .toList();
    expect(files, isNotEmpty, reason: 'need a local MP3 to play');

    final engine = MpvPlayerEngine();
    expect(engine.isAvailable, isTrue);

    final positions = <Duration>[];
    Duration? gotDuration;
    var completed = false;
    engine.onPositionChanged = () => positions.add(engine.position);
    engine.onDurationChanged = () => gotDuration = engine.duration;
    engine.onCompleted = () => completed = true;

    await engine.open(files.first.path);
    // Allow playback to progress.
    await Future<void>.delayed(const Duration(seconds: 4));

    expect(gotDuration, isNotNull);
    expect(gotDuration!.inSeconds, greaterThan(0));
    expect(positions.any((p) => p > Duration.zero), isTrue,
        reason: 'position should advance');

    // Seek forward.
    final before = engine.position;
    await engine.seek(before + const Duration(seconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(engine.position >= before, isTrue);

    // Apply a lavfi lowpass filter; must not throw.
    await engine.setAudioFilter('lavfi=[lowpass=f=3000:poles=2]');
    await Future<void>.delayed(const Duration(seconds: 1));

    await engine.stop();
    await engine.dispose();
    expect(completed, isFalse); // not finished within the short window
  });
}

bool _tryEnsure() {
  try {
    MediaKit.ensureInitialized();
    return true;
  } catch (_) {
    return false;
  }
}
