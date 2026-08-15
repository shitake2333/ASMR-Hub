import 'package:flutter/material.dart';

import 'package:asmr_hub/l10n/app_localizations.dart';
import 'package:asmr_hub/services/audio_storage_service.dart';
import 'package:asmr_hub/services/source_import_service.dart';

/// Two-step import picker:
///  1. Choose a platform + type (e.g. "Bilibili Favorites").
///  2. Check the individual entries of that type and import them.
class ImportSourcesPage extends StatefulWidget {
  const ImportSourcesPage({super.key});

  @override
  State<ImportSourcesPage> createState() => _ImportSourcesPageState();
}

class _ImportSourcesPageState extends State<ImportSourcesPage> {
  final SourceImportService _service = SourceImportService();
  final AudioStorageService _storage = AudioStorageService();

  // Step 1 state.
  List<ImportGroup> _groups = [];
  bool _loadingGroups = true;
  String? _error;

  // Step 2 state.
  ImportGroup? _activeGroup;
  List<ImportedSource> _entries = [];
  bool _loadingEntries = false;
  final Set<String> _selected = {}; // keys: 'groupId|url'
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _loadingGroups = true;
      _error = null;
    });
    try {
      final groups = await _service.discoverGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loadingGroups = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingGroups = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openGroup(ImportGroup group) async {
    if (!group.available) return;
    setState(() {
      _activeGroup = group;
      _loadingEntries = true;
      _entries = [];
      _selected.clear();
    });
    try {
      final entries = await _service.loadGroupEntries(group.id);
      if (!mounted || _activeGroup?.id != group.id) return;
      setState(() {
        _entries = entries;
        _loadingEntries = false;
      });
    } catch (e) {
      if (!mounted || _activeGroup?.id != group.id) return;
      setState(() {
        _loadingEntries = false;
        _error = e.toString();
      });
    }
  }

  void _backToGroups() {
    setState(() {
      _activeGroup = null;
      _entries = [];
      _selected.clear();
    });
  }

  void _toggleEntry(ImportedSource entry, bool value) {
    final key = '${_activeGroup!.id}|${entry.url}';
    setState(() {
      if (value) {
        _selected.add(key);
      } else {
        _selected.remove(key);
      }
    });
  }

  Future<void> _importSelected() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.importNoSelection),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final entries = _entries
          .where((e) => _selected.contains('${_activeGroup!.id}|${e.url}'))
          .toList();
      final existing = await _storage.loadSources();
      final existingIds = existing.map((s) => s.id).toSet();
      var added = 0;
      for (final e in entries) {
        final asmr = e.toAsmrSource();
        if (existingIds.contains(asmr.id)) continue;
        existing.add(asmr);
        existingIds.add(asmr.id);
        added++;
      }
      await _storage.saveSources(existing);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.importResult(added))));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _groupTitle(ImportGroup group, AppLocalizations l10n) {
    switch (group.id) {
      case 'bilibili_favorites':
        return l10n.importBilibiliFavorites;
      case 'bilibili_followings':
        return l10n.importBilibiliFollowings;
      case 'asmrone_playlists':
        return l10n.importAsmrOnePlaylists;
      case 'douyu_follows':
        return l10n.importDouyuFollows;
      case 'dlsite_library':
        return l10n.importDlsiteLibrary;
      default:
        return group.title;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Step 2: entry selection for an active group.
    if (_activeGroup != null) {
      return _buildStep2(context, l10n);
    }

    // Step 1: choose platform + type.
    return Scaffold(
      appBar: AppBar(title: Text(l10n.importSelectTitle)),
      body: _loadingGroups
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _loadGroups,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _groups.isEmpty
          ? Center(child: Text(l10n.importEmpty))
          : ListView(
              padding: const EdgeInsets.all(8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  child: Text(
                    l10n.importSelectHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                for (final group in _groups)
                  ListTile(
                    enabled: group.available,
                    leading: Icon(
                      group.available ? Icons.folder_open : Icons.lock_outline,
                    ),
                    title: Text(_groupTitle(group, l10n)),
                    subtitle: group.available
                        ? Text(group.sourceTypeId)
                        : Text(l10n.importNotLoggedIn),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: group.available ? () => _openGroup(group) : null,
                  ),
              ],
            ),
    );
  }

  Widget _buildStep2(BuildContext context, AppLocalizations l10n) {
    final group = _activeGroup!;
    final selectedCount = _selected.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(_groupTitle(group, l10n)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _saving ? null : _backToGroups,
        ),
      ),
      body: _loadingEntries
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? Center(child: Text(l10n.importEmpty))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final entry = _entries[index];
                      return CheckboxListTile(
                        dense: true,
                        value: _selected.contains('${group.id}|${entry.url}'),
                        onChanged: _saving
                            ? null
                            : (v) => _toggleEntry(entry, v ?? false),
                        title: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: entry.subtitle != null
                            ? Text(
                                entry.subtitle!,
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            : null,
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving || selectedCount == 0
                            ? null
                            : _importSelected,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download),
                        label: Text(l10n.importSelected(selectedCount)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
