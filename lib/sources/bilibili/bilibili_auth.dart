import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart' hide State;
import 'package:qr_flutter/qr_flutter.dart';

import 'package:asmr_hub/l10n/app_localizations.dart';
import 'package:asmr_hub/models/account_info.dart';
import 'package:asmr_hub/models/base_auth_data.dart';
import 'package:asmr_hub/pages/web_login_page.dart';
import 'package:asmr_hub/services/log_service.dart';
import 'package:asmr_hub/sources/base/source_auth.dart';

class BilibiliAuthData extends BaseAuthData {
  final String sessData;
  final String biliJct;
  final String dedeUserId;
  final String dedeUserIdCkMd5;
  final String sid;
  final String? refreshToken;

  BilibiliAuthData({
    required this.sessData,
    required this.biliJct,
    required this.dedeUserId,
    required this.dedeUserIdCkMd5,
    required this.sid,
    this.refreshToken,
  });

  String get cookie =>
      'SESSDATA=$sessData; bili_jct=$biliJct; DedeUserID=$dedeUserId; DedeUserID__ckMd5=$dedeUserIdCkMd5; sid=$sid';

  @override
  Map<String, dynamic> toJson() => {
    'SESSDATA': sessData,
    'bili_jct': biliJct,
    'DedeUserID': dedeUserId,
    'DedeUserID__ckMd5': dedeUserIdCkMd5,
    'sid': sid,
    'refresh_token': refreshToken,
  };

  factory BilibiliAuthData.fromJson(Map<String, dynamic> json) {
    return BilibiliAuthData(
      sessData: json['SESSDATA'] as String? ?? '',
      biliJct: json['bili_jct'] as String? ?? '',
      dedeUserId: json['DedeUserID'] as String? ?? '',
      dedeUserIdCkMd5: json['DedeUserID__ckMd5'] as String? ?? '',
      sid: json['sid'] as String? ?? '',
      refreshToken: json['refresh_token'] as String?,
    );
  }

  factory BilibiliAuthData.fromCookieString(
    String cookieStr, {
    String? refreshToken,
  }) {
    final cookies = parseCookieString(cookieStr);
    return BilibiliAuthData(
      sessData: cookies['SESSDATA'] ?? '',
      biliJct: cookies['bili_jct'] ?? '',
      dedeUserId: cookies['DedeUserID'] ?? '',
      dedeUserIdCkMd5: cookies['DedeUserID__ckMd5'] ?? '',
      sid: cookies['sid'] ?? '',
      refreshToken: refreshToken,
    );
  }

  static Map<String, String> parseCookieString(String cookieStr) {
    final Map<String, String> cookies = {};
    final keys = [
      'SESSDATA',
      'bili_jct',
      'DedeUserID',
      'DedeUserID__ckMd5',
      'sid',
    ];
    for (final key in keys) {
      final RegExp regex = RegExp('$key=([^;]+)');
      final Match? match = regex.firstMatch(cookieStr);
      if (match != null) {
        cookies[key] = match.group(1)!;
      }
    }
    return cookies;
  }
}

class BilibiliAuth extends SourceAuth {
  /// Global instance shared by the source, the API client and the scraper,
  /// so every Bilibili request automatically carries the login cookie
  /// (higher audio quality, charged content, etc.).
  static final BilibiliAuth instance = BilibiliAuth._();

  BilibiliAuth._() : super('https://api.bilibili.com');

  @override
  bool get requiresAuth => true;

  @override
  bool get supportsQrCodeLogin => true;

  @override
  bool get supportsWebLogin => true;

  @override
  bool get supportsCookieLogin => true;

  @override
  bool get supportsCredentialsLogin => false;

  @override
  Future<void> loginWithCredentials(String username, String password) async {
    throw UnsupportedError('Bilibili does not support username/password login');
  }

  bool _isLoggedIn = false;
  AccountInfo? _currentUser;
  BilibiliAuthData? _authData;

  @override
  bool get isLoggedIn => _isLoggedIn;

  @override
  AccountInfo? get currentUser => _currentUser;

  /// HTTP Cookie header form ("SESSDATA=...; bili_jct=...") for live
  /// requests. Persisted sessions keep the JSON form in AccountInfo.cookie.
  @override
  String? get cookie => _authData?.cookie;

  @override
  Future<void> loginWithCookie(String cookieStr) async {
    LogService().info('Logging in to Bilibili...');

    // Try to parse as JSON first
    try {
      final Map<String, dynamic> json = jsonDecode(cookieStr);
      if (json.containsKey('SESSDATA')) {
        _authData = BilibiliAuthData.fromJson(json);
      } else if (json.containsKey('cookie')) {
        // Handle legacy format or if user manually constructed JSON with 'cookie' key
        // But BilibiliAuthData.fromJson expects keys like SESSDATA.
        // If it's the old format {cookie: "...", refresh_token: "..."}
        final rawCookie = json['cookie'] as String;
        final refreshToken = json['refresh_token'] as String?;
        _authData = BilibiliAuthData.fromCookieString(
          rawCookie,
          refreshToken: refreshToken,
        );
      } else {
        // Fallback for raw cookie string
        _authData = BilibiliAuthData.fromCookieString(cookieStr);
      }
    } catch (e) {
      // Not JSON, treat as raw cookie string
      _authData = BilibiliAuthData.fromCookieString(cookieStr);
    }

    final cookie = _authData!.cookie;

    http.Response? response;
    try {
      response = await http
          .get(
            Uri.parse('https://api.bilibili.com/x/web-interface/nav'),
            headers: {'Cookie': cookie},
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      LogService().warning('Bilibili cookie check network error: $e');
    }

    if (response != null && response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['code'] == 0 && data['data'] is Map<String, dynamic>) {
          final dataObj = data['data'] as Map<String, dynamic>;
          _isLoggedIn = true;
          _currentUser = AccountInfo(
            name: dataObj['uname']?.toString() ?? 'Bilibili User',
            id: dataObj['mid']?.toString() ?? '0',
            avatarUrl: dataObj['face']?.toString(),
            cookie: _authData!.serialize(),
          );
          LogService().info('Logged in as ${_currentUser?.name}');
          return;
        }
      } catch (e) {
        LogService().warning('Bilibili nav parse failed: $e');
      }
    }

    if (response == null) {
      // Network error: keep the session optimistically (startup restore
      // should not wipe a valid login because of a flaky connection).
      _isLoggedIn = true;
      _currentUser = AccountInfo(
        name: 'Bilibili User',
        id: '0',
        cookie: _authData!.serialize(),
      );
    } else {
      // Explicit non-200 / business error: the session is invalid.
      LogService().warning(
        'Bilibili cookie invalid (status ${response.statusCode})',
      );
      _isLoggedIn = false;
      _currentUser = null;
    }
  }

  @override
  Future<void> loginWithQrCode(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const BilibiliQrLoginDialog(),
    );

    if (result != null && result['cookie'] != null) {
      final authData = BilibiliAuthData.fromCookieString(
        result['cookie'],
        refreshToken: result['refresh_token'],
      );
      await loginWithCookie(authData.serialize());
    }
  }

  @override
  Future<void> loginWithWeb(BuildContext context) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const WebLoginPage(
          initialUrl: 'https://passport.bilibili.com/login',
          sourceName: 'Bilibili',
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      await loginWithCookie(result);
    }
  }

  @override
  Future<void> logout() async {
    LogService().info('Bilibili logout: user=${_currentUser?.name}');
    _isLoggedIn = false;
    _currentUser = null;
    _authData = null;
  }

  BigInt _base64UrlToBigInt(String s) {
    var padded = s;
    while (padded.length % 4 != 0) {
      padded += '=';
    }
    final bytes = base64Url.decode(padded);
    return BigInt.parse(
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );
  }

  String _getCorrespondPath(int timestamp) {
    const nStr =
        "y4HdjgJHBlbaBN04VERG4qNBIFHP6a3GozCl75AihQloSWCXC5HDNgyinEnhaQ_4-gaMud_GF50elYXLlCToR9se9Z8z433U3KjM-3Yx7ptKkmQNAMggQwAVKgq3zYAoidNEWuxpkY_mAitTSRLnsJW-NCTa0bqBFF6Wm1MxgfE";
    const eStr = "AQAB";

    final n = _base64UrlToBigInt(nStr);
    final e = _base64UrlToBigInt(eStr);

    final publicKey = RSAPublicKey(n, e);

    final cipher = OAEPEncoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

    final input = Uint8List.fromList(utf8.encode('refresh_$timestamp'));
    final output = cipher.process(input);

    return output.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _refreshCookie() async {
    if (_authData == null || _authData!.refreshToken == null) return;

    try {
      // Get refresh_csrf
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final correspondPath = _getCorrespondPath(timestamp);
      final csrfResponse = await http
          .get(
            Uri.parse('https://www.bilibili.com/correspond/1/$correspondPath'),
            headers: {'Cookie': _authData!.cookie},
          )
          .timeout(const Duration(seconds: 15));

      final refreshCsrfMatch = RegExp(
        r'<div id="1-name">([^<]+)</div>',
      ).firstMatch(csrfResponse.body);
      if (refreshCsrfMatch == null) {
        LogService().error('Failed to get refresh_csrf');
        return;
      }
      final refreshCsrf = refreshCsrfMatch.group(1)!;

      // Get CSRF from cookie
      final csrf = _authData!.biliJct;

      // Refresh Cookie
      final refreshResponse = await http
          .post(
            Uri.parse(
              'https://passport.bilibili.com/x/passport-login/web/cookie/refresh',
            ),
            headers: {
              'Cookie': _authData!.cookie,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {
              'csrf': csrf,
              'refresh_csrf': refreshCsrf,
              'source': 'main_web',
              'refresh_token': _authData!.refreshToken,
            },
          )
          .timeout(const Duration(seconds: 15));

      final refreshData = jsonDecode(refreshResponse.body);
      if (refreshData['code'] == 0) {
        final newRefreshToken =
            (refreshData['data'] as Map<String, dynamic>?)?['refresh_token']
                ?.toString();

        // Parse new cookies
        final setCookie = refreshResponse.headers['set-cookie'];
        if (setCookie != null) {
          final newAuthData = BilibiliAuthData.fromCookieString(
            setCookie,
            refreshToken: newRefreshToken,
          );

          // Confirm refresh
          try {
            await http
                .post(
                  Uri.parse(
                    'https://passport.bilibili.com/x/passport-login/web/confirm/refresh',
                  ),
                  headers: {
                    'Cookie': newAuthData.cookie,
                    'Content-Type': 'application/x-www-form-urlencoded',
                  },
                  body: {
                    'csrf': newAuthData.biliJct,
                    'refresh_token': _authData!.refreshToken,
                  },
                )
                .timeout(const Duration(seconds: 15));
          } catch (e) {
            LogService().warning('Bilibili confirm refresh failed: $e');
          }

          // Update local state
          _authData = newAuthData;

          // Update user info with new cookie
          await loginWithCookie(_authData!.serialize());
          LogService().info('Bilibili cookie refreshed successfully');
        }
      } else {
        LogService().error(
          "Failed to refresh cookie: ${refreshData['message']}",
        );
      }
    } catch (e) {
      LogService().error('Error refreshing cookie: $e');
    }
  }

  @override
  Future<void> checkLoginStatus() async {
    if (_authData == null) {
      _isLoggedIn = false;
      _currentUser = null;
      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse(
              'https://passport.bilibili.com/x/passport-login/web/cookie/info',
            ),
            headers: {'Cookie': _authData!.cookie},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0) {
          _isLoggedIn = true;
          final refresh = data['data']['refresh'] as bool;
          if (refresh) {
            LogService().info('Bilibili cookie needs refresh, refreshing...');
            await _refreshCookie();
          }

          // If we don't have user info, fetch it
          if (_currentUser == null) {
            await loginWithCookie(_authData!.serialize());
          }
        } else {
          LogService().warning(
            "Bilibili login check failed: ${data['message']}",
          );
          _isLoggedIn = false;
          _currentUser = null;
        }
      }
    } catch (e) {
      LogService().error('Error checking Bilibili login status: $e');
    }
  }
}

class BilibiliQrLoginDialog extends StatefulWidget {
  const BilibiliQrLoginDialog({super.key});

  @override
  State<BilibiliQrLoginDialog> createState() => _BilibiliQrLoginDialogState();
}

class _BilibiliQrLoginDialogState extends State<BilibiliQrLoginDialog> {
  String? _qrUrl;
  String? _qrKey;
  String _statusText = '';
  bool _isExpired = false;
  bool _isSuccess = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadQrCode();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadQrCode() async {
    setState(() {
      _isExpired = false;
      _statusText = 'Loading QR Code...';
    });
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://passport.bilibili.com/x/passport-login/web/qrcode/generate',
            ),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (data['code'] == 0) {
        if (mounted) {
          setState(() {
            _qrUrl = data['data']['url'];
            _qrKey = data['data']['qrcode_key'];
            _statusText = AppLocalizations.of(context)!.scanWithApp;
          });
          _startPolling();
        }
      } else {
        if (mounted) {
          setState(() {
            _statusText = 'Failed to load QR code';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = 'Error: $e';
        });
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_qrKey == null || !mounted) return;

      try {
        final response = await http
            .get(
              Uri.parse(
                'https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=$_qrKey',
              ),
            )
            .timeout(const Duration(seconds: 10));
        final data = jsonDecode(response.body);

        if (data['code'] == 0) {
          final code = data['data']['code'];
          if (!mounted) return;

          switch (code) {
            case 0: // Success
              timer.cancel();
              setState(() {
                _isSuccess = true;
                _statusText = 'Login Successful';
              });

              // Extract cookies from headers
              String? setCookie = response.headers['set-cookie'];
              String cookie = setCookie ?? '';
              String? refreshToken = data['data']['refresh_token'];

              // Wait a bit to show success message
              await Future.delayed(const Duration(seconds: 1));
              if (mounted) {
                Navigator.of(
                  context,
                ).pop({'cookie': cookie, 'refresh_token': refreshToken});
              }
              break;
            case 86101: // Not scanned
              // Continue
              break;
            case 86090: // Scanned, not confirmed
              setState(() {
                _statusText = 'Scanned, please confirm on phone';
              });
              break;
            case 86038: // Expired
              timer.cancel();
              setState(() {
                _isExpired = true;
                _statusText = 'QR Code Expired';
              });
              break;
            default:
              // Error or other states
              break;
          }
        }
      } catch (e) {
        // Ignore poll errors
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.bilibiliQrLogin),
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
