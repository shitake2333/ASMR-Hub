import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import 'package:asmr_hub/l10n/app_localizations.dart';
import 'package:asmr_hub/models/account_info.dart';
import 'package:asmr_hub/models/base_auth_data.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/sources/base/source_auth.dart';

/// Douyu login credentials (cookie based)
class DouyuAuthData extends BaseAuthData {
  final Map<String, String> cookies;

  DouyuAuthData(this.cookies);

  String get cookie =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  @override
  Map<String, dynamic> toJson() => {'cookies': cookies};

  factory DouyuAuthData.fromJson(Map<String, dynamic> json) {
    final raw = json['cookies'] as Map<String, dynamic>? ?? {};
    return DouyuAuthData(raw.map((k, v) => MapEntry(k, v.toString())));
  }

  factory DouyuAuthData.fromCookieString(String cookieStr) {
    final cookies = <String, String>{};
    for (final part in cookieStr.split(';')) {
      final idx = part.indexOf('=');
      if (idx > 0) {
        cookies[part.substring(0, idx).trim()] = part.substring(idx + 1).trim();
      }
    }
    return DouyuAuthData(cookies);
  }
}

/// Douyu (斗鱼) authentication via QR scan login.
/// Protocol reference: https://github.com/CharlesPikachu/DecryptLogin
class DouyuAuth extends SourceAuth {
  /// Global instance shared by the source and the scraper, so requests made
  /// by the scraper automatically carry the login cookie.
  static final DouyuAuth instance = DouyuAuth._();

  DouyuAuth._() : super('https://passport.douyu.com');

  final LogService _logger = LogService();

  bool _isLoggedIn = false;
  AccountInfo? _currentUser;
  DouyuAuthData? _authData;

  @override
  bool get requiresAuth => true;

  @override
  bool get supportsQrCodeLogin => true;

  @override
  bool get supportsWebLogin => false;

  @override
  bool get supportsCookieLogin => true;

  @override
  bool get supportsCredentialsLogin => false;

  @override
  Future<void> loginWithCredentials(String username, String password) async {
    throw UnsupportedError('Douyu does not support username/password login');
  }

  @override
  Future<void> loginWithWeb(BuildContext context) async {
    throw UnsupportedError('Douyu web login is not supported');
  }

  @override
  bool get isLoggedIn => _isLoggedIn;

  @override
  AccountInfo? get currentUser => _currentUser;

  /// HTTP Cookie header form ("k=v; k=v") for live requests. Persisted
  /// sessions keep the JSON form in AccountInfo.cookie.
  @override
  String? get cookie => _authData?.cookie;

  @override
  Future<void> loginWithCookie(String cookieStr) async {
    // Persisted sessions are stored as `serialize()` output (JSON). Legacy
    // cookie strings ("k=v; k=v") are also accepted.
    DouyuAuthData? data;
    try {
      final decoded = jsonDecode(cookieStr);
      if (decoded is Map<String, dynamic>) {
        data = DouyuAuthData.fromJson(decoded);
      }
    } catch (_) {
      // not JSON: raw cookie string
    }
    _authData = data ?? DouyuAuthData.fromCookieString(cookieStr);
    final ok = await _validateAndFetchUser();
    if (ok) {
      _logger.info('Logged in to Douyu as ${_currentUser?.name}');
    } else {
      _logger.warning('Douyu cookie validation failed');
      _isLoggedIn = false;
      _currentUser = null;
    }
  }

  @override
  Future<void> loginWithQrCode(BuildContext context) async {
    _logger.info('Douyu QR login: dialog opened');
    final result = await showDialog<DouyuAuthData>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const DouyuQrLoginDialog(),
    );
    if (result == null) {
      _logger.info('Douyu QR login: canceled by user');
      return;
    }
    _authData = result;
    _logger.info('Douyu QR login: scanned, proceeding');
    final ok = await _validateAndFetchUser();
    if (ok) {
      _logger.info('Douyu QR login: SUCCESS user=${_currentUser?.name}');
    } else {
      // Login state accepted but user info fetch failed; keep logged in.
      _isLoggedIn = true;
      _currentUser ??= AccountInfo(
        name: 'Douyu User',
        id: _authData?.cookies['dy_authid'],
        cookie: _authData?.serialize(),
      );
      _logger.warning(
        'Douyu QR login: session accepted but user info fetch failed; '
        'fallback user=${_currentUser?.name}',
      );
    }
  }

  /// Validate the stored cookie against douyu.com and fetch user name.
  Future<bool> _validateAndFetchUser() async {
    final data = _authData;
    if (data == null) {
      _logger.warning('Douyu validate: no auth data');
      return false;
    }

    // Modern Douyu issues LTP0 as the passport session token. The member
    // page is an SPA that redirects, so follow redirects manually while
    // keeping the cookie, then parse the display name out of the markup.
    final hasAuthCookie =
        data.cookies.containsKey('LTP0') ||
        data.cookies.containsKey('acf_auth') ||
        data.cookies.containsKey('dy_authid') ||
        data.cookies.containsKey('acf_uid');
    if (!hasAuthCookie) {
      _logger.warning('Douyu validate: no auth cookie present');
      return false;
    }

    final result = await _fetchMemberName(data);
    if (result.$1) {
      // Name resolved (or network kept the session): logged in. Persist any
      // fresh session cookies (acf_uid/acf_nickname/acf_avatar/...) that the
      // redirect chain issued — they carry uid, name and avatar.
      if (result.$4 != null) {
        final merged = Map<String, String>.from(data.cookies)
          ..addAll(result.$4!);
        _authData = DouyuAuthData(merged);
        _logger.info('Douyu validate: session cookies refreshed');
      }
      _isLoggedIn = true;
      final cookies = _authData!.cookies;
      final avatar = _resolveAvatar(cookies['acf_avatar']);
      _currentUser = AccountInfo(
        name: result.$2 ?? cookies['acf_nickname'] ?? 'Douyu User',
        id: cookies['acf_uid'] ?? cookies['dy_authid'],
        avatarUrl: avatar,
        cookie: _authData!.serialize(),
      );
      final avatarDesc = avatar == null ? 'none' : 'set';
      _logger.info(
        'Douyu validate: OK user=${_currentUser?.name} '
        'uid=${_currentUser?.id} avatar=$avatarDesc',
      );
      return true;
    }
    if (result.$3) {
      // Network error: keep the session optimistically; the name will be
      // resolved on a later check.
      _isLoggedIn = true;
      _currentUser ??= AccountInfo(
        name: 'Douyu User',
        id: data.cookies['dy_authid'] ?? data.cookies['acf_uid'],
        avatarUrl: null,
        cookie: data.serialize(),
      );
      _logger.warning(
        'Douyu validate: network error, keeping session '
        'user=${_currentUser?.name}',
      );
      return true;
    }
    // The member page redirected to the sign-in page: the session is
    // actually expired even though an auth cookie is present.
    _isLoggedIn = false;
    _currentUser = null;
    _logger.warning(
      'Douyu validate: session expired (member page redirected to login)',
    );
    return false;
  }

  /// Decodes the `acf_avatar` cookie and rejects values that are truncated
  /// (Douyu truncates the default-avatar cookie to ".../default/11_"), so a
  /// broken URL never reaches the UI.
  String? _resolveAvatar(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    String decoded;
    try {
      decoded = Uri.decodeComponent(raw);
    } catch (_) {
      decoded = raw;
    }
    // Truncated default avatar (".../default/11_", no extension) is not a
    // usable URL.
    if (decoded.endsWith('11_') ||
        decoded.endsWith('/default/') ||
        !RegExp(
          r'\.(jpg|jpeg|png|webp|gif)($|\?)',
          caseSensitive: false,
        ).hasMatch(decoded)) {
      _logger.info('Douyu avatar cookie unusable, ignoring');
      return null;
    }
    return decoded;
  }

  /// Follows the member-page redirect chain (keeping the cookie) and returns
  /// `(resolved, name, networkError, newCookies)`. `resolved` is true when
  /// the session was validated (name may still be null); `networkError` is
  /// true when the check could not complete due to a network problem;
  /// `newCookies` holds any cookies issued along the chain.
  Future<(bool, String?, bool, Map<String, String>?)> _fetchMemberName(
    DouyuAuthData data,
  ) async {
    final dio = Dio(
      BaseOptions(
        // Do NOT auto-follow redirects: the cookie must be preserved and
        // accumulated across each hop, which dio's auto-redirect drops.
        followRedirects: false,
        validateStatus: (s) => s != null && s < 500,
        headers: {'User-Agent': _ua, 'Accept-Language': 'zh-CN,zh;q=0.9'},
      ),
    );
    final cookies = Map<String, String>.from(data.cookies);
    String cookieStr() =>
        cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    String resolve(String base, String loc) {
      if (loc.startsWith('http')) return loc;
      if (loc.startsWith('//')) return 'https:$loc';
      final u = Uri.parse(base);
      return '${u.scheme}://${u.host}$loc';
    }

    try {
      var url = 'https://www.douyu.com/member';
      var newCookies = <String, String>{};
      for (var i = 0; i < 8; i++) {
        final Response<dynamic> resp;
        try {
          resp = await dio.get<dynamic>(
            url,
            options: Options(headers: {'Cookie': cookieStr()}),
          );
        } catch (e) {
          return (true, null, true, null);
        }
        // Merge Set-Cookie headers from this hop (passport issues session
        // cookies along the redirect chain that make the final page work).
        final sc = resp.headers['set-cookie'] ?? const [];
        for (final raw in sc) {
          for (final part in raw.split(RegExp(r',(?=[^,]*=)'))) {
            final eq = part.indexOf('=');
            if (eq <= 0) continue;
            final k = part.substring(0, eq).trim();
            if (k.isEmpty || k.contains(' ')) continue;
            if (RegExp(
              r'^(Expires|Path|Domain|Max-Age|SameSite|Secure|HttpOnly|Version)$',
              caseSensitive: false,
            ).hasMatch(k)) {
              continue;
            }
            var v = part.substring(eq + 1);
            final semi = v.indexOf(';');
            if (semi >= 0) v = v.substring(0, semi);
            cookies[k] = v;
            newCookies[k] = v;
          }
        }
        final status = resp.statusCode ?? 0;
        if (status >= 300 && status < 400) {
          final loc = resp.headers.value('location');
          if (loc == null || loc.isEmpty) {
            return (false, null, false, newCookies);
          }
          url = resolve(url, loc);
          continue;
        }
        if (status == 200) {
          final body = resp.data?.toString() ?? '';
          final nameMatch = RegExp(
            r'uname_con clearfix" title="(.*?)"',
          ).firstMatch(body);
          if (nameMatch != null) {
            return (true, nameMatch.group(1), false, newCookies);
          }
          // Logged-out requests are served the single sign-on page.
          if (body.contains('单点登录') || body.contains('passport.douyu.com')) {
            return (false, null, false, newCookies);
          }
          return (true, null, false, newCookies);
        }
        return (false, null, false, newCookies);
      }
      // Too many redirects: treat as network-level failure.
      return (true, null, true, newCookies);
    } finally {
      dio.close();
    }
  }

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  @override
  Future<void> checkLoginStatus() async {
    if (_authData == null) {
      _isLoggedIn = false;
      _currentUser = null;
      _logger.info('Douyu checkLoginStatus: no auth data');
      return;
    }
    final ok = await _validateAndFetchUser();
    _logger.info(
      'Douyu checkLoginStatus: ${ok ? 'valid' : 'invalid'} '
      'user=${_currentUser?.name}',
    );
  }

  @override
  Future<void> logout() async {
    _logger.info('Douyu logout: user=${_currentUser?.name}');
    _isLoggedIn = false;
    _currentUser = null;
    _authData = null;
  }
}

/// QR code login dialog following Douyu's passport flow.
class DouyuQrLoginDialog extends StatefulWidget {
  const DouyuQrLoginDialog({super.key});

  @override
  State<DouyuQrLoginDialog> createState() => _DouyuQrLoginDialogState();
}

class _DouyuQrLoginDialogState extends State<DouyuQrLoginDialog> {
  final Map<String, String> _cookies = {};
  final http.Client _client = http.Client();

  String? _qrUrl;
  String? _qrCode;
  String _statusText = '';
  bool _isExpired = false;
  bool _isSuccess = false;
  Timer? _pollTimer;

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  @override
  void initState() {
    super.initState();
    _loadQrCode();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _client.close();
    super.dispose();
  }

  void _mergeSetCookie(http.Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null) return;
    // set-cookie headers can contain multiple cookies separated by commas,
    // but Expires dates also contain commas. Split and skip attribute parts
    // (Expires/Path/Domain/Max-Age/...) instead of parsing them as cookies.
    final parts = raw.split(RegExp(r',(?=[^,]*=)'));
    for (var part in parts) {
      part = part.trim();
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      final key = part.substring(0, idx).trim();
      if (key.isEmpty || key.contains(' ')) continue;
      if (RegExp(
        r'^(Expires|expires|Path|path|Domain|Max-Age|SameSite|Secure|HttpOnly|Version)$',
      ).hasMatch(key)) {
        continue;
      }
      var value = part.substring(idx + 1);
      final semi = value.indexOf(';');
      if (semi >= 0) value = value.substring(0, semi);
      _cookies[key] = value;
    }
  }

  String get _cookieHeader =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  Future<void> _loadQrCode() async {
    setState(() {
      _isExpired = false;
      _isSuccess = false;
      _statusText = 'Loading QR Code...';
    });
    try {
      final response = await _client.post(
        Uri.parse('https://passport.douyu.com/scan/generateCode'),
        headers: {
          'User-Agent': _ua,
          'Referer':
              'https://passport.douyu.com/index/login?type=login&client_id=1',
        },
        body: {'client_id': '1'},
      );
      _mergeSetCookie(response);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['error'] == 0) {
        final payload = data['data'] as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _qrUrl = payload['url'].toString().replaceAll('\\', '');
            _qrCode = payload['code'].toString();
            _statusText = AppLocalizations.of(context)!.scanWithDouyuApp;
          });
          _startPolling();
        }
      } else {
        if (mounted) {
          setState(() => _statusText = 'Failed to load QR code');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusText = 'Error: $e');
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_qrCode == null || !mounted) return;
      try {
        final time = DateTime.now().millisecondsSinceEpoch;
        final response = await _client.get(
          Uri.parse(
            'https://passport.douyu.com/lapi/passport/qrcode/check'
            '?time=$time&code=$_qrCode',
          ),
          headers: {
            'User-Agent': _ua,
            // Douyu rejects the check without the correct referer
            // (error -3, referer mismatch). An empty Cookie header also
            // triggers it, so only send the cookie when set.
            'Referer': 'https://passport.douyu.com/',
            if (_cookieHeader.isNotEmpty) 'Cookie': _cookieHeader,
          },
        );
        _mergeSetCookie(response);
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (!mounted) return;

        final error = data['error'];
        if (error == 0) {
          // Scanned & confirmed: follow the login URL to finish the session.
          timer.cancel();
          setState(() {
            _isSuccess = true;
            _statusText = 'Login Successful';
          });
          // The data shape varies: {"url": "..."} or a bare URL string.
          final d = data['data'];
          String? loginPath;
          if (d is Map<String, dynamic>) {
            loginPath = d['url']?.toString();
          } else if (d is String && d.isNotEmpty) {
            loginPath = d;
          }
          if (loginPath == null || loginPath.isEmpty) {
            // No follow-up URL: the session cookies may already be set.
            if (_cookies.isNotEmpty) {
              Navigator.of(context).pop(DouyuAuthData(Map.of(_cookies)));
              return;
            }
            if (mounted) {
              setState(() => _statusText = 'Login response missing url');
            }
            return;
          }
          final loginUrl = loginPath.startsWith('http')
              ? loginPath
              : 'https:$loginPath';
          try {
            final loginResp = await _client.get(
              Uri.parse(
                '$loginUrl?callback=appClient_json_callback&_='
                '${DateTime.now().millisecondsSinceEpoch}',
              ),
              headers: {'User-Agent': _ua, 'Cookie': _cookieHeader},
            );
            _mergeSetCookie(loginResp);
            final body = loginResp.body.trim();
            if (body.startsWith('appClient_json_callback(')) {
              final payload =
                  jsonDecode(
                        body.substring(
                          'appClient_json_callback('.length,
                          body.length - 1,
                        ),
                      )
                      as Map<String, dynamic>;
              if (payload['error'] != 0) {
                if (mounted) {
                  setState(
                    () => _statusText =
                        payload['msg']?.toString() ?? 'Login failed',
                  );
                }
                return;
              }
            }
          } catch (e) {
            if (mounted) {
              setState(() => _statusText = 'Login confirm error: $e');
            }
            return;
          }
          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) {
            Navigator.of(context).pop(DouyuAuthData(Map.of(_cookies)));
          }
        } else if (error == -1) {
          // Expired
          timer.cancel();
          setState(() {
            _isExpired = true;
            _statusText = 'QR Code Expired';
          });
        } else if (error == 1) {
          // Scanned, waiting for confirmation
          setState(() => _statusText = 'Scanned, please confirm on phone');
        } else if (error == -2) {
          // Not scanned yet
          setState(
            () => _statusText = AppLocalizations.of(context)!.scanWithDouyuApp,
          );
        } else {
          // Other errors
        }
      } catch (e) {
        if (mounted) {
          setState(() => _statusText = 'Poll error: $e');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Douyu QR Login'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_qrUrl != null && !_isExpired && !_isSuccess)
            SizedBox(
              width: 200,
              height: 200,
              child: QrImageView(
                data: _qrUrl!,
                version: QrVersions.auto,
                size: 200.0,
              ),
            )
          else if (_isExpired)
            Column(
              children: [
                const Icon(Icons.refresh, size: 64, color: Colors.orange),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loadQrCode,
                  child: const Text('Refresh'),
                ),
              ],
            )
          else if (_isSuccess)
            const Icon(Icons.check_circle, size: 64, color: Colors.green)
          else
            const SizedBox(
              width: 200,
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 16),
          Text(_statusText, textAlign: TextAlign.center),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
      ],
    );
  }
}
