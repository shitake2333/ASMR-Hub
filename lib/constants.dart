import 'package:flutter/material.dart';

class AppConstants {
  // App Info
  static const String appName = 'ASMR Hub';
  static const String appVersion = '1.0.0';
  static const String appDeveloper = 'shitake233';
  static const String appEmail = 'z1522716486@hotmail.com';
  static const String githubUrl = 'https://github.com/shitake2333/ASMR-Hub';

  static const String appLicense = '''MIT License

Copyright (c) 2025 shitake233

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.''';

  // Theme Colors
  static const List<Color> themeColors = [
    Colors.purple,
    Colors.blue,
    Colors.teal,
    Color(0xFF3EB559),
    Colors.orange,
    Colors.red,
    Color(0xFFFF6699),
    Colors.indigo,
    Colors.blueGrey,
  ];

  // UI Constants
  static const Duration snackBarDuration = Duration(seconds: 2);

  // Localization
  static const List<Locale> supportedLocales = [Locale('en'), Locale('zh')];

  static String getLanguageName(Locale locale) {
    switch (locale.languageCode) {
      case 'zh':
        return '简体中文';
      case 'en':
        return 'English';
      default:
        return locale.languageCode;
    }
  }
}
