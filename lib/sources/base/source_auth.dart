import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import 'package:asmr_hub/models/account_info.dart';

abstract class SourceAuth {
  bool get requiresAuth;
  bool get isLoggedIn;

  // Login method support flags
  bool get supportsQrCodeLogin;
  bool get supportsWebLogin;
  bool get supportsCookieLogin;
  bool get supportsCredentialsLogin;

  AccountInfo? get currentUser;
  String? get cookie;

  /// Shared HTTP session for the source.
  final Dio clientSession;

  SourceAuth(String baseUrl)
    : clientSession = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: Duration(seconds: 5),
          receiveTimeout: Duration(seconds: 3),
          headers: {'User-Agent': 'Dart/3.0'},
        ),
      );

  Future<void> closeHttpSession() async {
    clientSession.close(force: true);
  }

  void updateCookie() {
    clientSession.options.headers['Cookie'] = cookie;
  }

  Future<Map<String, dynamic>> get(String path) async {
    final response = await clientSession.get(path);
    return response.data;
  }

  Future<void> loginWithCookie(String cookie);
  Future<void> loginWithQrCode(BuildContext context);
  Future<void> loginWithWeb(BuildContext context);
  Future<void> loginWithCredentials(String username, String password);
  Future<void> logout();
  Future<void> checkLoginStatus();
}
