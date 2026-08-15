import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:asmr_hub/models/account_info.dart';
import 'package:asmr_hub/pages/web_login_page.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/sources/base/source_auth.dart';

/// YouTube authentication.
///
/// YouTube does not expose a public cookie-validation API, so we validate the
/// session by requesting the account page: an authenticated request returns
/// 200, while an unauthenticated one is redirected (303) to Google sign-in.
class YouTubeAuth extends SourceAuth {
  YouTubeAuth() : super('https://www.youtube.com');

  final LogService _logger = LogService();

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  @override
  bool get requiresAuth => true;

  @override
  bool get supportsQrCodeLogin => false;

  @override
  bool get supportsWebLogin => true;

  @override
  bool get supportsCookieLogin => true;

  @override
  bool get supportsCredentialsLogin => false;

  @override
  Future<void> loginWithCredentials(String username, String password) async {
    throw UnsupportedError('YouTube does not support username/password login');
  }

  bool _isLoggedIn = false;
  AccountInfo? _currentUser;
  String? _cookie;

  @override
  bool get isLoggedIn => _isLoggedIn;

  @override
  AccountInfo? get currentUser => _currentUser;

  @override
  String? get cookie => _cookie;

  @override
  Future<void> loginWithCookie(String cookie) async {
    _cookie = cookie;
    final ok = await _validateAndFetchUser();
    if (!ok) {
      _isLoggedIn = false;
      _currentUser = null;
      _logger.warning('YouTube cookie validation failed');
    }
  }

  /// Validate the session cookie and fetch the user's channel info.
  Future<bool> _validateAndFetchUser() async {
    final cookie = _cookie;
    if (cookie == null || cookie.isEmpty) return false;

    try {
      final response = await clientSession.get<dynamic>(
        'https://www.youtube.com/account',
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
          headers: {
            'Cookie': cookie,
            'User-Agent': _ua,
            'Accept-Language': 'en-US,en;q=0.9',
          },
        ),
      );

      final status = response.statusCode ?? 0;
      // Redirect to Google sign-in means the session is invalid.
      if (status == 302 || status == 303 || status == 401) {
        _isLoggedIn = false;
        _currentUser = null;
        return false;
      }
      if (status != 200) {
        _logger.warning('YouTube account check returned $status');
        _isLoggedIn = false;
        _currentUser = null;
        return false;
      }

      final body = response.data?.toString() ?? '';
      // Extract channel id and display name from the account page.
      String? channelId;
      final channelMatch = RegExp(r'"channelId":"(UC[\w-]+)"').firstMatch(body);
      if (channelMatch != null) {
        channelId = channelMatch.group(1);
      }

      String name = 'YouTube User';
      final nameMatch = RegExp(r'"displayName":"([^"]+)"').firstMatch(body);
      if (nameMatch != null) {
        name = _unescapeJson(nameMatch.group(1)!);
      }

      _isLoggedIn = true;
      _currentUser = AccountInfo(name: name, id: channelId, cookie: _cookie);
      _logger.info('Logged in to YouTube as $name');
      return true;
    } catch (e) {
      // Network error does not mean the session is dead. Keep it
      // optimistically so a flaky network at startup does not wipe the
      // persisted login.
      _logger.warning(
        'YouTube cookie validation network error, keeping session: $e',
      );
      _isLoggedIn = true;
      _currentUser ??= AccountInfo(
        name: 'YouTube User',
        id: null,
        cookie: _cookie,
      );
      return true;
    }
  }

  static String _unescapeJson(String s) {
    try {
      return jsonDecode('"$s"') as String;
    } catch (_) {
      return s;
    }
  }

  @override
  Future<void> loginWithQrCode(BuildContext context) async {
    // YouTube uses OAuth device code flow, not QR scan.
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('YouTube Login'),
        content: const Text(
          'Please use "Login with browser" or "Login with cookie" instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> loginWithWeb(BuildContext context) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const WebLoginPage(
          initialUrl:
              'https://accounts.google.com/ServiceLogin?service=youtube',
          sourceName: 'YouTube',
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      await loginWithCookie(result);
    }
  }

  @override
  Future<void> logout() async {
    _logger.info('YouTube logout: user=${_currentUser?.name}');
    _isLoggedIn = false;
    _currentUser = null;
    _cookie = null;
  }

  @override
  Future<void> checkLoginStatus() async {
    if (_cookie == null) {
      _isLoggedIn = false;
      _currentUser = null;
      return;
    }
    await _validateAndFetchUser();
  }
}
