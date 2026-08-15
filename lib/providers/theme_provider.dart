import 'package:flutter/material.dart';

import 'package:asmr_hub/services/preferences_service.dart';

class ThemeProvider extends ChangeNotifier {
  /// Default UI font on Windows: a CJK-capable family so Latin and Han
  /// glyphs render with the same weight (Flutter's default Segoe UI +
  /// fallback mixes weights for Chinese text).
  static const String defaultFontFamily = 'Microsoft YaHei UI';

  late ThemeMode _themeMode;
  late Color _seedColor;
  String? _fontFamily;
  double _textScaleFactor = 1.0;
  Locale? _locale;

  ThemeProvider() {
    _loadSettings();
  }

  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;

  /// Effective font family: the user's choice or the CJK default.
  String? get fontFamily => _fontFamily ?? defaultFontFamily;
  double get textScaleFactor => _textScaleFactor;
  Locale? get locale => _locale;

  void _loadSettings() {
    final modeStr = PreferencesService().getThemeMode();
    switch (modeStr) {
      case 'light':
        _themeMode = ThemeMode.light;
        break;
      case 'dark':
        _themeMode = ThemeMode.dark;
        break;
      default:
        _themeMode = ThemeMode.system;
    }

    final colorValue = PreferencesService().getThemeColor();
    _seedColor = Color(colorValue);

    _fontFamily = PreferencesService().getFontFamily();
    // Guard against invalid persisted names (raw file names returned by the
    // old system_fonts-based picker, e.g. "simhei", "SourceHanSansCN-Normal",
    // "segoeui"): real DirectWrite family names never carry a file-like
    // suffix or lowercase single-token names that match known file stems.
    final savedFont = _fontFamily;
    if (savedFont != null) {
      final t = savedFont.trim();
      final fileLike =
          // Known raw file stems from the old picker.
          const {
            'simhei',
            'simsunb',
            'simsunextg',
            'segoeui',
            'segoeuib',
            'segoeuii',
            'segoeuil',
            'segoeuisl',
            'segoeuiz',
            'msyh',
            'msyhbd',
            'arialbd',
            'arialbi',
            'ariali',
            'arialn',
          }.contains(t.toLowerCase()) ||
          // "Foo-Bar-Suffix" style file stems.
          RegExp(r'-\w+$').hasMatch(t) ||
          t.toLowerCase().contains('.ttf') ||
          t.toLowerCase().contains('.ttc');
      if (fileLike) _fontFamily = null;
    }
    _textScaleFactor = PreferencesService().getTextScaleFactor();

    final localeStr = PreferencesService().getLocale();
    if (localeStr != null) {
      final parts = localeStr.split('_');
      if (parts.length == 2) {
        _locale = Locale(parts[0], parts[1]);
      } else {
        _locale = Locale(parts[0]);
      }
    } else {
      // No preference found, try to detect system locale
      try {
        final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
        if (systemLocale.languageCode == 'zh') {
          _locale = const Locale('zh');
        } else {
          _locale = const Locale('en');
        }
      } catch (e) {
        _locale = const Locale('en');
      }
    }

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    String modeStr;
    switch (mode) {
      case ThemeMode.light:
        modeStr = 'light';
        break;
      case ThemeMode.dark:
        modeStr = 'dark';
        break;
      default:
        modeStr = 'system';
    }
    await PreferencesService().setThemeMode(modeStr);
    notifyListeners();
  }

  Future<void> setSeedColor(Color color) async {
    _seedColor = color;
    await PreferencesService().setThemeColor(color.toARGB32());
    notifyListeners();
  }

  Future<void> setFontFamily(String? fontFamily) async {
    if (fontFamily == _fontFamily) return;
    _fontFamily = fontFamily;
    await PreferencesService().setFontFamily(fontFamily);
    notifyListeners();
  }

  Future<void> setTextScaleFactor(double scaleFactor) async {
    _textScaleFactor = scaleFactor;
    await PreferencesService().setTextScaleFactor(scaleFactor);
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    if (locale == null) {
      await PreferencesService().setLocale(null);
    } else {
      await PreferencesService().setLocale(locale.toString());
    }
    notifyListeners();
  }
}
