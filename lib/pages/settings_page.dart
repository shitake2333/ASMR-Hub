import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:system_fonts/system_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:asmr_hub/l10n/app_localizations.dart';
import 'package:asmr_hub/constants.dart';
import '../providers/theme_provider.dart';
import '../services/preferences_service.dart';
import 'source_management_page.dart';
import 'log_viewer_page.dart';
import 'cache_management_page.dart';
import 'download_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _cachePath = '';
  String _downloadPath = '';
  String _audioQuality = 'auto';

  @override
  void initState() {
    super.initState();
    _loadPaths();
  }

  Future<void> _loadPaths() async {
    final cachePath = await PreferencesService().getCachePath();
    final downloadPath = await PreferencesService().getDownloadPath();
    final audioQuality = PreferencesService().getAudioQuality();
    if (mounted) {
      setState(() {
        _cachePath = cachePath;
        _downloadPath = downloadPath;
        _audioQuality = audioQuality;
      });
    }
  }

  Future<void> _pickAudioQuality(String quality) async {
    await PreferencesService().setAudioQuality(quality);
    if (mounted) {
      setState(() => _audioQuality = quality);
    }
  }

  Future<void> _pickPath(bool isCache) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      if (isCache) {
        await PreferencesService().setCachePath(result);
      } else {
        await PreferencesService().setDownloadPath(result);
      }
      await _loadPaths();
    }
  }

  Future<void> _resetPaths() async {
    await PreferencesService().resetPaths();
    await _loadPaths();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: AppConstants.snackBarDuration,
          content: Text(
            AppLocalizations.of(context)!.pathReset,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onInverseSurface,
            ),
          ),
        ),
      );
    }
  }

  String _qualityLabel(String q) {
    switch (q) {
      case 'auto':
        return AppLocalizations.of(context)!.qualityAuto;
      case 'flac':
        return 'FLAC 无损';
      case '320':
        return '320 kbps';
      case '192':
        return '192 kbps';
      case '132':
        return '132 kbps';
      case '64':
        return '64 kbps';
      default:
        return q;
    }
  }

  String _audioQualityLabel() {
    return AppLocalizations.of(context)!.audioQualitySubtitle;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.settingsTitle),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Account Settings
          _buildSectionHeader(AppLocalizations.of(context)!.accountSettings),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.account_circle),
                  title: Text(
                    AppLocalizations.of(context)!.sourceAccountManagement,
                  ),
                  subtitle: Text(
                    AppLocalizations.of(
                      context,
                    )!.sourceAccountManagementSubtitle,
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SourceManagementPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Appearance Settings
          _buildSectionHeader(AppLocalizations.of(context)!.appearanceSettings),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(AppLocalizations.of(context)!.language),
                  subtitle: Text(
                    AppLocalizations.of(context)!.languageSubtitle,
                  ),
                  trailing: DropdownButton<Locale>(
                    value: themeProvider.locale ?? const Locale('en'),
                    underline: Container(),
                    items: AppConstants.supportedLocales.map((locale) {
                      return DropdownMenuItem(
                        value: locale,
                        child: Text(
                          AppConstants.getLanguageName(locale),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      );
                    }).toList(),
                    onChanged: (Locale? newLocale) {
                      if (newLocale != null) {
                        themeProvider.setLocale(newLocale);
                      }
                    },
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(AppLocalizations.of(context)!.darkMode),
                  subtitle: Text(
                    AppLocalizations.of(context)!.darkModeSubtitle,
                  ),
                  value: themeProvider.themeMode == ThemeMode.dark,
                  onChanged: (value) {
                    themeProvider.setThemeMode(
                      value ? ThemeMode.dark : ThemeMode.light,
                    );
                  },
                  secondary: const Icon(Icons.dark_mode),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.color_lens),
                  title: Text(AppLocalizations.of(context)!.themeColor),
                  subtitle: Text(
                    AppLocalizations.of(context)!.themeColorSubtitle,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: AppConstants.themeColors.map((color) {
                      final isSelected = themeProvider.seedColor == color;
                      return GestureDetector(
                        onTap: () => themeProvider.setSeedColor(color),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    width: 2,
                                  )
                                : null,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 24,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.text_fields),
                  title: Text(AppLocalizations.of(context)!.fontSettings),
                  subtitle: Text(
                    AppLocalizations.of(context)!.fontSettingsSubtitle,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!kIsWeb &&
                          (Platform.isWindows ||
                              Platform.isLinux ||
                              Platform.isMacOS)) ...[
                        Row(
                          children: [
                            Text(AppLocalizations.of(context)!.fontFamily),
                            const Spacer(),
                            _AsyncFontSelector(
                              initial: themeProvider.fontFamily,
                              onFontSelected: (value) {
                                themeProvider.setFontFamily(value);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        children: [
                          Text(AppLocalizations.of(context)!.fontSize),
                          const Spacer(),
                          Text(
                            '${(themeProvider.textScaleFactor * 100).round()}%',
                          ),
                        ],
                      ),
                      Slider(
                        value: themeProvider.textScaleFactor,
                        min: 0.8,
                        max: 1.5,
                        divisions: 7,
                        label:
                            '${(themeProvider.textScaleFactor * 100).round()}%',
                        onChanged: (value) {
                          themeProvider.setTextScaleFactor(value);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Playback Settings (audio quality).
          _buildSectionHeader(AppLocalizations.of(context)!.playbackSettings),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text(AppLocalizations.of(context)!.audioQuality),
                  subtitle: Text(_audioQualityLabel()),
                  trailing: DropdownButton<String>(
                    value: _audioQuality,
                    underline: const SizedBox.shrink(),
                    items: ['auto', 'flac', '320', '192', '132', '64']
                        .map(
                          (q) => DropdownMenuItem(
                            value: q,
                            child: Text(_qualityLabel(q)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) _pickAudioQuality(value);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Storage Settings
          _buildSectionHeader(AppLocalizations.of(context)!.storageSettings),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text(AppLocalizations.of(context)!.cachePath),
                  subtitle: Text(_cachePath),
                  trailing: const Icon(Icons.folder_open),
                  onTap: () => _pickPath(true),
                ),
                ListTile(
                  title: Text(AppLocalizations.of(context)!.downloadPath),
                  subtitle: Text(_downloadPath),
                  trailing: const Icon(Icons.folder_open),
                  onTap: () => _pickPath(false),
                ),
                ListTile(
                  title: Text(AppLocalizations.of(context)!.resetPath),
                  subtitle: Text(
                    AppLocalizations.of(context)!.resetPathSubtitle,
                  ),
                  trailing: const Icon(Icons.restore),
                  onTap: _resetPaths,
                ),
                ListTile(
                  title: Text(AppLocalizations.of(context)!.downloadSettings),
                  subtitle: Text(
                    AppLocalizations.of(context)!.downloadSettingsSubtitle,
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DownloadSettingsPage(),
                      ),
                    );
                  },
                ),
                ListTile(
                  title: Text(AppLocalizations.of(context)!.storageManagement),
                  subtitle: Text(
                    AppLocalizations.of(context)!.storageManagementSubtitle,
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CacheManagementPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Other Settings
          _buildSectionHeader(AppLocalizations.of(context)!.otherSettings),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bug_report),
                  title: Text(AppLocalizations.of(context)!.systemLog),
                  subtitle: Text(
                    AppLocalizations.of(context)!.systemLogSubtitle,
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LogViewerPage(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(AppLocalizations.of(context)!.aboutApp),
                  subtitle: Text(
                    AppLocalizations.of(context)!.aboutAppSubtitle,
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    _showAboutDialog();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: Text(AppLocalizations.of(context)!.githubRepo),
                  subtitle: Text(
                    AppLocalizations.of(context)!.githubRepoSubtitle,
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () async {
                    final Uri url = Uri.parse(AppConstants.githubUrl);
                    if (!await launchUrl(url)) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            duration: AppConstants.snackBarDuration,
                            content: Text(
                              'Could not launch $url',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onInverseSurface,
                                  ),
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: AppConstants.appVersion,
      applicationIcon: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.headphones, color: Colors.white, size: 32),
      ),
      children: [
        Text(
          AppLocalizations.of(context)!.appDescription,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Text(
          AppLocalizations.of(context)!.developer(AppConstants.appDeveloper),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          AppLocalizations.of(context)!.email(AppConstants.appEmail),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Async font selector: enumerating system fonts is expensive on desktop
/// (registry scan), so it is done in a background isolate instead of
/// blocking the settings page build.
class _AsyncFontSelector extends StatefulWidget {
  final String? initial;
  final ValueChanged<String?> onFontSelected;

  const _AsyncFontSelector({
    required this.initial,
    required this.onFontSelected,
  });

  @override
  State<_AsyncFontSelector> createState() => _AsyncFontSelectorState();
}

class _AsyncFontSelectorState extends State<_AsyncFontSelector> {
  List<String> _fonts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFonts();
  }

  Future<void> _loadFonts() async {
    List<String> fonts;
    try {
      fonts = await compute(_listSystemFonts, true);
    } catch (e) {
      // Font enumeration failed (e.g. registry access): fall back to an
      // empty list so the dropdown still renders with the default option.
      fonts = const [];
    }
    if (!mounted) return;
    setState(() {
      _fonts = fonts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 120,
        height: 32,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final options = <String>['', ..._fonts];
    // The theme falls back to a CJK default when no font is chosen. Only
    // pass a value that exists in the options, otherwise the dropdown
    // assertion throws (e.g. a stale invalid name persisted earlier).
    String current = '';
    final initial = widget.initial;
    if (initial != null &&
        initial != ThemeProvider.defaultFontFamily &&
        options.contains(initial)) {
      current = initial;
    }
    return DropdownButton<String>(
      value: current,
      underline: Container(),
      items: options
          .map(
            (f) => DropdownMenuItem(
              value: f,
              child: Text(
                f.isEmpty ? AppLocalizations.of(context)!.defaultFont : f,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          widget.onFontSelected(value.isEmpty ? null : value);
        }
      },
    );
  }
}

/// Runs in a background isolate.
///
/// system_fonts returns raw file names ("simhei", "msyh", "segoeui") that
/// Flutter cannot apply via `fontFamily` — only DirectWrite family names
/// work. Read the Windows font registry instead, which stores real family
/// names ("Microsoft YaHei UI", "SimSun", "Noto Sans SC", ...).
List<String> _listSystemFonts(bool _) {
  try {
    final names = <String>{};
    final reg = Process.runSync('reg', [
      'query',
      r'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
    ]);
    if (reg.exitCode == 0) {
      for (final line in (reg.stdout as String).split('\n')) {
        final t = line.trim();
        if (t.isEmpty || !t.contains('(TrueType)')) continue;
        final name = t.split('(TrueType)').first.trim();
        if (name.isEmpty) continue;
        // Strip weight suffixes so the picker lists the family once
        // ("Microsoft YaHei Bold & ... UI Bold" -> "Microsoft YaHei UI").
        var family = name
            .split('&')
            .first
            .trim()
            .replaceAll(
              RegExp(r'\s*(Bold|Light|Medium|Semibold|Black|Thin|Regular)\s*$'),
              '',
            )
            .trim();
        if (family.isNotEmpty) names.add(family);
      }
    }
    return names.toList()..sort();
  } catch (_) {
    // Fall back to system_fonts (filtered to names with spaces).
    final all = SystemFonts().getFontList();
    final seen = <String>{};
    final result = <String>[];
    for (final f in all) {
      final t = f.trim();
      if (t.isEmpty || !t.contains(' ')) continue;
      if (seen.contains(t)) continue;
      seen.add(t);
      result.add(t);
    }
    return result;
  }
}
