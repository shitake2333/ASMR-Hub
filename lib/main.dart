import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:nativeapi/nativeapi.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asmr_hub/constants.dart';
import 'package:asmr_hub/l10n/app_localizations.dart';
import 'package:asmr_hub/pages/player_page.dart';
import 'package:asmr_hub/pages/playlist_page.dart';
import 'package:asmr_hub/pages/settings_page.dart';
import 'package:asmr_hub/pages/source_page.dart';
import 'package:asmr_hub/pages/download_manager_page.dart';
import 'package:asmr_hub/providers/audio_provider.dart';
import 'package:asmr_hub/providers/auth_provider.dart';
import 'package:asmr_hub/providers/effects_provider.dart';
import 'package:asmr_hub/providers/playlist_provider.dart';
import 'package:asmr_hub/providers/theme_provider.dart';
import 'package:asmr_hub/services/download_manager.dart';
import 'package:asmr_hub/services/live_watch_manager.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/services/app_navigator.dart';
import 'package:asmr_hub/services/preferences_service.dart';
import 'package:asmr_hub/services/sleep_detection_service.dart';

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize Logger
      await LogService().initialize();
      // Log a startup banner on every launch.
      LogService().info(
        '===== ASMR Hub ${AppConstants.appVersion} started =====',
      );

      // Initialize Preferences
      await PreferencesService().init();

      // Route package loggers to the app log (media_kit etc.).
      Logger.root.level = kDebugMode ? Level.FINE : Level.INFO;
      Logger.root.onRecord.listen((record) {
        dev.log(
          record.message,
          time: record.time,
          level: record.level.value,
          name: record.loggerName,
          zone: record.zone,
          error: record.error,
          stackTrace: record.stackTrace,
        );
        final msg = record.message;
        if (record.level >= Level.SEVERE) {
          LogService().error(
            '[${record.loggerName}] $msg',
            record.error,
            record.stackTrace,
          );
        } else if (record.level >= Level.WARNING) {
          LogService().warning('[${record.loggerName}] $msg');
        } else {
          LogService().info('[${record.loggerName}] $msg');
        }
      });

      // Initialize libmpv (media_kit). On Windows the media_kit_libs package
      // bundles a libmpv-2.dll; a full build (with lavfi filters) can be
      // dropped next to the exe to replace the bundled one.
      MediaKit.ensureInitialized();

      // Initialize nativeapi WindowManager for cross-platform window
      // handling. This replaces the removed window_manager plugin and the
      // runner-level WM_CLOSE hacks (windows/runner). Note: as of
      // nativeapi 0.1.4 the Windows event dispatch is a placeholder and
      // there is no close event, so close-time state saving relies on the
      // AppLifecycleState.detached handler in _MainPageState below.
      try {
        WindowManager.instance.startEventListening();
      } catch (e) {
        LogService().error('Failed to init nativeapi window manager', e);
      }

      // Check for saved playlist to determine initial screen
      final prefs = await SharedPreferences.getInstance();
      final hasPlaylist = prefs.getString('audio_player_playlist') != null;
      final initialIndex = hasPlaylist ? 1 : 0;

      // Register App License
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks([
          ' ${AppConstants.appName}',
        ], AppConstants.appLicense);
      });

      // Setup global error handling
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        LogService().error('Flutter Error', details.exception, details.stack);
      };

      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux ||
              defaultTargetPlatform == TargetPlatform.macOS)) {
        // Window sizing is handled by the runner (windows/runner/main.cpp).
      }
      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => AudioPlayerProvider()..initialize(),
            ),
            ChangeNotifierProvider(
              create: (_) => AudioSourceProvider()..initialize(),
            ),
            ChangeNotifierProvider(
              create: (_) => PlaylistProvider()..initialize(),
            ),
            // Effects are applied to the player engine via a filter chain.
            ChangeNotifierProxyProvider<AudioPlayerProvider, EffectsProvider>(
              create: (_) => EffectsProvider(),
              update: (_, player, effects) {
                effects ??= EffectsProvider();
                effects.onFilterChainChanged = (chain) async {
                  await player.setAudioFilter(chain);
                };
                return effects;
              },
            ),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(
              create: (_) => DownloadManager.instance..start(),
            ),
            ChangeNotifierProvider(
              create: (_) => LiveWatchManager.instance..start(),
            ),
            ChangeNotifierProvider(
              // AuthProvider must initialize eagerly: it restores persisted
              // login sessions. With the default lazy=true it would only be
              // created when the account-management page first reads it, so
              // sessions would never be restored at startup.
              lazy: false,
              create: (_) => AuthProvider(prefs)..initialize(),
            ),
            ChangeNotifierProvider(create: (_) => SleepDetectionService()),
          ],
          child: ASMRHub(initialIndex: initialIndex),
        ),
      );
    },
    (error, stack) {
      LogService().error('Uncaught Error', error, stack);
    },
  );
}

class ASMRHub extends StatelessWidget {
  final int initialIndex;

  const ASMRHub({super.key, required this.initialIndex});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      title: AppConstants.appName,
      themeMode: themeProvider.themeMode,
      locale: themeProvider.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      supportedLocales: AppConstants.supportedLocales,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);

        // Wrap child with MediaQuery (text scale factor). The system window
        // title bar is used.
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(themeProvider.textScaleFactor),
          ),
          child: child!,
        );
      },
      theme: ThemeData(
        fontFamily: themeProvider.fontFamily,
        textTheme: Typography.material2021(
          platform: defaultTargetPlatform,
        ).black.apply(fontFamily: themeProvider.fontFamily),
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: themeProvider.seedColor,
              brightness: Brightness.light,
            ).copyWith(
              primary: themeProvider.seedColor,
              surface: const Color(0xFFFFFFFF),
              surfaceTint: Colors.transparent,
              primaryContainer: const Color(0xFFF2F2F2),
              onPrimaryContainer: const Color(0xFF1E1E1E),
              secondaryContainer: const Color(0xFFF2F2F2),
              onSecondaryContainer: const Color(0xFF1E1E1E),
              surfaceContainerHighest: const Color(0xFFE6E6E6),
              onSurfaceVariant: const Color(0xFF444746),
              surfaceContainer: const Color(0xFFEDEDED),
              surfaceContainerLow: const Color(0xFFF3F3F3),
              surfaceContainerHigh: const Color(0xFFE7E7E7),
              outline: const Color(0xFF79747E),
              outlineVariant: const Color(0xFFC4C7C5),
            ),
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
        navigationRailTheme: NavigationRailThemeData(
          indicatorColor: themeProvider.seedColor,
          selectedIconTheme: const IconThemeData(color: Colors.white),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
      ),
      darkTheme: ThemeData(
        fontFamily: themeProvider.fontFamily,
        textTheme: Typography.material2021(
          platform: defaultTargetPlatform,
        ).white.apply(fontFamily: themeProvider.fontFamily),
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: themeProvider.seedColor,
              brightness: Brightness.dark,
            ).copyWith(
              primary: themeProvider.seedColor,
              surface: const Color(0xFF1E1E1E),
              onSurface: const Color(0xFFE3E3E3),
              surfaceTint: Colors.transparent,
              primaryContainer: const Color(0xFF2A2A2A),
              onPrimaryContainer: const Color(0xFFE0E0E0),
              secondaryContainer: const Color(0xFF2A2A2A),
              onSecondaryContainer: const Color(0xFFE0E0E0),
              onSurfaceVariant: const Color(0xFFC4C7C5),
              surfaceContainer: const Color(0xFF252525),
              surfaceContainerLow: const Color(0xFF222222),
              surfaceContainerHigh: const Color(0xFF2B2B2B),
              surfaceContainerHighest: const Color(0xFF363636),
              outline: const Color(0xFF938F99),
              outlineVariant: const Color(0xFF444746),
            ),
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        navigationRailTheme: NavigationRailThemeData(
          indicatorColor: themeProvider.seedColor,
          selectedIconTheme: const IconThemeData(color: Colors.white),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
      ),
      home: MainPage(initialIndex: initialIndex),
    );
  }
}

class MainPage extends StatefulWidget {
  final int initialIndex;

  const MainPage({super.key, required this.initialIndex});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    WidgetsBinding.instance.addObserver(this);
    // Listen for cross-page tab requests (e.g. source page asks to jump to
    // the player after starting playback).
    AppNavigator.tabRequest.addListener(_onTabRequest);
  }

  void _onTabRequest() {
    final index = AppNavigator.tabRequest.value;
    if (index == null || index == _currentIndex) return;
    setState(() => _currentIndex = index);
    // Reset so the same tab can be re-requested later.
    AppNavigator.tabRequest.value = null;
  }

  @override
  void dispose() {
    AppNavigator.tabRequest.removeListener(_onTabRequest);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Synchronous marker: reliable even when async log queue never flushes
    // (e.g. the process is stuck during teardown).
    try {
      final tmp = Platform.environment['TEMP'] ?? '.';
      File(
        '$tmp${Platform.pathSeparator}asmr_hub_lifecycle.txt',
      ).writeAsStringSync(
        '[${DateTime.now().toIso8601String()}] $state\n',
        mode: FileMode.append,
      );
    } catch (_) {}
    LogService().info('[Lifecycle] state -> $state');
    if (!mounted) return;
    final player = context.read<AudioPlayerProvider>();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Save on pause and on window destruction (detached) so the current
      // position/playlist survives an abrupt exit. The mpv engine's native
      // threads do not block engine shutdown, so the process exits cleanly.
      player.saveState().catchError((Object e) {
        LogService().error('Failed to save state on lifecycle', e);
      });
    }
  }

  final List<Widget> _pages = [
    const SourcePageNew(),
    const PlayerPage(),
    const PlaylistPage(),
    const DownloadManagerPage(),
  ];

  final List<NavigationItem> _navigationItems = [
    NavigationItem(
      icon: Icons.radio_outlined,
      selectedIcon: Icons.radio,
      labelKey: 'navSource',
      titleKey: 'navSourceTitle',
    ),
    NavigationItem(
      icon: Icons.play_circle_outline,
      selectedIcon: Icons.play_circle,
      labelKey: 'navPlayer',
      titleKey: 'navPlayerTitle',
    ),
    NavigationItem(
      icon: Icons.queue_music_outlined,
      selectedIcon: Icons.queue_music,
      labelKey: 'navPlaylist',
      titleKey: 'navPlaylistTitle',
    ),
    NavigationItem(
      icon: Icons.download_outlined,
      selectedIcon: Icons.download,
      labelKey: 'navDownloads',
      titleKey: 'navDownloadsTitle',
    ),
  ];

  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
  }

  bool _isWideScreen(BuildContext context) {
    return MediaQuery.of(context).size.width >= 800;
  }

  @override
  Widget build(BuildContext context) {
    final isWide = _isWideScreen(context);
    final l10n = AppLocalizations.of(context)!;

    // Helper to get localized string from key
    String getLocalized(String key) {
      switch (key) {
        case 'navSource':
          return l10n.navSource;
        case 'navSourceTitle':
          return l10n.navSourceTitle;
        case 'navPlayer':
          return l10n.navPlayer;
        case 'navPlayerTitle':
          return l10n.navPlayerTitle;
        case 'navPlaylist':
          return l10n.navPlaylist;
        case 'navPlaylistTitle':
          return l10n.navPlaylistTitle;
        case 'navDownloads':
          return l10n.navDownloads;
        case 'navDownloadsTitle':
          return l10n.navDownloadsTitle;
        default:
          return '';
      }
    }

    if (isWide) {
      return _buildDesktopLayout(getLocalized);
    } else {
      return _buildMobileLayout(getLocalized);
    }
  }

  Widget _buildDesktopLayout(String Function(String) getLocalized) {
    return Scaffold(
      body: Row(
        children: [
          // Side Navigation Rail
          NavigationRail(
            selectedIndex: _currentIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _currentIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            backgroundColor: Theme.of(context).colorScheme.surface,
            elevation: 2,
            minWidth: 80,
            destinations: _navigationItems
                .map(
                  (item) => NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: Text(
                      getLocalized(item.labelKey),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                )
                .toList(),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: IconButton(
                    onPressed: _navigateToSettings,
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: AppLocalizations.of(context)!.settingsTooltip,
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // Main Content Area
          Expanded(
            child: Column(
              children: [
                // Page Header
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        getLocalized(_navigationItems[_currentIndex].titleKey),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                // Page Content
                Expanded(
                  child: IndexedStack(index: _currentIndex, children: _pages),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(String Function(String) getLocalized) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          getLocalized(_navigationItems[_currentIndex].titleKey),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            onPressed: _navigateToSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: AppLocalizations.of(context)!.settingsTooltip,
          ),
          const SizedBox(width: 8),
        ],
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _currentIndex = index;
          });
        },
        elevation: 8,
        destinations: _navigationItems
            .map(
              (item) => NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.selectedIcon),
                label: getLocalized(item.labelKey),
              ),
            )
            .toList(),
      ),
    );
  }
}

class NavigationItem {
  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
  final String titleKey;

  NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.labelKey,
    required this.titleKey,
  });
}
