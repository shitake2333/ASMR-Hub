import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  /// Rotate the log file when it grows beyond this size.
  static const int _maxLogBytes = 2 * 1024 * 1024; // 2 MB

  /// Only keep this many newest lines when serving logs to the viewer.
  static const int _maxDisplayLines = 3000;

  File? _logFile;
  final List<String> _memoryLogs = [];

  /// Serialized write chain: every file write is appended to this future so
  /// concurrent log calls can never interleave and corrupt the file.
  Future<void> _writeQueue = Future<void>.value();

  Future<void> initialize() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      _logFile = File('${directory.path}/app_logs.txt');
      if (!await _logFile!.exists()) {
        await _logFile!.create();
      }
    } catch (e) {
      debugPrint('Failed to initialize logger: $e');
    }
  }

  void info(String message) => _log('INFO', message);
  void warning(String message) => _log('WARN', message);
  void error(String message, [dynamic error, StackTrace? stackTrace]) =>
      _log('ERROR', '$message ${error ?? ''} ${stackTrace ?? ''}');

  void _log(String level, String message) {
    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '[$timestamp] [$level] $message';

    // Print to console for debug
    if (kDebugMode) {
      debugPrint(logMessage);
    }

    // Add to memory
    _memoryLogs.add(logMessage);
    if (_memoryLogs.length > 1000) {
      _memoryLogs.removeAt(0);
    }

    // Write to file, serialized; rotate when the file gets too large.
    final line = '$logMessage\n';
    _writeQueue = _writeQueue.then((_) async {
      try {
        final file = _logFile;
        if (file == null) return;
        if (await file.length() > _maxLogBytes) {
          await _rotate();
        }
        await file.writeAsString(line, mode: FileMode.append);
      } catch (e) {
        // Never let logging break the app.
      }
    });
  }

  /// Rotates the log file: keeps one previous generation as `.old`.
  Future<void> _rotate() async {
    final file = _logFile;
    if (file == null) return;
    final old = File('${file.path}.old');
    if (await old.exists()) {
      await old.delete();
    }
    if (await file.exists()) {
      await file.rename(old.path);
    }
    await file.create();
    debugPrint('Log file rotated');
  }

  Future<String> getLogs() async {
    await _writeQueue;
    if (_logFile != null && await _logFile!.exists()) {
      try {
        final text = await _logFile!.readAsString();
        return _tail(text);
      } catch (e) {
        // The file may contain non-UTF8 bytes from older versions; fall
        // back to a lossless single-byte decode so the viewer still works.
        try {
          final bytes = await _logFile!.readAsBytes();
          return _tail(latin1.decode(bytes));
        } catch (_) {
          return _memoryLogs.join('\n');
        }
      }
    }
    return _memoryLogs.join('\n');
  }

  /// Keeps only the newest lines so the viewer never renders a huge string.
  static String _tail(String text) {
    final lines = text.split('\n');
    if (lines.length <= _maxDisplayLines) return text;
    return lines.sublist(lines.length - _maxDisplayLines).join('\n');
  }

  Future<void> clearLogs() async {
    await _writeQueue;
    _memoryLogs.clear();
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.writeAsString('');
    }
  }
}
