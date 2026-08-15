import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:asmr_hub/l10n/app_localizations.dart';
import 'package:asmr_hub/constants.dart';
import '../models/audio_models.dart';
import '../providers/audio_provider.dart';
import '../providers/effects_provider.dart';
import '../services/audio_source_manager.dart';
import '../services/cache_service.dart';
import '../services/download_manager.dart';
import '../services/live_watch_manager.dart';
import '../services/sleep_detection_service.dart';
import '../services/audio_source.dart';
import 'effects_page.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  bool _debugForceMobile = false;

  /// Guards against scheduling the live-blocked snackbar more than once.
  bool _liveBlockedHandled = false;

  /// While the user drags the progress slider, the thumb follows the finger
  /// locally; the real seek happens once on release (onChangeEnd).
  double? _dragPositionMs;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 24),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Toggles recording/watch for the currently playing live track.
  Future<void> _toggleLiveRecording(AudioTrack track) async {
    await LiveWatchManager.instance.toggleForTrack(track);
    if (mounted) {
      setState(() {});
    }
  }

  AudioSource? _liveSourceFor(String sourceTypeId) {
    for (final s in AudioSourceManager().getSources()) {
      if (s.sourceTypeId == sourceTypeId && s.supportsLiveRecording) return s;
    }
    return null;
  }

  String _formatTime(Duration duration) => _fmtClock(duration);

  /// Clock-style H:MM:SS / MM:SS formatting for durations.
  String _fmtClock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  bool _isWideScreen(BuildContext context) {
    if (_debugForceMobile) return false;
    return MediaQuery.of(context).size.width >= 900;
  }

  @override
  Widget build(BuildContext context) {
    final playerProvider = context.watch<AudioPlayerProvider>();
    final currentTrack = playerProvider.currentTrack;
    final isPlaying = playerProvider.isPlaying;

    // A live-card play was blocked because the room is offline: inform the
    // user once (with the channel name), then clear the flag. The flag
    // prevents scheduling the post-frame callback more than once per block.
    final blocked = playerProvider.liveBlockedTitle;
    if (blocked != null && !_liveBlockedHandled) {
      _liveBlockedHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _liveBlockedHandled = false;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: AppConstants.snackBarDuration,
            content: Text(
              '$blocked：${AppLocalizations.of(context)!.liveEnded}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onInverseSurface,
              ),
            ),
          ),
        );
        playerProvider.clearLiveBlocked();
      });
    }

    if (isPlaying) {
      if (!_rotationController.isAnimating) {
        _rotationController.repeat();
      }
    } else {
      if (_rotationController.isAnimating) {
        _rotationController.stop();
      }
    }

    if (currentTrack == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.music_note, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context)!.noContent,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.goToSource,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    final isWide = _isWideScreen(context);

    if (isWide) {
      return _buildDesktopLayout(context, playerProvider, currentTrack);
    }
    return _buildMobileLayout(context, playerProvider, currentTrack);
  }

  void _showUnifiedBottomSheet(
    BuildContext context,
    String title,
    Widget Function(BuildContext, ScrollController) contentBuilder, {
    Widget? trailing,
    double initialChildSize = 0.5,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useRootNavigator: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: initialChildSize,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (trailing != null)
                          trailing
                        else
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                      ],
                    ),
                  ),
                  Expanded(child: contentBuilder(context, scrollController)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSleepTimerContent(
    BuildContext context,
    AudioPlayerProvider provider,
  ) {
    return SleepTimerPanel(provider: provider);
  }

  void _showSleepTimerDialog(
    BuildContext context,
    AudioPlayerProvider provider,
  ) {
    if (_isWideScreen(context)) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(AppLocalizations.of(context)!.sleepTimer),
            content: _buildSleepTimerContent(context, provider),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
            ],
          );
        },
      );
    } else {
      _showUnifiedBottomSheet(
        context,
        AppLocalizations.of(context)!.sleepTimer,
        (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: _buildSleepTimerContent(context, provider),
        ),
      );
    }
  }

  void _showEffects(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_isWideScreen(context)) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(l10n.audioEffects),
            content: const SizedBox(
              width: 400,
              child: SingleChildScrollView(child: EffectsList()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
            ],
          );
        },
      );
    } else {
      _showUnifiedBottomSheet(
        context,
        l10n.audioEffects,
        (context, scrollController) =>
            EffectsList(controller: scrollController),
      );
    }
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    AudioPlayerProvider provider,
    AudioTrack currentTrack,
  ) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: Column(
          children: [
            _buildDesktopHeader(context, currentTrack),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 48,
                  vertical: 24,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildDesktopMainSection(
                        context,
                        provider,
                        currentTrack,
                      ),
                    ),
                    const SizedBox(width: 32),
                    SizedBox(
                      width: 320,
                      child: _buildDesktopQueue(context, provider),
                    ),
                  ],
                ),
              ),
            ),
            _buildDesktopFooter(context, provider, currentTrack),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopHeader(BuildContext context, AudioTrack currentTrack) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 48),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.nowPlaying,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                currentTrack.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Text(
            currentTrack.artist,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildDesktopMainSection(
    BuildContext context,
    AudioPlayerProvider provider,
    AudioTrack currentTrack,
  ) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildAlbumArt(context, 220, currentTrack.albumArt),
                    const SizedBox(width: 48),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildTrackInfo(context, currentTrack, true),
                          const SizedBox(height: 16),
                          Text(
                            AppLocalizations.of(context)!.immersiveAudio,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDesktopQueue(
    BuildContext context,
    AudioPlayerProvider provider,
  ) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppLocalizations.of(context)!.playQueue,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    provider.clearPlaylist();
                  },
                  icon: const Icon(Icons.delete_outline),
                  tooltip: AppLocalizations.of(context)!.clearQueue,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(
                context,
              )!.tracksCount(provider.currentPlaylist.length),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildQueueList(context, provider)),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopFooter(
    BuildContext context,
    AudioPlayerProvider provider,
    AudioTrack currentTrack,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Buffering / error status hint.
          if (provider.playbackState == PlaybackState.buffering)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context)!.buffering,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else if (provider.playbackState == PlaybackState.error)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 14,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context)!.playbackError,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: () => provider.play(),
                    child: Text(AppLocalizations.of(context)!.retry),
                  ),
                ],
              ),
            ),
          _buildProgressControl(context, provider, true),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        gradient: currentTrack.albumArt == null
                            ? LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primary,
                                  Theme.of(context).colorScheme.secondary,
                                ],
                              )
                            : null,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: currentTrack.albumArt == null
                          ? const Icon(Icons.headphones, color: Colors.white)
                          : _CachedCover(size: 48, url: currentTrack.albumArt),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentTrack.title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            currentTrack.artist,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 240,
                    child: _buildPlaybackControls(context, provider, true),
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: provider.toggleShuffle,
                        icon: const Icon(Icons.shuffle),
                        iconSize: 20,
                        color: provider.isShuffleEnabled
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        tooltip: AppLocalizations.of(context)!.shuffleTooltip,
                      ),
                      IconButton(
                        onPressed: provider.toggleLoopMode,
                        icon: _buildLoopIcon(context, provider),
                        iconSize: 20,
                        tooltip: AppLocalizations.of(context)!.repeatTooltip,
                      ),
                      IconButton(
                        onPressed: () =>
                            _showSleepTimerDialog(context, provider),
                        icon: Icon(
                          provider.isSleepTimerActive
                              ? Icons.timer
                              : Icons.timer_outlined,
                        ),
                        iconSize: 20,
                        color: provider.isSleepTimerActive
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        tooltip: AppLocalizations.of(context)!.sleepTimer,
                      ),
                      IconButton(
                        onPressed: () {
                          _showEffects(context);
                        },
                        icon: const Icon(Icons.equalizer),
                        iconSize: 20,
                        color:
                            context.watch<EffectsProvider>().isAnyEffectEnabled
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        tooltip: AppLocalizations.of(context)!.audioEffects,
                      ),
                      const SizedBox(width: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Consumer<AudioPlayerProvider>(
                            builder: (_, provider, _) => IconButton(
                              onPressed: provider.toggleMute,
                              icon: Icon(
                                provider.isMuted
                                    ? Icons.volume_off
                                    : Icons.volume_up,
                                size: 20,
                              ),
                              tooltip: provider.isMuted
                                  ? AppLocalizations.of(context)!.unmuteTooltip
                                  : AppLocalizations.of(context)!.muteTooltip,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Consumer<AudioPlayerProvider>(
                              builder: (_, provider, _) => SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 12,
                                  ),
                                  valueIndicatorShape:
                                      const RectangularSliderValueIndicatorShape(),
                                  showValueIndicator: ShowValueIndicator.onDrag,
                                ),
                                child: Slider(
                                  value: provider.isMuted ? 0 : provider.volume,
                                  onChanged: provider.setVolume,
                                  divisions: 100,
                                  label:
                                      '${((provider.isMuted ? 0 : provider.volume) * 100).round()}%',
                                  activeColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  inactiveColor: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQueueList(
    BuildContext context,
    AudioPlayerProvider provider, {
    ScrollController? scrollController,
  }) {
    return ListView.separated(
      controller: scrollController,
      itemCount: provider.currentPlaylist.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
      itemBuilder: (context, index) {
        final track = provider.currentPlaylist[index];
        final isCurrent = index == provider.currentIndex;

        final isLiveCard =
            track.metadata?['isLiveCard'] == true ||
            track.metadata?['isLive'] == true;
        // Live-card tracks use the owner avatar as their icon (rounded);
        // other tracks use the cover art (rounded square).
        final avatarUrl = track.metadata?['avatarUrl']?.toString();
        final useAvatar =
            isLiveCard && avatarUrl != null && avatarUrl.isNotEmpty;
        final leadingUrl = useAvatar ? avatarUrl : track.albumArt;

        return ListTile(
          onTap: () {
            provider.play(track);
          },
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          selected: isCurrent,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
          leading: leadingUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(useAvatar ? 20 : 10),
                  child: _CachedCover(size: 40, url: leadingUrl),
                )
              : Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: isCurrent
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  child: Icon(
                    isCurrent
                        ? (provider.isPlaying
                              ? Icons.graphic_eq
                              : Icons.play_arrow)
                        : Icons.music_note,
                    color: isCurrent
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ),
          title: Text(
            track.title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            track.artist,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Live-card tracks show their online status (heartbeat).
              if (track.metadata?['isLiveCard'] == true ||
                  track.metadata?['isLive'] == true) ...[
                Icon(
                  Icons.circle,
                  size: 10,
                  color: provider.isLiveCardOnline(track.id)
                      ? Colors.red
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Text(
                  provider.isLiveCardOnline(track.id)
                      ? AppLocalizations.of(context)!.liveNow
                      : AppLocalizations.of(context)!.liveEnded,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: provider.isLiveCardOnline(track.id)
                        ? Colors.red
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
              ] else
                Text(
                  _formatTime(track.duration),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: AppLocalizations.of(context)!.removeFromQueue,
                onPressed: () {
                  provider.removeFromPlaylist(index);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPlaylistBottomSheet(BuildContext context) {
    _showUnifiedBottomSheet(
      context,
      AppLocalizations.of(context)!.playQueue,
      (context, scrollController) {
        return Consumer<AudioPlayerProvider>(
          builder: (context, provider, child) {
            return _buildQueueList(
              context,
              provider,
              scrollController: scrollController,
            );
          },
        );
      },
      trailing: Consumer<AudioPlayerProvider>(
        builder: (context, provider, child) {
          return IconButton(
            onPressed: () {
              provider.clearPlaylist();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.delete_outline),
            tooltip: AppLocalizations.of(context)!.clearQueue,
          );
        },
      ),
      initialChildSize: 0.6,
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    AudioPlayerProvider provider,
    AudioTrack currentTrack,
  ) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (kDebugMode)
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _debugForceMobile = !_debugForceMobile;
                          });
                        },
                        icon: const Icon(Icons.desktop_windows),
                        tooltip: 'Toggle Desktop Layout',
                      )
                    else
                      const SizedBox(width: 48, height: 48),
                    Text(
                      AppLocalizations.of(context)!.nowPlaying,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        _showPlaylistBottomSheet(context);
                      },
                      icon: const Icon(Icons.queue_music),
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double artSize = (constraints.maxHeight * 0.35).clamp(
                      120.0,
                      280.0,
                    );

                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              const SizedBox(height: 16),
                              _buildAlbumArt(
                                context,
                                artSize,
                                currentTrack.albumArt,
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildTrackInfo(
                                      context,
                                      currentTrack,
                                      false,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildProgressControl(context, provider, false),
                              const SizedBox(height: 16),
                              _buildPlaybackControls(context, provider, false),
                              const SizedBox(height: 16),
                              _buildExtraControls(context, provider, false),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumArt(BuildContext context, double size, String? albumArt) {
    return AnimatedBuilder(
      animation: _rotationController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _rotationController.value * 2 * math.pi,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 30,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(size / 2),
              child: _CachedCover(size: size, url: albumArt),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrackInfo(
    BuildContext context,
    AudioTrack currentTrack,
    bool isDesktop,
  ) {
    return Column(
      crossAxisAlignment: isDesktop
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: isDesktop ? MainAxisSize.min : MainAxisSize.max,
          mainAxisAlignment: isDesktop
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                currentTrack.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: isDesktop ? 28 : 24,
                ),
                textAlign: isDesktop ? TextAlign.center : TextAlign.start,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Cached-file badge.
            if (_isTrackCached(currentTrack.id)) ...[
              const SizedBox(width: 8),
              const Icon(Icons.offline_pin, size: 20, color: Colors.green),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // Live-card tracks show their live status here (updates via the
        // provider heartbeat); regular tracks show the artist line.
        if (currentTrack.metadata?['isLiveCard'] == true ||
            currentTrack.metadata?['isLive'] == true)
          Row(
            mainAxisSize: isDesktop ? MainAxisSize.min : MainAxisSize.max,
            mainAxisAlignment: isDesktop
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(
                Icons.circle,
                size: 12,
                color:
                    context.watch<AudioPlayerProvider>().isLiveCardOnline(
                      currentTrack.id,
                    )
                    ? Colors.red
                    : Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  context.watch<AudioPlayerProvider>().isLiveCardOnline(
                        currentTrack.id,
                      )
                      ? AppLocalizations.of(context)!.liveNow
                      : AppLocalizations.of(context)!.liveEnded,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color:
                        context.watch<AudioPlayerProvider>().isLiveCardOnline(
                          currentTrack.id,
                        )
                        ? Colors.red
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: isDesktop ? 16 : 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          )
        else
          Text(
            '${currentTrack.artist} · ASMR',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: isDesktop ? 18 : 16,
            ),
            textAlign: isDesktop ? TextAlign.center : TextAlign.start,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  /// Whether [trackId] has a downloaded file (checked against the manager's
  /// in-memory index; files are validated on startup / detail open).
  bool _isTrackCached(String trackId) {
    return DownloadManager.instance.isTrackCached(trackId);
  }

  Widget _buildProgressControl(
    BuildContext context,
    AudioPlayerProvider provider,
    bool isDesktop,
  ) {
    // Live-card tracks: if the room is streaming (per heartbeat) AND the
    // live stream is actually active in the decoder, show a "live" badge
    // with how long the stream has been live. If the room is offline, show
    // a neutral "not live" label instead of a fake seekable timeline.
    final isLiveCard =
        provider.currentTrack?.metadata?['isLiveCard'] == true ||
        provider.currentTrack?.metadata?['isLive'] == true;
    final isLiveActive = provider.isLiveActive;
    final liveOnline =
        isLiveCard && provider.isLiveCardOnline(provider.currentTrack!.id);
    if (isLiveCard && isLiveActive && liveOnline) {
      final liveMs = provider.currentTrack?.metadata?['liveTime'];
      String liveFor = '';
      if (liveMs is int && liveMs > 0) {
        final diff = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(liveMs),
        );
        liveFor = AppLocalizations.of(context)!.liveFor(_fmtClock(diff));
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.circle, size: 10, color: Colors.red),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context)!.liveNow,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (liveFor.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(liveFor, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(width: 16),
            Text(
              _formatTime(provider.position),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ],
        ),
      );
    }

    // A live-card track that is not actively streaming (offline / blocked):
    // show a neutral "not live" label instead of a fake seekable timeline.
    if (isLiveCard) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.circle,
              size: 10,
              color: liveOnline
                  ? Colors.green
                  : Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Text(
              liveOnline
                  ? AppLocalizations.of(context)!.liveNow
                  : AppLocalizations.of(context)!.liveEnded,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: liveOnline
                    ? Colors.green
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final position = provider.position;
    // Fall back to the track's known duration (e.g. from the bilibili view
    // API) while the provider has no duration yet (live or still decoding).
    final trackDuration = provider.currentTrack?.duration ?? Duration.zero;
    final duration = provider.duration > Duration.zero
        ? provider.duration
        : trackDuration;
    double sliderValue =
        (_dragPositionMs ?? position.inMilliseconds.toDouble());
    double maxDuration = duration.inMilliseconds.toDouble();
    if (maxDuration <= 0) maxDuration = 1.0;
    if (sliderValue > maxDuration) sliderValue = maxDuration;

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: isDesktop ? 4 : 4,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: isDesktop ? 6 : 6,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: sliderValue,
            min: 0.0,
            max: maxDuration,
            // While dragging, only preview the position; the expensive seek
            // (decoder + buffer stream rebuild) happens once on release.
            onChanged: (value) {
              setState(() => _dragPositionMs = value);
            },
            onChangeEnd: (value) {
              _dragPositionMs = null;
              provider.seek(Duration(milliseconds: value.toInt()));
            },
            activeColor: Theme.of(context).colorScheme.primary,
            inactiveColor: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatTime(position),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontSize: isDesktop ? 12 : 12),
              ),
              Text(
                _formatTime(duration),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontSize: isDesktop ? 12 : 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackControls(
    BuildContext context,
    AudioPlayerProvider provider,
    bool isDesktop,
  ) {
    final iconSize = isDesktop ? 32.0 : 40.0;
    final mainIconSize = isDesktop ? 48.0 : 60.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          onPressed: provider.playPrevious,
          icon: const Icon(Icons.skip_previous),
          iconSize: iconSize,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            // The current live-card is offline: disable the play button
            // (auto-plays once the heartbeat sees the room come online).
            final cur = provider.currentTrack;
            final liveCardOffline =
                cur != null &&
                (cur.metadata?['isLiveCard'] == true ||
                    cur.metadata?['isLive'] == true) &&
                !provider.isLiveCardOnline(cur.id) &&
                !provider.isLiveActive;
            return Transform.scale(
              scale: provider.isPlaying
                  ? 1.0 + (_pulseController.value * 0.1)
                  : 1.0,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: liveCardOffline
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : Theme.of(context).colorScheme.primary,
                  boxShadow: provider.isPlaying
                      ? [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ]
                      : null,
                ),
                child: IconButton(
                  onPressed: liveCardOffline
                      ? null
                      : () {
                          if (provider.playbackState == PlaybackState.error) {
                            provider.play();
                          } else if (provider.isPlaying) {
                            provider.pause();
                          } else {
                            provider.play();
                          }
                        },
                  icon: provider.playbackState == PlaybackState.buffering
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          provider.playbackState == PlaybackState.error
                              ? Icons.refresh
                              : provider.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          size: mainIconSize * 0.6,
                          color: liveCardOffline
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : Colors.white,
                        ),
                  iconSize: mainIconSize,
                ),
              ),
            );
          },
        ),
        IconButton(
          onPressed: provider.playNext,
          icon: const Icon(Icons.skip_next),
          iconSize: iconSize,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }

  Widget _buildLoopIcon(BuildContext context, AudioPlayerProvider provider) {
    IconData icon;
    Color? color;

    switch (provider.loopMode) {
      case LoopMode.off:
        icon = Icons.repeat;
        color = Theme.of(context).colorScheme.onSurfaceVariant;
        break;
      case LoopMode.all:
        icon = Icons.repeat;
        color = Theme.of(context).colorScheme.primary;
        break;
      case LoopMode.one:
        icon = Icons.repeat_one;
        color = Theme.of(context).colorScheme.primary;
        break;
    }

    return Icon(icon, color: color);
  }

  Widget _buildExtraControls(
    BuildContext context,
    AudioPlayerProvider provider,
    bool isDesktop,
  ) {
    final iconSize = isDesktop ? 28.0 : 24.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Live recording toggle (any live-card track). Downloads are only
        // offered from the source/detail pages, not the player.
        if (provider.currentTrack?.metadata?['isLiveCard'] == true &&
            _liveSourceFor(provider.currentTrack!.sourceTypeId) != null)
          Builder(
            builder: (context) {
              final room = context.watch<LiveWatchManager>().roomForTrack(
                provider.currentTrack!,
              );
              final isRec = room?.isRecording ?? false;
              final isWatching = room?.enabled ?? false;
              return IconButton(
                onPressed: () => _toggleLiveRecording(provider.currentTrack!),
                icon: Icon(
                  isRec ? Icons.stop_circle : Icons.fiber_manual_record,
                ),
                iconSize: iconSize,
                color: isRec
                    ? Theme.of(context).colorScheme.primary
                    : isWatching
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                tooltip: isRec
                    ? AppLocalizations.of(context)!.stopRecording
                    : AppLocalizations.of(context)!.recordLive,
              );
            },
          ),
        // Quality selector for remote on-demand media (tap to change and
        // replay from the current position).
        if (provider.currentTrack != null &&
            provider.currentTrack!.metadata?['isLiveCard'] != true &&
            provider.currentTrack!.sourceTypeId != 'local')
          PopupMenuButton<String>(
            tooltip: AppLocalizations.of(context)!.audioQuality,
            initialValue: provider.quality,
            icon: const Icon(Icons.high_quality_outlined),
            iconSize: iconSize,
            onSelected: (q) => provider.replayWithQuality(q),
            itemBuilder: (context) => qualityMenuItems(context),
          ),
        IconButton(
          onPressed: provider.toggleShuffle,
          icon: const Icon(Icons.shuffle),
          iconSize: iconSize,
          color: provider.isShuffleEnabled
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        IconButton(
          onPressed: provider.toggleLoopMode,
          icon: _buildLoopIcon(context, provider),
          iconSize: iconSize,
        ),
        IconButton(
          onPressed: () => _showSleepTimerDialog(context, provider),
          icon: Icon(
            provider.isSleepTimerActive ? Icons.timer : Icons.timer_outlined,
          ),
          iconSize: iconSize,
          color: provider.isSleepTimerActive
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        IconButton(
          onPressed: () {
            _showEffects(context);
          },
          icon: const Icon(Icons.equalizer),
          iconSize: iconSize,
          color: context.watch<EffectsProvider>().isAnyEffectEnabled
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

/// Cover image that downloads the URL into the metadata cache first (with
/// anti-hotlink headers when needed) and displays the local file, falling
/// back to a headphones icon.
class _CachedCover extends StatefulWidget {
  final double size;
  final String? url;

  const _CachedCover({required this.size, this.url});

  @override
  State<_CachedCover> createState() => _CachedCoverState();
}

class _CachedCoverState extends State<_CachedCover> {
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _CachedCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _localPath = null;
      _load();
    }
  }

  Future<void> _load() async {
    final url = widget.url;
    if (url == null || url.isEmpty) return;
    final local = await CacheService().cacheRemoteFile(
      url,
      headers: CacheService.coverHeadersFor(url),
    );
    // Ignore stale responses: the widget may have moved to another URL
    // while the cache fetch was in flight.
    if (mounted && local != null && widget.url == url) {
      setState(() => _localPath = local);
    }
  }

  Widget _fallback(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            Theme.of(context).colorScheme.surfaceContainerHighest,
            Theme.of(context).colorScheme.surfaceContainer,
          ],
        ),
      ),
      child: Icon(
        Icons.headphones,
        size: widget.size * 0.4,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = _localPath;
    if (local == null) return _fallback(context);
    return Image.file(
      File(local),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _fallback(context),
    );
  }
}

/// Quality menu entries shared by the player and the download buttons.
List<PopupMenuEntry<String>> qualityMenuItems(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  String label(String q) {
    switch (q) {
      case 'auto':
        return l10n.qualityAuto;
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

  return [
    'auto',
    'flac',
    '320',
    '192',
    '132',
    '64',
  ].map((q) => PopupMenuItem(value: q, child: Text(label(q)))).toList();
}

/// Sleep timer panel: live countdown when active, quick presets, a custom
/// minute input and (mobile) smart sleep detection.
class SleepTimerPanel extends StatefulWidget {
  final AudioPlayerProvider provider;

  const SleepTimerPanel({super.key, required this.provider});

  @override
  State<SleepTimerPanel> createState() => _SleepTimerPanelState();
}

class _SleepTimerPanelState extends State<SleepTimerPanel> {
  Timer? _ticker;
  // Duration picked on the wheel (default 30 min). Applied via the start
  // button; wheel changes just update this value.
  Duration _customDuration = const Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant SleepTimerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    if (widget.provider.isSleepTimerActive) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        // Schedule the rebuild outside the timer callback / any active build
        // or layout phase to avoid re-entrant frame scheduling (which can
        // trip Flutter's mouse-tracker debug assertions on desktop).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _start(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes <= 0) return;
    widget.provider.setSleepTimer(duration);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: AppConstants.snackBarDuration,
        content: Text(
          AppLocalizations.of(context)!.sleepTimerSet(minutes),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onInverseSurface,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final sleepService = context.watch<SleepDetectionService>();

    final active = provider.isSleepTimerActive;
    final remaining = provider.sleepTimerRemaining;
    final total = provider.sleepTimerDuration;
    final endTime = provider.sleepTimerEndTime;
    double progress = 1.0;
    if (active && remaining != null && total != null && total.inSeconds > 0) {
      progress = (remaining.inSeconds / total.inSeconds).clamp(0.0, 1.0);
    }
    // Keep the countdown timer alive while the panel is open. Scheduled
    // post-frame so the timer never starts mid-build/layout (re-entrancy
    // can trip desktop mouse-tracker debug assertions).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncTicker();
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ---- Active state card ----
        if (active) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.timer, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.sleepTimerActiveTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        provider.cancelSleepTimer();
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.close),
                      tooltip: l10n.sleepTimerOff,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Live countdown clock.
                Builder(
                  builder: (context) {
                    final rem = remaining ?? Duration.zero;
                    final h = rem.inHours;
                    final m = rem.inMinutes.remainder(60);
                    final s = rem.inSeconds.remainder(60);
                    final mm = m.toString().padLeft(2, '0');
                    final ss = s.toString().padLeft(2, '0');
                    final clock = h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
                    return Column(
                      children: [
                        Text(
                          clock,
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (endTime != null)
                          Text(
                            l10n.sleepTimerEndsAt(_formatClockTime(endTime)),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.sleepTimerRemaining(
                    _fmtClockTop(remaining ?? Duration.zero),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 12),
        ],

        // ---- Quick presets ----
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l10n.sleepTimerPresetLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final minutes in [15, 30, 60]) ...[
              Expanded(
                child: _PresetChip(
                  label: '$minutes ${l10n.minutesSuffix}'.trim(),
                  selected:
                      active && total != null && total.inMinutes == minutes,
                  onTap: () => _start(Duration(minutes: minutes)),
                ),
              ),
              if (minutes != 60) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 20),

        // ---- Custom: hours + minutes pickers ----
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l10n.sleepTimerCustomLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _customDuration.inHours.clamp(0, 8),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (var h = 0; h <= 8; h++)
                    DropdownMenuItem(
                      value: h,
                      child: Text(
                        h == 0
                            ? '0 ${l10n.hoursSuffix}'
                            : '$h ${l10n.hoursSuffix}',
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _customDuration = Duration(
                      hours: value,
                      minutes: _customDuration.inMinutes.remainder(60),
                    );
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _customDuration.inMinutes.remainder(60),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (var m = 0; m < 60; m += 5)
                    DropdownMenuItem(
                      value: m,
                      child: Text('$m ${l10n.minutesSuffix}'),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _customDuration = Duration(
                      hours: _customDuration.inHours,
                      minutes: value,
                    );
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _start(_customDuration),
            icon: const Icon(Icons.timer),
            label: Text(
              '${l10n.sleepTimerSetStart}'
              ' ${_formatWheelDuration(_customDuration, l10n)}',
            ),
          ),
        ),
        const SizedBox(height: 8),

        // ---- Smart Sleep Detection (Mobile Only) ----
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ...[
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.smartSleepDetection),
            subtitle: Text(l10n.smartSleepDetectionSubtitle),
            value: sleepService.isMonitoring,
            onChanged: (value) {
              if (value) {
                sleepService.startMonitoring(
                  onSleepDetected: () {
                    provider.setSleepTimer(const Duration(minutes: 1));
                  },
                );
              } else {
                sleepService.stopMonitoring();
              }
            },
            secondary: const Icon(Icons.nights_stay),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Formats a [DateTime] as "HH:MM" (24h).
String _formatClockTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Clock-style H:MM:SS / MM:SS formatting for durations.
String _fmtClockTop(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = two(d.inMinutes.remainder(60));
  final s = two(d.inSeconds.remainder(60));
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Formats a wheel-picked duration as "1 h 30 min" / "45 min".
String _formatWheelDuration(Duration d, AppLocalizations l10n) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0 && m > 0) {
    return '$h ${l10n.hoursSuffix} $m ${l10n.minutesSuffix}';
  }
  if (h > 0) return '$h ${l10n.hoursSuffix}';
  return '$m ${l10n.minutesSuffix}';
}

/// A selectable preset chip for the sleep timer.
class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
