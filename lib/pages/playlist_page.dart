import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:asmr_hub/l10n/app_localizations.dart';
import 'package:asmr_hub/constants.dart';
import '../models/audio_models.dart';
import '../providers/audio_provider.dart';
import '../providers/playlist_provider.dart';
import '../services/download_manager.dart';

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key});

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  String? _expandedPlaylistId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showCreatePlaylistDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.createPlaylistTitle,
          style: Theme.of(context).textTheme.titleLarge,
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
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                context.read<PlaylistProvider>().createPlaylist(name);
                Navigator.pop(context);
              }
            },
            child: Text(
              AppLocalizations.of(context)!.create,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _playPlaylist(Playlist playlist) {
    if (playlist.tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: AppConstants.snackBarDuration,
          content: Text(
            AppLocalizations.of(context)!.playlistEmpty,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onInverseSurface,
            ),
          ),
        ),
      );
      return;
    }
    final playerProvider = context.read<AudioPlayerProvider>();
    playerProvider.setPlaylist(playlist.tracks);
    playerProvider.play(playlist.tracks.first);

    // Switch to queue tab
    _tabController.animateTo(1);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: AppConstants.snackBarDuration,
        content: Text(
          AppLocalizations.of(context)!.startPlaying(playlist.name),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onInverseSurface,
          ),
        ),
      ),
    );
  }

  void _deletePlaylist(Playlist playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.confirmDeleteTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Text(
          AppLocalizations.of(context)!.confirmDeleteContent(playlist.name),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          TextButton(
            onPressed: () {
              context.read<PlaylistProvider>().deletePlaylist(playlist.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(
              AppLocalizations.of(context)!.delete,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant,
              indicatorColor: Theme.of(context).colorScheme.primary,
              tabs: [
                Tab(text: AppLocalizations.of(context)!.myPlaylists),
                Tab(text: AppLocalizations.of(context)!.currentQueue),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildMyPlaylistsTab(), _buildCurrentQueueTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyPlaylistsTab() {
    return Consumer<PlaylistProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Text(
                    AppLocalizations.of(context)!.customPlaylists,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _showCreatePlaylistDialog,
                    icon: const Icon(Icons.add),
                    label: Text(
                      AppLocalizations.of(context)!.newPlaylist,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  if (provider.playlists.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Text(
                          AppLocalizations.of(context)!.noPlaylists,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    )
                  else
                    for (var playlist in provider.playlists) ...[
                      if (_expandedPlaylistId == playlist.id)
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _PlaylistHeaderDelegate(
                            playlist: playlist,
                            isExpanded: true,
                            onTap: () {
                              setState(() {
                                if (_expandedPlaylistId == playlist.id) {
                                  _expandedPlaylistId = null;
                                } else {
                                  _expandedPlaylistId = playlist.id;
                                }
                              });
                            },
                            onPlay: () => _playPlaylist(playlist),
                            onDelete: () => _deletePlaylist(playlist),
                          ),
                        )
                      else
                        SliverToBoxAdapter(
                          child: _PlaylistHeaderCard(
                            playlist: playlist,
                            isExpanded: false,
                            onTap: () {
                              setState(() {
                                if (_expandedPlaylistId == playlist.id) {
                                  _expandedPlaylistId = null;
                                } else {
                                  _expandedPlaylistId = playlist.id;
                                }
                              });
                            },
                            onPlay: () => _playPlaylist(playlist),
                            onDelete: () => _deletePlaylist(playlist),
                          ),
                        ),
                      if (_expandedPlaylistId == playlist.id)
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildPlaylistTrack(
                              playlist,
                              playlist.tracks[index],
                            ),
                            childCount: playlist.tracks.length,
                          ),
                        ),
                    ],
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlaylistTrack(Playlist playlist, AudioTrack track) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Card(
        margin: const EdgeInsets.only(bottom: 4),
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.music_note, size: 16),
          title: Text(
            track.title,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          subtitle: Text(
            track.artist,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 16),
            onPressed: () {
              context.read<PlaylistProvider>().removeTrackFromPlaylist(
                playlist.id,
                track.id,
              );
            },
          ),
          onTap: () {
            // Play this track from this playlist context
            final playerProvider = context.read<AudioPlayerProvider>();
            playerProvider.setPlaylist(
              playlist.tracks,
              startIndex: playlist.tracks.indexOf(track),
            );
            playerProvider.play(track);
          },
        ),
      ),
    );
  }

  Widget _buildCurrentQueueTab() {
    return Consumer<AudioPlayerProvider>(
      builder: (context, provider, child) {
        final tracks = provider.currentPlaylist;
        final currentTrack = provider.currentTrack;

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Text(
                      AppLocalizations.of(context)!.playQueue,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${tracks.length}${AppLocalizations.of(context)!.tracksCountSuffix}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_sweep),
                      onPressed: tracks.isEmpty
                          ? null
                          : () {
                              provider.clearPlaylist();
                            },
                      tooltip: AppLocalizations.of(context)!.clearQueueTooltip,
                    ),
                  ],
                ),
              ),
            ),
            if (tracks.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    AppLocalizations.of(context)!.queueEmpty,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final track = tracks[index];
                  final isPlaying = currentTrack?.id == track.id;

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    color: isPlaying
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    child: ListTile(
                      leading: isPlaying
                          ? Icon(
                              Icons.graphic_eq,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : Text(
                              '${index + 1}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              track.title,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontWeight: isPlaying
                                        ? FontWeight.bold
                                        : null,
                                    color: isPlaying
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (DownloadManager.instance.isTrackCached(
                            track.id,
                          )) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.offline_pin,
                              size: 14,
                              color: Colors.green,
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        track.artist,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          provider.removeFromPlaylist(index);
                        },
                      ),
                      onTap: () {
                        provider.play(track);
                      },
                    ),
                  );
                }, childCount: tracks.length),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        );
      },
    );
  }
}

class _PlaylistHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Playlist playlist;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  _PlaylistHeaderDelegate({
    required this.playlist,
    required this.isExpanded,
    required this.onTap,
    required this.onPlay,
    required this.onDelete,
  });

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return _PlaylistHeaderCard(
      playlist: playlist,
      isExpanded: isExpanded,
      onTap: onTap,
      onPlay: onPlay,
      onDelete: onDelete,
    );
  }

  @override
  double get maxExtent => 84.0;

  @override
  double get minExtent => 84.0;

  @override
  bool shouldRebuild(covariant _PlaylistHeaderDelegate oldDelegate) {
    return playlist != oldDelegate.playlist ||
        isExpanded != oldDelegate.isExpanded;
  }
}

class _PlaylistHeaderCard extends StatelessWidget {
  final Playlist playlist;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  const _PlaylistHeaderCard({
    required this.playlist,
    required this.isExpanded,
    required this.onTap,
    required this.onPlay,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      color: Theme.of(context).colorScheme.surface,
      alignment: Alignment.center,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
              image: playlist.coverArt != null
                  ? DecorationImage(
                      image: NetworkImage(playlist.coverArt!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: playlist.coverArt == null
                ? Icon(
                    Icons.queue_music,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
          ),
          title: Text(
            playlist.name,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${playlist.tracks.length}${AppLocalizations.of(context)!.tracksCountSuffix}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.play_circle_fill),
                color: Theme.of(context).colorScheme.primary,
                onPressed: onPlay,
                tooltip: AppLocalizations.of(context)!.playAllTooltip,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
                tooltip: AppLocalizations.of(context)!.deletePlaylistTooltip,
              ),
              Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
