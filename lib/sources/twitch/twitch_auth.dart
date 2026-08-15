import 'package:flutter/material.dart';

import 'package:asmr_hub/models/account_info.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/sources/base/source_auth.dart';

/// Twitch authentication.
///
/// Twitch's public playback API works anonymously for public channels
/// (audio-only), so login is optional. A session cookie can be provided for
/// better availability, but the anonymous path is the default.
class TwitchAuth extends SourceAuth {
  final LogService _logger = LogService();

  bool _isLoggedIn = false;
  AccountInfo? _currentUser;
  String? _cookie;

  TwitchAuth() : super('https://www.twitch.tv');

  @override
  bool get requiresAuth => false;

  @override
  bool get supportsQrCodeLogin => false;

  @override
  bool get supportsWebLogin => false;

  @override
  bool get supportsCookieLogin => true;

  @override
  bool get supportsCredentialsLogin => false;

  @override
  Future<void> loginWithCredentials(String username, String password) async {
    throw UnsupportedError('Twitch does not support username/password login');
  }

  @override
  bool get isLoggedIn => _isLoggedIn;

  @override
  AccountInfo? get currentUser => _currentUser;

  @override
  String? get cookie => _cookie;

  @override
  Future<void> loginWithCookie(String cookie) async {
    _cookie = cookie;
    _isLoggedIn = true;
    _currentUser = AccountInfo(name: 'Twitch User', cookie: cookie);
    _logger.info('Twitch login with cookie accepted');
  }

  @override
  Future<void> loginWithQrCode(BuildContext context) async {
    // Not supported.
  }

  @override
  Future<void> loginWithWeb(BuildContext context) async {
    // Web login is not offered (supportsWebLogin=false); anonymous playback
    // covers public channels.
  }

  @override
  Future<void> logout() async {
    _logger.info('Twitch logout: user=${_currentUser?.name}');
    _isLoggedIn = false;
    _currentUser = null;
    _cookie = null;
  }

  @override
  Future<void> checkLoginStatus() async {
    // Anonymous playback always available; nothing to verify.
    _isLoggedIn = _cookie != null;
    _currentUser = _cookie == null ? null : _currentUser;
  }
}
