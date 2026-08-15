import 'package:flutter/material.dart';
import 'package:asmr_hub/l10n/app_localizations.dart';
import 'package:asmr_hub/constants.dart';
import '../services/audio_source_manager.dart';
import '../services/cache_service.dart';
import '../services/log_service.dart';
import '../sources/base/base_source.dart';

class CacheManagementPage extends StatefulWidget {
  const CacheManagementPage({super.key});

  @override
  State<CacheManagementPage> createState() => _CacheManagementPageState();
}

class _CacheManagementPageState extends State<CacheManagementPage> {
  final AudioSourceManager _sourceManager = AudioSourceManager();
  final CacheService _cacheService = CacheService();
  Map<String, int> _cacheSizes = {};
  int _totalSize = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCacheSizes();
  }

  Future<void> _loadCacheSizes() async {
    if (mounted) setState(() => _isLoading = true);

    int total = 0;
    final sizes = <String, int>{};

    final sources = _sourceManager.getSources();
    try {
      for (final source in sources) {
        if (source is BaseAudioSource) {
          final size = await _cacheService
              .getCacheSize(source.sourceTypeId)
              .timeout(const Duration(seconds: 15));
          sizes[source.sourceTypeId] = size;
          total += size;
        }
      }
    } catch (e) {
      LogService().error('Failed to load cache sizes', e);
    }

    if (mounted) {
      setState(() {
        _cacheSizes = sizes;
        _totalSize = total;
        _isLoading = false;
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _clearCache(String? sourceTypeId) async {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.confirmClearTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Text(
          sourceTypeId == null
              ? AppLocalizations.of(context)!.confirmClearAllContent
              : AppLocalizations.of(context)!.confirmClearSourceContent,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              if (mounted) setState(() => _isLoading = true);

              try {
                if (sourceTypeId == null) {
                  await _cacheService.clearAllCache();
                } else {
                  await _cacheService.clearCache(sourceTypeId);
                }
              } catch (e) {
                LogService().error('Failed to clear cache', e);
              }

              await _loadCacheSizes();

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    duration: AppConstants.snackBarDuration,
                    content: Text(
                      AppLocalizations.of(context)!.cacheCleared,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onInverseSurface,
                      ),
                    ),
                  ),
                );
              }
            },
            child: Text(
              AppLocalizations.of(context)!.clear,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sourceManager.getSources();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.cacheManagementTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCacheSizes,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          AppLocalizations.of(context)!.totalCacheSize,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatSize(_totalSize),
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _totalSize > 0
                              ? () => _clearCache(null)
                              : null,
                          icon: const Icon(Icons.delete_forever),
                          label: Text(
                            AppLocalizations.of(context)!.clearAllCache,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: sources.length,
                    itemBuilder: (context, index) {
                      final source = sources[index];
                      if (source is! BaseAudioSource) {
                        return const SizedBox.shrink();
                      }

                      final size = _cacheSizes[source.sourceTypeId] ?? 0;

                      return ListTile(
                        leading: Icon(source.icon),
                        title: Text(
                          source.sourceName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: Text(
                          AppLocalizations.of(
                            context,
                          )!.spaceUsed(_formatSize(size)),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: size > 0
                              ? () => _clearCache(source.sourceTypeId)
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
