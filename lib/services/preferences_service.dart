import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService() => _instance;
  PreferencesService._internal();

  static const String _keyCachePath = 'cache_path';
  static const String _keyCacheFormat = 'cache_format';
  static const String _keyAudioQuality = 'audio_quality';
  static const String _keyDownloadPath = 'download_path';
  static const String _keyMaxDownloadRate = 'max_download_rate';
  static const String _keyMaxDownloadThreads = 'max_download_threads';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyThemeColor = 'theme_color';
  static const String _keyFontFamily = 'font_family';
  static const String _keyTextScaleFactor = 'text_scale_factor';
  static const String _keyLocale = 'locale';
  static const String _keyAutoPlay = 'auto_play';
  static const String _keyNotifications = 'notifications_enabled';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Theme Settings
  String getThemeMode() {
    return _prefs.getString(_keyThemeMode) ?? 'system';
  }

  Future<void> setThemeMode(String mode) async {
    await _prefs.setString(_keyThemeMode, mode);
  }

  int getThemeColor() {
    return _prefs.getInt(_keyThemeColor) ?? 0xFF9C27B0; // Default Purple
  }

  Future<void> setThemeColor(int colorValue) async {
    await _prefs.setInt(_keyThemeColor, colorValue);
  }

  String? getFontFamily() {
    return _prefs.getString(_keyFontFamily);
  }

  Future<void> setFontFamily(String? fontFamily) async {
    if (fontFamily == null) {
      await _prefs.remove(_keyFontFamily);
    } else {
      await _prefs.setString(_keyFontFamily, fontFamily);
    }
  }

  double getTextScaleFactor() {
    return _prefs.getDouble(_keyTextScaleFactor) ?? 1.0;
  }

  Future<void> setTextScaleFactor(double scaleFactor) async {
    await _prefs.setDouble(_keyTextScaleFactor, scaleFactor);
  }

  String? getLocale() {
    return _prefs.getString(_keyLocale);
  }

  Future<void> setLocale(String? locale) async {
    if (locale == null) {
      await _prefs.remove(_keyLocale);
    } else {
      await _prefs.setString(_keyLocale, locale);
    }
  }

  Future<String> _getDefaultDataDirectory() async {
    if (!kIsWeb && Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null) {
        final dir = Directory(path.join(localAppData, 'ASMRHub'));
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return dir.path;
      }
    }

    if (!kIsWeb && (Platform.isLinux || Platform.isMacOS)) {
      final appSupportDir = await getApplicationSupportDirectory();
      // Ensure we are in a dedicated folder if the system didn't give us one (though it usually does)
      // But to be safe and consistent with the request for "ASMRHub" folder:
      // Note: getApplicationSupportDirectory usually returns .../com.example.asmr_hub or similar.
      // We will trust path_provider for Linux/Mac to be standard compliant,
      // but if we want to enforce "ASMRHub" name we might need to tweak.
      // However, standard practice is to use what the OS gives for the app.
      // The user said "similar logic" for Linux/Mac.
      return appSupportDir.path;
    }

    final appDir = await getApplicationDocumentsDirectory();
    return appDir.path;
  }

  Future<String> getCachePath() async {
    final customPath = _prefs.getString(_keyCachePath);
    if (customPath != null) return customPath;

    final baseDir = await _getDefaultDataDirectory();
    return path.join(baseDir, 'cache');
  }

  Future<void> setCachePath(String path) async {
    await _prefs.setString(_keyCachePath, path);
  }

  /// Cache format for FFmpeg-decoded media: 'off' (no cache),
  /// 'wav' (lossless PCM, ~10 MB/min) or 'mp3' (compressed, ~1.4 MB/min).
  String getCacheFormat() {
    return _prefs.getString(_keyCacheFormat) ?? 'mp3';
  }

  Future<void> setCacheFormat(String format) async {
    await _prefs.setString(_keyCacheFormat, format);
  }

  /// Preferred audio quality for remote on-demand media:
  /// 'auto' | 'flac' | '320' | '192' | '132' | '64' (kbps).
  String getAudioQuality() {
    return _prefs.getString(_keyAudioQuality) ?? 'auto';
  }

  Future<void> setAudioQuality(String quality) async {
    await _prefs.setString(_keyAudioQuality, quality);
  }

  Future<String> getDownloadPath() async {
    final customPath = _prefs.getString(_keyDownloadPath);
    if (customPath != null) return customPath;

    final baseDir = await _getDefaultDataDirectory();
    return path.join(baseDir, 'downloads');
  }

  Future<void> setDownloadPath(String path) async {
    await _prefs.setString(_keyDownloadPath, path);
  }

  Future<void> resetPaths() async {
    await _prefs.remove(_keyCachePath);
    await _prefs.remove(_keyDownloadPath);
  }

  /// Maximum download rate in KB/s. 0 means unlimited.
  int getMaxDownloadRate() {
    return _prefs.getInt(_keyMaxDownloadRate) ?? 0;
  }

  Future<void> setMaxDownloadRate(int kbPerSec) async {
    await _prefs.setInt(_keyMaxDownloadRate, kbPerSec);
  }

  /// Maximum concurrent download threads. Must be >= 1.
  int getMaxDownloadThreads() {
    final v = _prefs.getInt(_keyMaxDownloadThreads) ?? 1;
    return v < 1 ? 1 : v;
  }

  Future<void> setMaxDownloadThreads(int threads) async {
    await _prefs.setInt(_keyMaxDownloadThreads, threads < 1 ? 1 : threads);
  }

  bool getAutoPlay() => _prefs.getBool(_keyAutoPlay) ?? false;

  Future<void> setAutoPlay(bool value) async {
    await _prefs.setBool(_keyAutoPlay, value);
  }

  bool getNotificationsEnabled() => _prefs.getBool(_keyNotifications) ?? true;

  Future<void> setNotificationsEnabled(bool value) async {
    await _prefs.setBool(_keyNotifications, value);
  }
}
