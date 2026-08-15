import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:asmr_hub/pages/player_page.dart';
import 'package:asmr_hub/providers/audio_provider.dart';
import 'package:asmr_hub/providers/effects_provider.dart';
import 'package:asmr_hub/services/sleep_detection_service.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:asmr_hub/l10n/app_localizations.dart';

void main() {
  testWidgets('PlayerPage desktop layout overflow test at min size', (
    WidgetTester tester,
  ) async {
    // Set desktop size 1024x720 (minimum size)
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1.0;

    // Reset size
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AudioPlayerProvider()),
          ChangeNotifierProvider(create: (_) => EffectsProvider()),
          ChangeNotifierProvider(create: (_) => SleepDetectionService()),
        ],
        child: MaterialApp(
          home: const PlayerPage(),
          theme: ThemeData(useMaterial3: true),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
        ),
      ),
    );

    // Allow animation to run one frame to capture layout
    await tester.pump();

    // Check for overflow errors
    // If there is an overflow, Flutter usually prints an error to the console, and tester.takeException() might capture it (depending on implementation),
    // but it is more reliable to see if there are RenderFlex overflowed error logs.
    // In flutter_test, overflow is usually treated as an exception thrown.
  });
}
