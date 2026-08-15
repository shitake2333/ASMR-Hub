import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:asmr_hub/models/account_info.dart';
import 'package:asmr_hub/models/base_auth_data.dart';
import 'package:asmr_hub/pages/web_login_page.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/sources/base/source_auth.dart';

/// DLSite session data (cookie based)
class DLSiteAuthData extends BaseAuthData {
  final Map<String, String> cookies;

  DLSiteAuthData(this.cookies);

  String get cookie =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  @override
  Map<String, dynamic> toJson() => {'cookies': cookies};

  factory DLSiteAuthData.fromJson(Map<String, dynamic> json) {
    final raw = json['cookies'] as Map<String, dynamic>? ?? {};
    return DLSiteAuthData(raw.map((k, v) => MapEntry(k, v.toString())));
  }

  factory DLSiteAuthData.fromCookieString(String cookieStr) {
    final cookies = <String, String>{};
    for (final part in cookieStr.split(';')) {
      final idx = part.indexOf('=');
      if (idx > 0) {
        cookies[part.substring(0, idx).trim()] = part.substring(idx + 1).trim();
      }
    }
    return DLSiteAuthData(cookies);
  }
}

/// DLSite authentication.
///
/// Supports username/password login (form POST to login.dlsite.com/login)
/// as well as cookie login. Session validity is checked against the mypage.
class DLSiteAuth extends SourceAuth {
  /// Global instance shared by the source and the scraper, so DLsite
  /// requests automatically carry the session cookie (purchased content).
  static final DLSiteAuth instance = DLSiteAuth._();

  DLSiteAuth._() : super('https://www.dlsite.com');

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
  bool get supportsCredentialsLogin => true;

  bool _isLoggedIn = false;
  AccountInfo? _currentUser;
  DLSiteAuthData? _authData;
  final Map<String, String> _tempJar = {};

  @override
  bool get isLoggedIn => _isLoggedIn;

  @override
  AccountInfo? get currentUser => _currentUser;

  /// HTTP Cookie header form ("k=v; k=v") for live requests.
  @override
  String? get cookie => _authData?.cookie;

  /// Merge Set-Cookie headers into the cookie jar.
  void _mergeSetCookies(Headers headers, Map<String, String> jar) {
    final values = headers['set-cookie'] ?? const [];
    for (final raw in values) {
      for (final part in raw.split(',')) {
        final idx = part.indexOf('=');
        if (idx <= 0) continue;
        final key = part.substring(0, idx).trim();
        var value = part.substring(idx + 1);
        final semi = value.indexOf(';');
        if (semi >= 0) value = value.substring(0, semi);
        jar[key] = value;
      }
    }
  }

  String _cookieHeader(Map<String, String> jar) =>
      jar.entries.map((e) => '${e.key}=${e.value}').join('; ');

  @override
  Future<void> loginWithCredentials(String username, String password) async {
    _tempJar.clear();
    try {
      // 1. Fetch the login page to obtain the CSRF token.
      final pageResp = await clientSession.get<dynamic>(
        'https://login.dlsite.com/login',
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
          headers: {'User-Agent': _ua},
        ),
      );
      final pageBody = pageResp.data?.toString() ?? '';
      final tokenMatch = RegExp(
        r'<input[^>]*name="_token"[^>]*value="([^"]+)"',
      ).firstMatch(pageBody);
      if (tokenMatch == null) {
        _logger.error('Failed to get DLSite login token');
        return;
      }
      final token = tokenMatch.group(1)!;
      _mergeSetCookies(pageResp.headers, _tempJar);

      // 2. POST credentials.
      final loginResp = await clientSession.post<dynamic>(
        'https://login.dlsite.com/login',
        data: {
          '_token': token,
          'login_id': username,
          'password': password,
          'remember': '1',
        },
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'User-Agent': _ua,
            'Cookie': _cookieHeader(_tempJar),
            'Referer': 'https://login.dlsite.com/login',
          },
        ),
      );
      _mergeSetCookies(loginResp.headers, _tempJar);

      // 3. Check the result: success redirects to dlsite.com (2xx/3xx with
      //    login cookies), failure returns the login page again.
      final loginOk =
          _tempJar.containsKey('login_secure_id') ||
          _tempJar.containsKey('adult_auth') ||
          _tempJar.containsKey('ckcy') ||
          (loginResp.statusCode == 302 ||
              (loginResp.statusCode != null && loginResp.statusCode! < 300));

      if (loginOk) {
        _authData = DLSiteAuthData(Map.of(_tempJar));
        final ok = await _validateAndFetchUser();
        if (!ok) {
          // Accept the session anyway; user info could not be resolved.
          _isLoggedIn = true;
          _currentUser = AccountInfo(
            name: 'DLSite User',
            cookie: _authData!.serialize(),
          );
        }
        _logger.info('Logged in to DLSite as ${_currentUser?.name}');
      } else {
        _logger.warning('DLSite login failed: invalid credentials');
        _isLoggedIn = false;
        _currentUser = null;
      }
    } catch (e) {
      _logger.error('Error logging in to DLSite: $e');
      _isLoggedIn = false;
      _currentUser = null;
      rethrow;
    }
  }

  @override
  Future<void> loginWithCookie(String cookieStr) async {
    // Persisted sessions are stored as `serialize()` output (JSON). Legacy
    // cookie strings ("k=v; k=v") are also accepted.
    DLSiteAuthData? data;
    try {
      final decoded = jsonDecode(cookieStr);
      if (decoded is Map<String, dynamic>) {
        data = DLSiteAuthData.fromJson(decoded);
      }
    } catch (_) {
      // not JSON: raw cookie string
    }
    _authData = data ?? DLSiteAuthData.fromCookieString(cookieStr);
    final ok = await _validateAndFetchUser();
    if (!ok) {
      _isLoggedIn = false;
      _currentUser = null;
      _logger.warning('DLSite cookie validation failed');
    }
  }

  /// Validate the session against mypage and fetch the user name.
  Future<bool> _validateAndFetchUser() async {
    final data = _authData;
    if (data == null) return false;

    try {
      final response = await clientSession.get<dynamic>(
        'https://www.dlsite.com/home/mypage',
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
          headers: {'User-Agent': _ua, 'Cookie': data.cookie},
        ),
      );
      final status = response.statusCode ?? 0;
      if (status == 302 || status == 303 || status == 401) {
        return false;
      }
      if (status != 200) return false;

      final body = response.data?.toString() ?? '';
      // Extract the user name from the mypage greeting.
      String name = 'DLSite User';
      final nameMatch = RegExp(r'ようこそ、(.+?)さん').firstMatch(body);
      if (nameMatch != null) {
        name = nameMatch.group(1)!;
      } else {
        final altMatch = RegExp(r'"user_name":"([^"]+)"').firstMatch(body);
        if (altMatch != null) name = altMatch.group(1)!;
      }

      _isLoggedIn = true;
      _currentUser = AccountInfo(
        name: name,
        id: data.cookies['login_secure_id'],
        cookie: data.serialize(),
      );
      return true;
    } catch (e) {
      // Network error does not mean the session is dead. Keep it
      // optimistically so a flaky network at startup does not wipe the
      // persisted login.
      _logger.warning(
        'DLSite cookie validation network error, keeping session: $e',
      );
      _isLoggedIn = true;
      _currentUser ??= AccountInfo(
        name: 'DLSite User',
        id: _authData?.cookies['login_secure_id'],
        cookie: _authData?.serialize(),
      );
      return true;
    }
  }

  @override
  Future<void> loginWithQrCode(BuildContext context) async {
    // Not supported.
  }

  @override
  Future<void> loginWithWeb(BuildContext context) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const WebLoginPage(
          initialUrl: 'https://login.dlsite.com/login',
          sourceName: 'DLSite',
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      await loginWithCookie(result);
    }
  }

  @override
  Future<void> logout() async {
    _logger.info('DLSite logout: user=${_currentUser?.name}');
    _isLoggedIn = false;
    _currentUser = null;
    _authData = null;
  }

  @override
  Future<void> checkLoginStatus() async {
    if (_authData == null) {
      _isLoggedIn = false;
      _currentUser = null;
      return;
    }
    await _validateAndFetchUser();
  }
}
