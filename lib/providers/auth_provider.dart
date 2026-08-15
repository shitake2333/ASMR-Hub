import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asmr_hub/models/account_info.dart';
import 'package:asmr_hub/services/audio_source_manager.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/sources/base/base_source.dart';

class AuthProvider extends ChangeNotifier {
  final SharedPreferences _prefs;
  final LogService _logger = LogService();
  final AudioSourceManager _sourceManager = AudioSourceManager();

  static const String _authKeyPrefix = 'auth_data_';

  AuthProvider(this._prefs);

  Future<void> initialize() async {
    // Ensure source manager is initialized so sources are registered
    await _sourceManager.initialize();
    _logger.info(
      'AuthProvider.initialize: sources=${_sourceManager.getSources().map((s) => s.sourceTypeId).join(',')}',
    );
    await _loadAllAuthData();
  }

  Future<List<String>> checkSessions() async {
    final expiredSources = <String>[];
    final sources = _sourceManager.getSources();

    for (final source in sources) {
      if (source is! BaseAudioSource) continue;
      if (!source.requiresAuth || !source.auth.isLoggedIn) continue;

      try {
        await source.auth.checkLoginStatus();
        if (!source.auth.isLoggedIn) {
          expiredSources.add(source.sourceName);
          // Clear invalid session data
          await clearAuthData(source.sourceTypeId);
        }
      } catch (e) {
        _logger.error('Failed to check session for ${source.sourceTypeId}', e);
      }
    }

    return expiredSources;
  }

  Future<void> _loadAllAuthData() async {
    final sources = _sourceManager.getSources();
    for (final source in sources) {
      if (source is! BaseAudioSource) continue;
      if (!source.requiresAuth) continue;

      final key = '$_authKeyPrefix${source.sourceTypeId}';
      final jsonStr = _prefs.getString(key);
      if (jsonStr != null) {
        try {
          final data = jsonDecode(jsonStr);
          final info = AccountInfo.fromJson(data);

          if (info.cookie != null) {
            await source.auth.loginWithCookie(info.cookie!);
            _logger.info('Restored session for ${source.sourceTypeId}');
          }
        } catch (e) {
          _logger.error(
            'Failed to restore session for ${source.sourceTypeId}',
            e,
          );
        }
      }
    }
    notifyListeners();
  }

  Future<void> saveAuthData(String sourceTypeId, AccountInfo info) async {
    final key = '$_authKeyPrefix$sourceTypeId';
    await _prefs.setString(key, jsonEncode(info.toJson()));
    notifyListeners();
  }

  Future<void> clearAuthData(String sourceTypeId) async {
    final key = '$_authKeyPrefix$sourceTypeId';
    await _prefs.remove(key);
    notifyListeners();
  }

  Future<void> onLoginSuccess(String sourceTypeId, AccountInfo info) async {
    await saveAuthData(sourceTypeId, info);
  }

  Future<void> logout(String sourceTypeId) async {
    final sources = _sourceManager.getSources();
    for (final s in sources) {
      if (s.sourceTypeId == sourceTypeId && s is BaseAudioSource) {
        await s.auth.logout();
        break;
      }
    }
    await clearAuthData(sourceTypeId);
  }
}
