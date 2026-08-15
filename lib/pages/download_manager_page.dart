import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:asmr_hub/l10n/app_localizations.dart';
import 'package:asmr_hub/services/download_manager.dart';
import 'package:asmr_hub/services/live_watch_manager.dart';

/// Download manager page: lists background download tasks with progress,
/// cancel and delete actions, plus the background live-recording watchdog.
class DownloadManagerPage extends StatelessWidget {
  const DownloadManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.downloadManagement),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.downloadsTab),
              Tab(text: l10n.watchRoomsTab),
            ],
          ),
        ),
        body: const TabBarView(children: [_DownloadsTab(), _WatchRoomsTab()]),
      ),
    );
  }
}

class _DownloadsTab extends StatelessWidget {
  const _DownloadsTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadManager>(
      builder: (context, manager, _) {
        final tasks = manager.tasks;
        if (tasks.isEmpty) {
          return Center(
            child: Text(
              AppLocalizations.of(context)!.noDownloads,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: tasks.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final task = tasks[index];
            return ListTile(
              leading: _statusIcon(task),
              title: Text(
                task.track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  if (task.isActive)
                    const LinearProgressIndicator(minHeight: 3),
                  const SizedBox(height: 4),
                  Text(
                    _statusText(context, task),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              trailing: task.isActive
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: AppLocalizations.of(context)!.cancel,
                      onPressed: () => manager.cancel(task.trackId),
                    )
                  : IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: AppLocalizations.of(context)!.delete,
                      onPressed: () => manager.remove(task.trackId),
                    ),
            );
          },
        );
      },
    );
  }

  Widget _statusIcon(DownloadTask task) {
    switch (task.status) {
      case DownloadTaskStatus.downloading:
      case DownloadTaskStatus.queued:
        return const Icon(Icons.downloading);
      case DownloadTaskStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green);
      case DownloadTaskStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
      case DownloadTaskStatus.canceled:
        return const Icon(Icons.cancel, color: Colors.grey);
    }
  }

  String _statusText(BuildContext context, DownloadTask task) {
    final l10n = AppLocalizations.of(context)!;
    final mb = (task.bytesDone / (1024 * 1024)).toStringAsFixed(1);
    switch (task.status) {
      case DownloadTaskStatus.queued:
        return l10n.downloadQueued;
      case DownloadTaskStatus.downloading:
        return '${l10n.downloading} ($mb MB)';
      case DownloadTaskStatus.completed:
        return '${l10n.downloadCompletedShort} · $mb MB';
      case DownloadTaskStatus.failed:
        return '${l10n.downloadFailedShort}: ${task.error ?? ''}';
      case DownloadTaskStatus.canceled:
        return l10n.downloadCanceled;
    }
  }
}

class _WatchRoomsTab extends StatefulWidget {
  const _WatchRoomsTab();

  @override
  State<_WatchRoomsTab> createState() => _WatchRoomsTabState();
}

class _WatchRoomsTabState extends State<_WatchRoomsTab> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresh live/recording durations every second.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Future<void> _addRoom(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.addRoom),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://live.bilibili.com/27109059',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    final room = await LiveWatchManager.instance.addRoomByUrl(url);
    if (room == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            l10n.addRoomFailed,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onInverseSurface,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<LiveWatchManager>(
      builder: (context, watch, _) {
        final rooms = watch.rooms;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                l10n.watchRoomsHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: rooms.isEmpty
                  ? Center(
                      child: Text(
                        l10n.noWatchRooms,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: rooms.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final room = rooms[index];
                        final recording = room.isRecording;
                        // Status line: watching/recording + durations.
                        String status;
                        if (recording) {
                          final recFor = room.recordingSince == null
                              ? ''
                              : ' · ${l10n.recordingFor(_fmt(DateTime.now().difference(room.recordingSince!)))}';
                          status = '${l10n.roomRecording}$recFor';
                        } else if (room.enabled) {
                          final liveFor = room.liveSince == null
                              ? ''
                              : ' · ${l10n.liveFor(_fmt(DateTime.now().difference(room.liveSince!)))}';
                          status = '${l10n.roomWatching}$liveFor';
                        } else {
                          status = l10n.roomPaused;
                        }
                        return ListTile(
                          leading: Icon(
                            recording ? Icons.fiber_manual_record : Icons.radar,
                            color: recording
                                ? Colors.red
                                : room.enabled
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                          ),
                          title: Text(
                            room.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '$status · ${room.sourceTypeId} ${room.roomId}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: room.enabled,
                                onChanged: (_) => watch.toggleEnabled(index),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: l10n.delete,
                                onPressed: () => watch.removeRoom(index),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: () => _addRoom(context),
                icon: const Icon(Icons.add),
                label: Text(l10n.addRoom),
              ),
            ),
          ],
        );
      },
    );
  }
}
