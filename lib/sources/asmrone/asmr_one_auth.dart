import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:asmr_hub/models/account_info.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/sources/base/source_auth.dart';

/// asmr.one authentication (JWT token based).
///
/// Login: `POST api.asmr-200.com/api/auth/me` with {name, password}.
/// Register: `POST api/auth/reg` with {name, password} (free, no email).
/// The JWT is stored as the source cookie for persistence.
class AsmrOneAuth extends SourceAuth {
  static final AsmrOneAuth instance = AsmrOneAuth._();

  AsmrOneAuth._() : super('https://api.asmr-200.com');

  static const String _api = 'https://api.asmr-200.com/api';

  final LogService _logger = LogService();
  bool _isLoggedIn = false;
  AccountInfo? _currentUser;
  String? _token;

  @override
  bool get requiresAuth => true; // playlists require a logged-in account

  @override
  bool get supportsQrCodeLogin => false;

  @override
  bool get supportsWebLogin => false;

  @override
  bool get supportsCookieLogin => true;

  @override
  bool get supportsCredentialsLogin => true;

  @override
  bool get isLoggedIn => _isLoggedIn;

  @override
  AccountInfo? get currentUser => _currentUser;

  /// JWT bearer token, or null when logged out.
  @override
  String? get cookie => _token;

  Map<String, String> get headers => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    if (_token != null && _token!.isNotEmpty) 'Authorization': 'Bearer $_token',
  };

  @override
  Future<void> loginWithCredentials(String username, String password) async {
    // asmr.one login is POST /api/auth/me with {name, password}.
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$_api/auth/me'),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Content-Type': 'application/json',
              'Origin': 'https://asmr.one',
              'Referer': 'https://asmr.one/',
            },
            body: jsonEncode({'name': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      _logger.warning('asmr.one login network error: $e');
      _isLoggedIn = false;
      _currentUser = null;
      return;
    }
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _token = json['token']?.toString();
      _isLoggedIn = _token != null && _token!.isNotEmpty;
      final user = json['user'] as Map<String, dynamic>? ?? const {};
      _currentUser = AccountInfo(
        name: user['name']?.toString() ?? username,
        id: user['id']?.toString(),
        cookie: _token,
      );
      if (_isLoggedIn) {
        _logger.info('Logged in to asmr.one as ${_currentUser?.name}');
      }
    } else {
      _logger.warning('asmr.one login failed: ${response.statusCode}');
      _isLoggedIn = false;
      _currentUser = null;
    }
  }

  /// Registers a new account (free). Returns true on success.
  Future<bool> register(String username, String password) async {
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$_api/auth/reg'),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Content-Type': 'application/json',
              'Origin': 'https://asmr.one',
              'Referer': 'https://asmr.one/',
            },
            body: jsonEncode({'name': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      _logger.warning('asmr.one register network error: $e');
      return false;
    }
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _token = json['token']?.toString();
      _isLoggedIn = _token != null && _token!.isNotEmpty;
      final user = json['user'] as Map<String, dynamic>? ?? const {};
      _currentUser = AccountInfo(
        name: user['name']?.toString() ?? username,
        id: user['id']?.toString(),
        cookie: _token,
      );
      _logger.info('Registered asmr.one account ${_currentUser?.name}');
      return true;
    }
    _logger.warning('asmr.one register failed: ${response.statusCode}');
    return false;
  }

  @override
  Future<void> loginWithCookie(String token) async {
    _token = token;
    if (token.isEmpty) {
      _isLoggedIn = false;
      _currentUser = null;
      return;
    }
    // Verify the token by fetching the current user.
    try {
      final response = await http.get(
        Uri.parse('$_api/auth/me'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final user = json['user'] as Map<String, dynamic>? ?? const {};
        _isLoggedIn = true;
        _currentUser = AccountInfo(
          name: user['name']?.toString() ?? 'asmr.one User',
          id: user['id']?.toString(),
          cookie: token,
        );
        _logger.info('Restored asmr.one session for ${_currentUser?.name}');
      } else {
        _isLoggedIn = false;
        _currentUser = null;
        _logger.warning('asmr.one token invalid (${response.statusCode})');
      }
    } catch (e) {
      // Network error (timeout/DNS) does not mean the token is invalid.
      // Keep the session optimistically so a flaky network at startup does
      // not wipe the persisted login.
      _logger.warning(
        'asmr.one token validation network error, keeping session: $e',
      );
      _isLoggedIn = true;
      _currentUser ??= AccountInfo(
        name: 'asmr.one User',
        id: null,
        cookie: token,
      );
    }
  }

  @override
  Future<void> loginWithQrCode(BuildContext context) async {
    throw UnsupportedError('asmr.one does not support QR login');
  }

  @override
  Future<void> loginWithWeb(BuildContext context) async {
    throw UnsupportedError('asmr.one does not support web login');
  }

  @override
  Future<void> checkLoginStatus() async {
    if (_token == null) return;
    await loginWithCookie(_token!);
  }

  @override
  Future<void> logout() async {
    _logger.info('asmr.one logout: user=${_currentUser?.name}');
    _isLoggedIn = false;
    _currentUser = null;
    _token = null;
  }
}
