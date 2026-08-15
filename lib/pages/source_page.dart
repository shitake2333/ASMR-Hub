import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:asmr_hub/l10n/app_localizations.dart';
import 'package:asmr_hub/constants.dart';
import '../services/audio_source.dart';
import '../models/asmr_source.dart';
import '../models/audio_models.dart';
import '../providers/audio_provider.dart';
import '../services/audio_storage_service.dart';
import '../services/audio_source_manager.dart';
import '../services/app_navigator.dart';
import '../services/log_service.dart';
import 'source_detail_page.dart';
import 'import_sources_page.dart';

class SourcePageNew extends StatefulWidget {
  const SourcePageNew({super.key});

  @override
  State<SourcePageNew> createState() => _SourcePageState();
}

class _SourcePageState extends State<SourcePageNew> {
  final TextEditingController _searchController = TextEditingController();
  final AudioStorageService _storageService = AudioStorageService();
  final AudioSourceManager _sourceManager = AudioSourceManager();

  List<ASMRSource> _mySources = [];

  // Filters
  String? _filterSourceId;
  bool? _filterIsLive;
  final List<String> _filterTags = [];

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    final sources = await _storageService.loadSources();
    if (mounted) {
      setState(() {
        _mySources = sources;
      });
    }
  }

  Future<void> _addSource(ASMRSource source) async {
    setState(() {
      _mySources.add(source);
    });
    await _storageService.saveSources(_mySources);
  }

  bool _importing = false;

  /// Opens the import picker: user selects platform/type/entries, then the
  /// chosen sources are added to the "my sources" list.
  Future<void> _importFromAccounts() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ImportSourcesPage()),
      );
      // Reload after import so newly added sources appear immediately.
      await _loadSources();
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _removeSource(String id) async {
    setState(() {
      _mySources.removeWhere((s) => s.id == id);
    });
    await _storageService.saveSources(_mySources);
  }

  Future<void> _updateSource(ASMRSource updatedSource) async {
    setState(() {
      final index = _mySources.indexWhere((s) => s.id == updatedSource.id);
      if (index != -1) {
        _mySources[index] = updatedSource;
      }
    });
    await _storageService.saveSources(_mySources);
  }

  /// Renames a source entry (long-press on the tile).
  Future<void> _renameSource(ASMRSource source) async {
    final controller = TextEditingController(text: source.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.renameSource),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.renameSourceHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(AppLocalizations.of(context)!.confirm),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || newName == source.name) return;
    await _updateSource(
      ASMRSource(
        id: source.id,
        name: newName,
        url: source.url,
        sourceTypeId: source.sourceTypeId,
        tags: source.tags,
        addedDate: source.addedDate,
      ),
    );
  }

  Future<void> _playSource(ASMRSource source) async {
    try {
      List<AudioTrack> tracks = [];
      try {
        tracks = await _sourceManager.getPlaylist(source.url);
      } catch (e) {
        // ignore
      }

      if (tracks.isEmpty) {
        final track = await _sourceManager.parseUrl(source.url);
        if (track != null) tracks = [track];
      }

      if (!mounted) return;

      if (tracks.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: AppConstants.snackBarDuration,
            content: Text(AppLocalizations.of(context)!.noAudioFilesFound),
          ),
        );
        return;
      }

      final playerProvider = context.read<AudioPlayerProvider>();
      for (final track in tracks) {
        playerProvider.addToPlaylist(track);
      }
      await playerProvider.play(tracks.first);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: AppConstants.snackBarDuration,
            content: Text(
              AppLocalizations.of(context)!.startPlayingCount(tracks.length),
            ),
          ),
        );
        // Jump to the player tab (index 1 in the main shell).
        AppNavigator.goToTab(1);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: AppConstants.snackBarDuration,
            content: Text(
              AppLocalizations.of(context)!.loadingFailed(e.toString()),
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showAddSourceDialog() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final tagsController = TextEditingController();
    final sources = _sourceManager.getSources();
    String selectedSourceTypeId = sources.first.sourceTypeId;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                AppLocalizations.of(context)!.addSourceTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(
                          context,
                        )!.sourceNameLabel,
                        hintText: AppLocalizations.of(context)!.sourceNameHint,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedSourceTypeId,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(
                                context,
                              )!.sourceTypeLabel,
                            ),
                            items: sources.map((source) {
                              return DropdownMenuItem(
                                value: source.sourceTypeId,
                                child: Row(
                                  children: [
                                    source.getIcon(context, size: 16),
                                    const SizedBox(width: 8),
                                    Text(
                                      source.sourceTypeId == 'local'
                                          ? AppLocalizations.of(
                                              context,
                                            )!.sourceLocal
                                          : source.sourceName,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => selectedSourceTypeId = value);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Help button: shows this source's help text (each
                        // source provides its own description).
                        Builder(
                          builder: (context) {
                            final selected = sources.firstWhere(
                              (s) => s.sourceTypeId == selectedSourceTypeId,
                              orElse: () => sources.first,
                            );
                            final help = selected.helpText;
                            if (help == null || help.trim().isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return IconButton(
                              icon: const Icon(Icons.help_outline),
                              tooltip: AppLocalizations.of(context)!.sourceHelp,
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    title: Row(
                                      children: [
                                        selected.getIcon(
                                          dialogContext,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            selected.sourceTypeId == 'local'
                                                ? AppLocalizations.of(
                                                    dialogContext,
                                                  )!.sourceLocal
                                                : selected.sourceName,
                                            style: Theme.of(
                                              dialogContext,
                                            ).textTheme.titleLarge,
                                          ),
                                        ),
                                      ],
                                    ),
                                    content: SingleChildScrollView(
                                      child: Text(
                                        help,
                                        style: Theme.of(dialogContext)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(height: 1.5),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext),
                                        child: Text(
                                          AppLocalizations.of(
                                            dialogContext,
                                          )!.close,
                                          style: Theme.of(
                                            dialogContext,
                                          ).textTheme.labelLarge,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (selectedSourceTypeId == 'local')
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: urlController,
                                  decoration: InputDecoration(
                                    labelText: AppLocalizations.of(
                                      context,
                                    )!.localPathLabel,
                                    hintText: AppLocalizations.of(
                                      context,
                                    )!.localPathHint,
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    FilePickerResult? result = await FilePicker
                                        .platform
                                        .pickFiles();
                                    if (result != null &&
                                        result.files.single.path != null) {
                                      urlController.text =
                                          result.files.single.path!;
                                    }
                                  },
                                  icon: const Icon(Icons.insert_drive_file),
                                  label: Text(
                                    AppLocalizations.of(context)!.selectFile,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    String? selectedDirectory = await FilePicker
                                        .platform
                                        .getDirectoryPath();
                                    if (selectedDirectory != null) {
                                      urlController.text = selectedDirectory;
                                    }
                                  },
                                  icon: const Icon(Icons.folder),
                                  label: Text(
                                    AppLocalizations.of(context)!.selectFolder,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    else
                      TextField(
                        controller: urlController,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!.urlPathLabel,
                          hintText: AppLocalizations.of(context)!.urlPathHint,
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: tagsController,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.tagsLabel,
                        hintText: AppLocalizations.of(context)!.tagsHint,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    AppLocalizations.of(context)!.cancel,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isNotEmpty &&
                        urlController.text.isNotEmpty) {
                      if (selectedSourceTypeId != 'local') {
                        try {
                          final source = _sourceManager.getSources().firstWhere(
                            (s) => s.sourceTypeId == selectedSourceTypeId,
                          );
                          try {
                            await source.parseFromUrl(urlController.text);
                          } catch (e) {
                            if (e is AudioSourceException &&
                                e.type ==
                                    AudioSourceExceptionType.playlistUrl) {
                              // Valid playlist URL, continue
                            } else {
                              rethrow;
                            }
                          }
                        } catch (e) {
                          // Log the failure so it can be diagnosed, then show
                          // a clear error to the user.
                          LogService().error(
                            'Failed to validate source URL: '
                            '${urlController.text}',
                            e,
                            StackTrace.current,
                          );
                          if (context.mounted) {
                            await showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.loadingFailed(e.toString()),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                content: SingleChildScrollView(
                                  child: Text(
                                    e.toString(),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                          }
                          return;
                        }
                      }

                      final tags = tagsController.text
                          .split(',')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .toList();

                      final newSource = ASMRSource(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: nameController.text,
                        url: urlController.text,
                        sourceTypeId: selectedSourceTypeId,
                        tags: tags,
                        addedDate: DateTime.now(),
                      );
                      _addSource(newSource);
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    }
                  },
                  child: Text(
                    AppLocalizations.of(context)!.add,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    // Release the controllers after the dialog is dismissed.
    nameController.dispose();
    urlController.dispose();
    tagsController.dispose();
  }

  /// Whether a source entry is a live room, judged by its URL (a source
  /// type can host both live rooms and on-demand media, e.g. Bilibili).
  bool _isLiveEntry(ASMRSource source) {
    final url = source.url;
    if (url.contains('live.bilibili.com')) return true;
    if (url.contains('douyu.com') || url.contains('douyutv.com')) return true;
    return false;
  }

  List<ASMRSource> get _filteredSources {
    final searchQuery = _searchController.text.toLowerCase();

    return _mySources.where((source) {
      // Filter by Search Query
      if (searchQuery.isNotEmpty) {
        final matchesName = source.name.toLowerCase().contains(searchQuery);
        final matchesTags = source.tags.any(
          (tag) => tag.toLowerCase().contains(searchQuery),
        );
        if (!matchesName && !matchesTags) {
          return false;
        }
      }

      // Filter by Source Type
      if (_filterSourceId != null && source.sourceTypeId != _filterSourceId) {
        return false;
      }

      // Filter by Live/File (per-entry URL type)
      if (_filterIsLive != null) {
        if (_isLiveEntry(source) != _filterIsLive) {
          return false;
        }
      }

      // Filter by Tags
      if (_filterTags.isNotEmpty) {
        final hasAllTags = _filterTags.every(
          (tag) => source.tags.contains(tag),
        );
        if (!hasAllTags) return false;
      }

      return true;
    }).toList();
  }

  Set<String> get _allAvailableTags {
    final tags = <String>{};
    for (var source in _mySources) {
      tags.addAll(source.tags);
    }
    return tags;
  }

  @override
  Widget build(BuildContext context) {
    final availableSources = _sourceManager.getSources();

    return Scaffold(
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(context)!.searchHint,
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      _searchController.clear();
                                    });
                                  },
                                )
                              : null,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: AppLocalizations.of(context)!.importFromAccounts,
                      onPressed: _importing ? null : _importFromAccounts,
                      icon: _importing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_download_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Filter Bar
                Row(
                  children: [
                    // Source Type Filter
                    Expanded(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _filterSourceId,
                        hint: Text(
                          AppLocalizations.of(context)!.sourceFilter,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              AppLocalizations.of(context)!.allSources,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          ...availableSources.map((source) {
                            return DropdownMenuItem(
                              value: source.sourceTypeId,
                              child: Text(
                                source.sourceTypeId == 'local'
                                    ? AppLocalizations.of(context)!.sourceLocal
                                    : source.sourceName,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _filterSourceId = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Live/File Filter
                    Expanded(
                      child: DropdownButton<bool?>(
                        isExpanded: true,
                        value: _filterIsLive,
                        hint: Text(
                          AppLocalizations.of(context)!.typeFilter,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              AppLocalizations.of(context)!.allTypes,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          DropdownMenuItem(
                            value: true,
                            child: Text(
                              AppLocalizations.of(context)!.liveStream,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          DropdownMenuItem(
                            value: false,
                            child: Text(
                              AppLocalizations.of(context)!.fileVideo,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _filterIsLive = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Tags Filter
                    Expanded(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        hint: Text(
                          AppLocalizations.of(context)!.tagFilter,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                        value: null,
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              AppLocalizations.of(context)!.selectTag,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          ..._allAvailableTags.map((tag) {
                            return DropdownMenuItem(
                              value: tag,
                              child: Text(
                                tag,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              if (!_filterTags.contains(value)) {
                                _filterTags.add(value);
                              }
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                // Active Tags Display
                if (_filterTags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: _filterTags.map((tag) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Chip(
                              label: Text(
                                tag,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              onDeleted: () {
                                setState(() {
                                  _filterTags.remove(tag);
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Content Area
          Expanded(child: _buildMySourcesList()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSourceDialog,
        icon: const Icon(Icons.add),
        label: Text(
          AppLocalizations.of(context)!.addSourceFab,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    );
  }

  Widget _buildMySourcesList() {
    final sources = _filteredSources;
    final availableSources = _sourceManager.getSources();

    if (sources.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.playlist_add,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.noSourcesFound,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.clearFilterHint,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sources.length,
      itemBuilder: (context, index) {
        final source = sources[index];
        final sourceHandler = availableSources.firstWhere(
          (s) => s.sourceTypeId == source.sourceTypeId,
          orElse: () => availableSources.first,
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: sourceHandler.getIcon(
              context,
              path: source.url,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              source.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sourceHandler.sourceTypeId == 'local'
                      ? AppLocalizations.of(context)!.sourceLocal
                      : sourceHandler.sourceName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (source.tags.isNotEmpty)
                  Wrap(
                    spacing: 4,
                    children: source.tags.map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          tag,
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(fontSize: 10),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _renameSource(source),
                  tooltip: AppLocalizations.of(context)!.renameSource,
                ),
                IconButton(
                  icon: const Icon(Icons.play_circle_fill),
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: () => _playSource(source),
                  tooltip: AppLocalizations.of(context)!.playAllTooltip,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeSource(source.id),
                  tooltip: AppLocalizations.of(context)!.delete,
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SourceDetailPage(
                    source: source,
                    onUpdate: _updateSource,
                    onDelete: (s) => _removeSource(s.id),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
