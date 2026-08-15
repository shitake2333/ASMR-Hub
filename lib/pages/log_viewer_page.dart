import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:asmr_hub/l10n/app_localizations.dart';
import 'package:asmr_hub/constants.dart';
import '../services/log_service.dart';

class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  String _logs = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    String logs = '';
    try {
      logs = await LogService().getLogs();
    } catch (e) {
      logs = 'Failed to load logs: $e';
    }
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _isLoading = false;
    });
  }

  Future<void> _clearLogs() async {
    await LogService().clearLogs();
    if (mounted) {
      await _loadLogs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.systemLogTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadLogs),
          IconButton(icon: const Icon(Icons.delete), onPressed: _clearLogs),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _logs));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: AppConstants.snackBarDuration,
                  content: Text(
                    AppLocalizations.of(context)!.logsCopied,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                _logs,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ),
    );
  }
}
