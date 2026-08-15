// Volume persistence contract:
//  - The app model is 0-1 everywhere; the engine converts to mpv's 0-100 at
//    the boundary (MpvPlayerEngine.setVolume multiplies by 100).
//  - Saved/restored values must never be interpreted as 0-100, and muting
//    must not persist a 0 that would come back as "silent" after a restart.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asmr_hub/providers/audio_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('volume round-trips through prefs in the 0-1 model', () async {
    SharedPreferences.setMockInitialValues({});

    final provider = AudioPlayerProvider();
    await provider.loadState();
    expect(provider.volume, 1.0, reason: 'default volume is 100%');

    // User sets 30%.
    provider.setVolume(0.3);
    expect(provider.volume, 0.3);
    await Future<void>.delayed(Duration.zero); // let the async save land

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getDouble('audio_player_volume'),
      0.3,
      reason: 'persisted value must be 0.3 (0-1), never 30 (0-100)',
    );

    // A fresh provider (simulating app restart) restores 0.3.
    final restarted = AudioPlayerProvider();
    await restarted.loadState();
    expect(restarted.volume, 0.3, reason: 'restored volume is 30%');
  });

  test('muting keeps the real volume and does not persist 0', () async {
    SharedPreferences.setMockInitialValues({'audio_player_volume': 0.5});

    final provider = AudioPlayerProvider();
    await provider.loadState();
    expect(provider.volume, 0.5);

    provider.toggleMute();
    expect(provider.isMuted, isTrue);
    expect(
      provider.volume,
      0.5,
      reason: 'mute must only silence the engine, not zero the volume',
    );
    await Future<void>.delayed(Duration.zero);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('audio_player_volume'), 0.5);

    // Restart while muted: back at 50% (not silent).
    final restarted = AudioPlayerProvider();
    await restarted.loadState();
    expect(restarted.volume, 0.5);
    expect(restarted.isMuted, isFalse);
  });

  test('a stray 0-100 value is clamped, never stored as-is', () async {
    SharedPreferences.setMockInitialValues({});

    final provider = AudioPlayerProvider();
    await provider.loadState();

    // If anything upstream ever passes mpv-style 0-100 (e.g. 30), the model
    // must clamp it to 1.0 (100%) instead of persisting a bogus 30.
    provider.setVolume(30);
    expect(provider.volume, 1.0);
    await Future<void>.delayed(Duration.zero);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('audio_player_volume'), 1.0);
  });
}
