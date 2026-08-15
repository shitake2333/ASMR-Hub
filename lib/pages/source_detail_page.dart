import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:asmr_hub/l10n/app_localizations.dart';
import 'package:asmr_hub/constants.dart';
import '../models/asmr_source.dart';
import '../models/audio_models.dart';
import '../providers/audio_provider.dart';
import '../providers/playlist_provider.dart';
import '../services/audio_source.dart';
import '../services/audio_source_manager.dart';
import '../services/app_navigator.dart';
import '../services/cache_service.dart';
import '../services/download_manager.dart';
import '../services/live_watch_manager.dart';
import '../services/log_service.dart';

class SourceDetailPage extends StatefulWidget {
  final ASMRSource source;
  final Function(ASMRSource) onUpdate;
  final Function(ASMRSource)? onDelete;

  const SourceDetailPage({
    super.key,
    required this.source,
    required this.onUpdate,
    this.onDelete,
  });

  @override
  State<SourceDetailPage> createState() => _SourceDetailPageState();
}

class _SourceDetailPageState extends State<SourceDetailPage> {
  late TextEditingController _tagController;
  late List<String> _tags;
  final AudioSourceManager _sourceManager = AudioSourceManager();
  Timer? _recordingRefreshTimer;
  int _liveRefreshCounter = 0;

  List<AudioTrack> _tracks = [];
  bool _isLoading = true;
  String? _error;

  /// Track ids that have a downloaded (cached) file, for badge display.
  Set<String> _cachedIds = {};

  /// Total bytes downloaded for this source (shown in the info card).
  int _downloadSize = 0;

  /// Refreshes the total download size of this source.
  Future<void> _refreshDownloadSize() async {
    final size = await DownloadManager.instance.sourceDownloadSize(
      widget.source.sourceTypeId,
    );
    if (mounted && size != _downloadSize) {
      setState(() => _downloadSize = size);
    }
  }

  /// Validates the download index and queries which of [tracks] are cached.
  Future<void> _checkCached(List<AudioTrack> tracks) async {
    await DownloadManager.instance.validateIndex();
    final cached = await DownloadManager.instance.downloadedIdsFor(tracks);
    if (mounted) {
      setState(() => _cachedIds = cached);
    }
    await _refreshDownloadSize();
  }

  /// Enqueues every on-demand track of this source for download (skips live
  /// cards and tracks that are already downloaded or queued).
  Future<void> _downloadAllTracks() async {
    final targets = <AudioTrack>[];
    for (final t in _tracks) {
      if (t.metadata?['isLiveCard'] == true || t.metadata?['isLive'] == true) {
        continue; // live rooms cannot be downloaded
      }
      if (t.sourceTypeId == 'local') continue; // already local
      if (await DownloadManager.instance.isDownloaded(t)) continue;
      targets.add(t);
    }
    if (targets.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: AppConstants.snackBarDuration,
            content: Text(
              AppLocalizations.of(context)!.downloadAllDone,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onInverseSurface,
              ),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    // Confirm, since this downloads many files.
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          AppLocalizations.of(
            dialogContext,
          )!.downloadAllConfirm(targets.length),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              AppLocalizations.of(dialogContext)!.cancel,
              style: Theme.of(dialogContext).textTheme.labelLarge,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppLocalizations.of(dialogContext)!.confirm),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    var enqueued = 0;
    for (final t in targets) {
      final task = await DownloadManager.instance.startDownload(t);
      if (task != null) enqueued++;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: AppConstants.snackBarDuration,
          content: Text(
            enqueued == 0
                ? AppLocalizations.of(context)!.downloadAllAlready
                : AppLocalizations.of(context)!.downloadAllStarted(enqueued),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onInverseSurface,
            ),
          ),
        ),
      );
    }
  }

  /// Deletes every downloaded file of this source after confirmation.
  Future<void> _clearAllDownloads() async {
    final l10n = AppLocalizations.of(context)!;
    final size = await DownloadManager.instance.sourceDownloadSize(
      widget.source.sourceTypeId,
    );
    if (!mounted) return;
    if (size == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: AppConstants.snackBarDuration,
          content: Text(
            l10n.downloadAllDone,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onInverseSurface,
            ),
          ),
        ),
      );
      return;
    }
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.clearAllCacheConfirm),
        content: Text(l10n.clearAllCacheContent(_formatBytes(size))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              l10n.cancel,
              style: Theme.of(dialogContext).textTheme.labelLarge,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              l10n.confirm,
              style: Theme.of(dialogContext).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    await DownloadManager.instance.clearSourceDownloads(
      widget.source.sourceTypeId,
    );
    await _checkCached(_tracks);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: AppConstants.snackBarDuration,
        content: Text(
          l10n.cacheCleared,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onInverseSurface,
          ),
        ),
      ),
    );
  }

  /// Formats a byte count as a human-readable size string.
  String _formatBytes(int bytes) {
    if (bytes >= 1 << 30) {
      return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1 << 20) {
      return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1 << 10) {
      return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  /// Deletes this source entry from the source list after confirmation.
  Future<void> _deleteSource() async {
    final onDelete = widget.onDelete;
    if (onDelete == null) return;
    final l10n = AppLocalizations.of(context)!;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteSourceConfirm),
        content: Text(l10n.deleteSourceContent(widget.source.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              l10n.cancel,
              style: Theme.of(dialogContext).textTheme.labelLarge,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: Text(
              l10n.delete,
              style: Theme.of(dialogContext).textTheme.labelLarge?.copyWith(
                color: Theme.of(dialogContext).colorScheme.onError,
              ),
            ),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    onDelete(widget.source);
    Navigator.of(context).pop();
  }

  /// The audio source instance for the given track's sourceTypeId.
  AudioSource? _sourceFor(String sourceTypeId) {
    for (final s in _sourceManager.getSources()) {
      if (s.sourceTypeId == sourceTypeId) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _tagController = TextEditingController();
    _tags = List.from(widget.source.tags);
    // Keep the recording/watch state in sync, refresh live durations and
    // periodically re-check the live status of the pinned card.
    _recordingRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final hasLiveCard = _tracks.any((t) => t.metadata?['isLiveCard'] == true);
      if (hasLiveCard) {
        setState(() {});
        _liveRefreshCounter++;
        if (_liveRefreshCounter >= 30) {
          _liveRefreshCounter = 0;
          _refreshLiveCards();
        }
      }
    });
    _loadTracks();
  }

  @override
  void dispose() {
    _recordingRefreshTimer?.cancel();
    _tagController.dispose();
    super.dispose();
  }

  /// Toggles recording for a live-card track: starts watching (recording
  /// starts automatically when the room is online) or stops it. Works even
  /// while the room is offline.
  Future<void> _toggleRecording(AudioTrack track) async {
    await LiveWatchManager.instance.toggleForTrack(track);
    if (mounted) setState(() {});
  }

  DateTime? _liveTimeOf(AudioTrack track) {
    final ms = track.metadata?['liveTime'];
    if (ms is int && ms > 0) {
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return null;
  }

  String _liveDurationText(DateTime liveTime) {
    final diff = DateTime.now().difference(liveTime);
    return _fmtDuration(diff);
  }

  String _recordingDurationText(LiveWatchRoom? room) {
    final since = room?.recordingSince;
    if (since == null) return '';
    return _fmtDuration(DateTime.now().difference(since));
  }

  String _fmtDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Future<void> _loadTracks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Try to fetch as playlist (for directory or playlist URL)
      Object? playlistError;
      try {
        final tracks = await _sourceManager
            .getPlaylist(widget.source.url)
            .timeout(const Duration(seconds: 25));
        if (tracks.isNotEmpty) {
          if (mounted) {
            setState(() {
              _tracks = tracks;
              _isLoading = false;
            });
          }
          await _checkCached(tracks);
          return;
        }
      } catch (e) {
        // Remember the first real error; playlistUrl exceptions from
        // parseFromUrl are expected and must not mask the playlist error.
        playlistError ??= e;
      }

      // Try to parse as single track
      try {
        final track = await _sourceManager
            .parseUrl(widget.source.url)
            .timeout(const Duration(seconds: 25));
        if (track != null) {
          if (mounted) {
            setState(() {
              _tracks = [track];
              _isLoading = false;
            });
          }
          await _checkCached([track]);
          return;
        }
      } catch (e) {
        playlistError ??= e;
      }

      if (mounted) {
        setState(() {
          _tracks = [];
          _isLoading = false;
          // If we hit a network/protocol error, surface it with a retry
          // action instead of silently showing an empty list.
          _error = playlistError == null
              ? null
              : '${AppLocalizations.of(context)!.networkError}\n'
                    '$playlistError';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tagController.clear();
      });
      _updateSource();
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
    _updateSource();
  }

  void _updateSource() {
    final updatedSource = ASMRSource(
      id: widget.source.id,
      name: widget.source.name,
      url: widget.source.url,
      sourceTypeId: widget.source.sourceTypeId,
      tags: _tags,
      addedDate: widget.source.addedDate,
    );
    widget.onUpdate(updatedSource);
  }

  Future<void> _playAll() async {
    if (_tracks.isEmpty) return;

    final playerProvider = context.read<AudioPlayerProvider>();

    // Add all tracks to playlist
    for (final track in _tracks) {
      playerProvider.addToPlaylist(track);
    }

    // Play the first one
    await playerProvider.play(_tracks.first);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: AppConstants.snackBarDuration,
          content: Text(
            AppLocalizations.of(context)!.startPlayingCount(_tracks.length),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onInverseSurface,
            ),
          ),
        ),
      );
      // Return to the shell so the tab switch is visible, then jump to the
      // player tab so the user sees playback start.
      Navigator.of(context).popUntil((route) => route.isFirst);
      AppNavigator.goToTab(1);
    }
  }

  void _showAddToPlaylistDialog(List<AudioTrack> tracks) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.addToPlaylist,
          style: Theme.of(dialogContext).textTheme.titleLarge,
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Consumer<PlaylistProvider>(
            builder: (consumerContext, playlistProvider, child) {
              return ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.queue_music),
                    title: Text(
                      AppLocalizations.of(context)!.currentQueue,
                      style: Theme.of(consumerContext).textTheme.bodyLarge,
                    ),
                    onTap: () {
                      final playerProvider = context
                          .read<AudioPlayerProvider>();
                      for (final track in tracks) {
                        playerProvider.addToPlaylist(track);
                      }
                      Navigator.pop(dialogContext);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            duration: AppConstants.snackBarDuration,
                            content: Text(
                              AppLocalizations.of(
                                context,
                              )!.addedToQueue(tracks.length),
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
                    },
                  ),
                  const Divider(),
                  if (playlistProvider.playlists.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        AppLocalizations.of(context)!.noCustomPlaylists,
                        style: Theme.of(consumerContext).textTheme.bodyMedium
                            ?.copyWith(
                              color: Theme.of(
                                consumerContext,
                              ).colorScheme.onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ...playlistProvider.playlists.map(
                    (playlist) => ListTile(
                      leading: const Icon(Icons.playlist_play),
                      title: Text(
                        playlist.name,
                        style: Theme.of(consumerContext).textTheme.bodyLarge,
                      ),
                      subtitle: Text(
                        '${playlist.tracks.length}${AppLocalizations.of(context)!.tracksCountSuffix}',
                        style: Theme.of(consumerContext).textTheme.bodySmall,
                      ),
                      onTap: () {
                        for (final track in tracks) {
                          playlistProvider.addTrackToPlaylist(
                            playlist.id,
                            track,
                          );
                        }
                        Navigator.pop(dialogContext);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              duration: AppConstants.snackBarDuration,
                              content: Text(
                                AppLocalizations.of(context)!.addedToPlaylist(
                                  tracks.length,
                                  playlist.name,
                                ),
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
                      },
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: Text(
                      AppLocalizations.of(context)!.createPlaylistTitle,
                      style: Theme.of(consumerContext).textTheme.bodyLarge,
                    ),
                    onTap: () {
                      Navigator.pop(dialogContext);
                      _showCreatePlaylistDialog(tracks);
                    },
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: Theme.of(dialogContext).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog(List<AudioTrack> tracks) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.createPlaylistTitle,
          style: Theme.of(dialogContext).textTheme.titleLarge,
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.playlistNameHint,
            labelText: AppLocalizations.of(context)!.playlistNameLabel,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: Theme.of(dialogContext).textTheme.labelLarge,
            ),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(dialogContext);
                final playlistProvider = context.read<PlaylistProvider>();
                await playlistProvider.createPlaylist(name);

                if (!mounted) return;

                // Find the newly created playlist (it's the last one)
                if (playlistProvider.playlists.isNotEmpty) {
                  final newPlaylist = playlistProvider.playlists.last;
                  for (final track in tracks) {
                    playlistProvider.addTrackToPlaylist(newPlaylist.id, track);
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      duration: AppConstants.snackBarDuration,
                      content: Text(
                        AppLocalizations.of(
                          context,
                        )!.createdAndAddedToPlaylist(tracks.length, name),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onInverseSurface,
                        ),
                      ),
                    ),
                  );
                }
              }
            },
            child: Text(
              AppLocalizations.of(context)!.create,
              style: Theme.of(dialogContext).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _playTrack(AudioTrack track) async {
    // Live-card tracks: verify the room is actually streaming before
    // playing — a stale "live" state must not end in a failed playback.
    if (track.metadata?['isLiveCard'] == true) {
      final source = _sourceFor(track.sourceTypeId);
      final roomId = track.metadata?['roomId']?.toString() ?? track.id;
      if (source != null && roomId.isNotEmpty) {
        try {
          final live = await source.isRoomLive(roomId);
          if (!live && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                duration: AppConstants.snackBarDuration,
                content: Text(
                  AppLocalizations.of(context)!.liveEnded,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onInverseSurface,
                  ),
                ),
              ),
            );
            // Refresh the card state so the UI reflects reality.
            await _refreshLiveCards();
            return;
          }
        } catch (e) {
          // If the status check fails, still allow playback attempts.
        }
      }
    }
    if (!mounted) return;
    final playerProvider = context.read<AudioPlayerProvider>();
    playerProvider.addToPlaylist(track);
    await playerProvider.play(track);
    if (!mounted) return;
    // Pop back to the shell (main page) first — the tab bar lives there and
    // the detail page is a pushed route on top of it. Without this the tab
    // switches underneath while the detail page stays on screen.
    Navigator.of(context).popUntil((route) => route.isFirst);
    // Then jump to the player tab so the user sees playback start.
    AppNavigator.goToTab(1);
  }

  /// Re-checks the live status of all live-card tracks and updates the UI.
  Future<void> _refreshLiveCards() async {
    final liveCards = _tracks.where((t) => t.metadata?['isLiveCard'] == true);
    if (liveCards.isEmpty) return;
    for (final track in liveCards) {
      final source = _sourceFor(track.sourceTypeId);
      final roomId = track.metadata?['roomId']?.toString() ?? track.id;
      if (source == null || roomId.isEmpty) continue;
      try {
        final live = await source.isRoomLive(roomId);
        final metadata = Map<String, dynamic>.from(track.metadata ?? {});
        metadata['isLive'] = live;
        final updated = AudioTrack(
          id: track.id,
          title: track.title,
          artist: track.artist,
          albumArt: track.albumArt,
          duration: track.duration,
          streamUrl: track.streamUrl,
          sourceTypeId: track.sourceTypeId,
          description: track.description,
          metadata: metadata,
        );
        final idx = _tracks.indexWhere((t) => t.id == track.id);
        if (idx != -1 && mounted) {
          setState(() => _tracks[idx] = updated);
        }
      } catch (e) {
        LogService().warning('Live status refresh failed for $roomId: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sourceManager.getSources();
    if (sources.isEmpty) {
      // Manager not initialized yet: show a minimal scaffold instead of
      // crashing on sources.first.
      return Scaffold(
        appBar: AppBar(title: Text(widget.source.name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final sourceHandler = sources.firstWhere(
      (s) => s.sourceTypeId == widget.source.sourceTypeId,
      orElse: () => sources.first,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.source.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppLocalizations.of(context)!.refresh,
            onPressed: _loadTracks,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: AppLocalizations.of(context)!.clearAllCache,
            onPressed: () => _clearAllDownloads(),
          ),
          if (widget.onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: AppLocalizations.of(context)!.deleteSource,
              onPressed: () => _deleteSource(),
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Source Info Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                sourceHandler.icon,
                                size: 48,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.source.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      sourceHandler.sourceTypeId == 'local'
                                          ? AppLocalizations.of(
                                              context,
                                            )!.sourceLocal
                                          : sourceHandler.sourceName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.source.url,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _tracks.isNotEmpty
                                      ? _playAll
                                      : null,
                                  icon: const Icon(Icons.play_arrow),
                                  label: Text(
                                    AppLocalizations.of(context)!.playAll,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _tracks.isNotEmpty
                                      ? () => _showAddToPlaylistDialog(_tracks)
                                      : null,
                                  icon: const Icon(Icons.playlist_add),
                                  label: Text(
                                    AppLocalizations.of(context)!.addAll,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _tracks.isNotEmpty
                                      ? _downloadAllTracks
                                      : null,
                                  icon: const Icon(
                                    Icons.download_for_offline_outlined,
                                  ),
                                  label: Text(
                                    AppLocalizations.of(context)!.downloadAll,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Download occupancy of this source.
                          Row(
                            children: [
                              Icon(
                                Icons.sd_storage_outlined,
                                size: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                AppLocalizations.of(
                                  context,
                                )!.downloadUsage(_formatBytes(_downloadSize)),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              const Spacer(),
                              if (_downloadSize > 0)
                                TextButton(
                                  onPressed: _clearAllDownloads,
                                  child: Text(
                                    AppLocalizations.of(
                                      context,
                                    )!.clearDownloads,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Tags Section
                  Text(
                    AppLocalizations.of(context)!.tagManagement,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._tags.map(
                        (tag) => Chip(
                          label: Text(
                            tag,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          onDeleted: () => _removeTag(tag),
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: Text(
                          AppLocalizations.of(context)!.addTag,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(
                                AppLocalizations.of(context)!.addTag,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              content: TextField(
                                controller: _tagController,
                                decoration: InputDecoration(
                                  hintText: AppLocalizations.of(
                                    context,
                                  )!.tagNameHint,
                                ),
                                autofocus: true,
                                onSubmitted: (_) {
                                  _addTag();
                                  Navigator.pop(context);
                                },
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text(
                                    AppLocalizations.of(context)!.cancel,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    _addTag();
                                    Navigator.pop(context);
                                  },
                                  child: Text(
                                    AppLocalizations.of(context)!.confirm,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // File List Section
                  Text(
                    AppLocalizations.of(context)!.fileList(_tracks.length),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  AppLocalizations.of(context)!.loadingFailed(_error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            )
          else if (_tracks.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(AppLocalizations.of(context)!.noAudioFilesFound),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final track = _tracks[index];
                // Pinned live-room card: always rendered on top of a live
                // room's playlist, showing online state + recording toggle.
                if (track.metadata?['isLiveCard'] == true) {
                  return _buildLiveCard(track);
                }
                return Column(
                  children: [
                    ListTile(
                      onTap: () => _playTrack(track),
                      leading: track.metadata?['isRecording'] == true
                          ? const Icon(Icons.history)
                          : track.albumArt != null
                          ? _TrackCover(url: track.albumArt!, size: 40)
                          : const Icon(Icons.audiotrack),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              track.title,
                              style: Theme.of(context).textTheme.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Cached-file badge.
                          if (_cachedIds.contains(track.id)) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.offline_pin,
                              size: 16,
                              color: Colors.green,
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        track.artist,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (track.metadata?['isLive'] != true &&
                              track.metadata?['isRecording'] != true &&
                              track.sourceTypeId != 'local')
                            _TrackCacheButton(track: track),
                          IconButton(
                            icon: const Icon(Icons.play_arrow),
                            onPressed: () => _playTrack(track),
                          ),
                          IconButton(
                            icon: const Icon(Icons.playlist_add),
                            onPressed: () => _showAddToPlaylistDialog([track]),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                );
              }, childCount: _tracks.length),
            ),
        ],
      ),
    );
  }

  /// Pinned card for the current live room: online state, live title,
  /// recording toggle and play button.
  Widget _buildLiveCard(AudioTrack track) {
    final l10n = AppLocalizations.of(context)!;
    final isOnline = track.metadata?['isLive'] == true;
    final source = _sourceFor(track.sourceTypeId);
    final canRecord = source != null && source.supportsLiveRecording;
    // Recording state comes from the unified watch manager: any recording
    // started anywhere (card button, player, watchdog) shows here.
    final watchRoom = LiveWatchManager.instance.roomForTrack(track);
    final isRec = watchRoom?.isRecording ?? false;
    final isWatching = watchRoom?.enabled ?? false;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOnline
              ? Colors.red.withValues(alpha: 0.6)
              : Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Cover thumbnail (cached from the live room cover URL).
          _LiveCover(
            avatarUrl: track.metadata?['avatarUrl']?.toString(),
            coverUrl: track.metadata?['coverUrl']?.toString(),
            size: 56,
          ),
          const SizedBox(width: 12),
          // Online indicator.
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline ? Colors.red : Colors.grey,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isOnline ? l10n.liveNow : l10n.liveOffline,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isOnline
                            ? Colors.red
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    // How long the stream has been live.
                    if (isOnline && _liveTimeOf(track) != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        l10n.liveFor(_liveDurationText(_liveTimeOf(track)!)),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    // Recording state (unified across all entry points).
                    if (isRec) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.circle, size: 8, color: Colors.red),
                      const SizedBox(width: 4),
                      Text(
                        _recordingDurationText(watchRoom),
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: Colors.red),
                      ),
                    ] else if (isWatching) ...[
                      const SizedBox(width: 8),
                      Text(
                        l10n.roomWatching,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  track.title,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (track.artist.isNotEmpty &&
                    track.artist != 'Bilibili' &&
                    track.artist != 'Douyu')
                  Text(
                    track.artist,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Recording toggle (unified watch): red stop while recording,
          // theme-primary dot while watching, grey dot when idle. Works even
          // while offline (watches until the room goes live).
          if (canRecord)
            IconButton(
              icon: Icon(
                isRec ? Icons.stop_circle : Icons.fiber_manual_record,
                color: isRec
                    ? Colors.red
                    : isWatching
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
              tooltip: isRec
                  ? l10n.stopRecording
                  : isWatching
                  ? l10n.roomWatching
                  : l10n.recordLive,
              onPressed: () => _toggleRecording(track),
            ),
          // Play (disabled when offline, with a hint).
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: isOnline
                ? () => _playTrack(track)
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        duration: AppConstants.snackBarDuration,
                        content: Text(
                          l10n.liveOffline,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onInverseSurface,
                              ),
                        ),
                      ),
                    );
                  },
          ),
        ],
      ),
    );
  }
}

/// Rounded cover thumbnail for a live room: downloads the cover URL into the
/// metadata cache on first use, then shows the local file.
class _LiveCover extends StatefulWidget {
  /// Owner avatar (preferred as the live-card icon).
  final String? avatarUrl;

  /// Room cover / live screenshot (fallback when no avatar).
  final String? coverUrl;
  final double size;

  const _LiveCover({this.avatarUrl, this.coverUrl, this.size = 56});

  @override
  State<_LiveCover> createState() => _LiveCoverState();
}

class _LiveCoverState extends State<_LiveCover> {
  String? _localPath;

  /// The URL currently being displayed (avatar preferred).
  String? get _displayUrl =>
      (widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty)
      ? widget.avatarUrl
      : widget.coverUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _LiveCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl ||
        oldWidget.coverUrl != widget.coverUrl) {
      _localPath = null;
      _load();
    }
  }

  Future<void> _load() async {
    final url = _displayUrl;
    if (url == null || url.isEmpty) return;
    final local = await CacheService().cacheRemoteFile(
      url,
      headers: CacheService.coverHeadersFor(url),
    );
    // Ignore stale responses if the widget moved to another cover URL.
    if (mounted && local != null && _displayUrl == url) {
      setState(() => _localPath = local);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final local = _localPath;
    final isAvatar = widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty;
    Widget child;
    if (local != null) {
      child = Image.file(
        File(local),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            Icon(isAvatar ? Icons.person : Icons.live_tv),
      );
    } else {
      child = Icon(
        isAvatar ? Icons.person : Icons.live_tv,
        size: size * 0.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    // Avatar is shown as a circle, room cover as a rounded square.
    return ClipRRect(
      borderRadius: BorderRadius.circular(isAvatar ? size / 2 : 10),
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: child,
        ),
      ),
    );
  }
}

/// Rounded cover thumbnail for a track: downloads the cover URL into the
/// metadata cache on first use, then shows the local file.
class _TrackCover extends StatefulWidget {
  final String url;
  final double size;

  const _TrackCover({required this.url, this.size = 40});

  @override
  State<_TrackCover> createState() => _TrackCoverState();
}

class _TrackCoverState extends State<_TrackCover> {
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _TrackCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _localPath = null;
      _load();
    }
  }

  Future<void> _load() async {
    final url = widget.url;
    final local = await CacheService().cacheRemoteFile(
      url,
      headers: CacheService.coverHeadersFor(url),
    );
    // Ignore stale responses if the widget moved to another cover URL.
    if (mounted && local != null && widget.url == url) {
      setState(() => _localPath = local);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final local = _localPath;
    Widget child;
    if (local != null) {
      child = Image.file(
        File(local),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.audiotrack),
      );
    } else {
      child = Icon(
        Icons.audiotrack,
        size: size * 0.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: child,
        ),
      ),
    );
  }
}

/// Download status button for a track: download action when not downloaded,
/// a spinner while a background task runs, a green check when done (tap to
/// delete the file).
class _TrackCacheButton extends StatefulWidget {
  final AudioTrack track;

  const _TrackCacheButton({required this.track});

  @override
  State<_TrackCacheButton> createState() => _TrackCacheButtonState();
}

class _TrackCacheButtonState extends State<_TrackCacheButton> {
  bool? _isDownloaded;
  bool _taskActive = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final downloaded =
        await DownloadManager.instance.downloadedFileFor(widget.track) != null;
    final active =
        DownloadManager.instance.activeTaskFor(widget.track.id) != null;
    if (mounted) {
      setState(() {
        _isDownloaded = downloaded;
        _taskActive = active;
      });
    }
  }

  Future<void> _download() async {
    final l10n = AppLocalizations.of(context)!;
    final task = await DownloadManager.instance.startDownload(widget.track);
    if (task == null) {
      // Either the file already exists or the format is off.
      final downloaded =
          await DownloadManager.instance.downloadedFileFor(widget.track) !=
          null;
      if (downloaded) {
        await _check();
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: AppConstants.snackBarDuration,
            content: Text(
              l10n.downloadOffHint,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onInverseSurface,
              ),
            ),
          ),
        );
      }
      return;
    }
    await _check();
  }

  Future<void> _deleteDownload() async {
    await DownloadManager.instance.deleteFile(widget.track);
    if (mounted) {
      setState(() => _isDownloaded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDownloaded == null) {
      return const SizedBox.shrink();
    }
    if (_taskActive) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_isDownloaded == true) {
      return IconButton(
        icon: const Icon(Icons.check_circle, color: Colors.green),
        tooltip: AppLocalizations.of(context)!.cachedTooltip,
        onPressed: _deleteDownload,
      );
    }
    return IconButton(
      icon: const Icon(Icons.download),
      tooltip: AppLocalizations.of(context)!.downloadAudio,
      onPressed: _download,
    );
  }
}
