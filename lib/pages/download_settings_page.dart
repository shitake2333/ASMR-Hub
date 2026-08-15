import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:asmr_hub/l10n/app_localizations.dart';
import 'package:asmr_hub/services/preferences_service.dart';

/// Download settings: max rate, concurrency and cache format.
class DownloadSettingsPage extends StatefulWidget {
  const DownloadSettingsPage({super.key});

  @override
  State<DownloadSettingsPage> createState() => _DownloadSettingsPageState();
}

class _DownloadSettingsPageState extends State<DownloadSettingsPage> {
  final TextEditingController _rateController = TextEditingController();
  int _maxThreads = 1;
  String _cacheFormat = 'mp3';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = PreferencesService();
    final rate = prefs.getMaxDownloadRate();
    final threads = prefs.getMaxDownloadThreads();
    final format = prefs.getCacheFormat();
    if (mounted) {
      setState(() {
        _rateController.text = rate.toString();
        _maxThreads = threads;
        _cacheFormat = format;
      });
    }
  }

  Future<void> _saveRate(String text) async {
    final value = int.tryParse(text) ?? 0;
    if (value < 0) return;
    await PreferencesService().setMaxDownloadRate(value);
  }

  Future<void> _setThreads(int value) async {
    if (value < 1) return;
    setState(() => _maxThreads = value);
    await PreferencesService().setMaxDownloadThreads(value);
  }

  Future<void> _pickCacheFormat(String format) async {
    setState(() => _cacheFormat = format);
    await PreferencesService().setCacheFormat(format);
  }

  String _formatSubtitle(AppLocalizations l10n) {
    switch (_cacheFormat) {
      case 'off':
        return l10n.cacheFormatOffSubtitle;
      case 'wav':
        return l10n.cacheFormatWavSubtitle;
      case 'flac':
        return l10n.cacheFormatFlacSubtitle;
      case 'mp3':
      default:
        return l10n.cacheFormatMp3Subtitle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.downloadSettings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                // Max download rate (KB/s, 0 = unlimited).
                ListTile(
                  leading: const Icon(Icons.speed),
                  title: Text(l10n.maxDownloadRate),
                  subtitle: Text(l10n.maxDownloadRateSubtitle),
                  trailing: SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _rateController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        suffixText: l10n.maxDownloadRateUnit,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: _saveRate,
                      onSubmitted: _saveRate,
                    ),
                  ),
                ),
                const Divider(height: 1),
                // Max concurrent threads.
                ListTile(
                  leading: const Icon(Icons.hub_outlined),
                  title: Text(l10n.maxDownloadThreads),
                  subtitle: Text(l10n.maxDownloadThreadsSubtitle),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _maxThreads > 1
                            ? () => _setThreads(_maxThreads - 1)
                            : null,
                      ),
                      Text('$_maxThreads', style: theme.textTheme.titleMedium),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => _setThreads(_maxThreads + 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Cache format.
          Card(
            child: ListTile(
              leading: const Icon(Icons.audio_file),
              title: Text(l10n.cacheFormat),
              subtitle: Text(_formatSubtitle(l10n)),
              trailing: DropdownButton<String>(
                value: _cacheFormat,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'off', child: Text('Off')),
                  DropdownMenuItem(value: 'wav', child: Text('WAV')),
                  DropdownMenuItem(value: 'flac', child: Text('FLAC')),
                  DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                ],
                onChanged: (value) {
                  if (value != null) _pickCacheFormat(value);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
