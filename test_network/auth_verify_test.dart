// Temporary verification script for auth cookie validation logic.
// Run: flutter test test/auth_verify_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:asmr_hub/sources/dlsite/dlsite_auth.dart';
import 'package:asmr_hub/sources/douyu/douyu_auth.dart';
import 'package:asmr_hub/sources/youtube/youtube_auth.dart';

void main() {
  test('Douyu rejects invalid cookie', () async {
    final douyu = DouyuAuth.instance;
    await douyu.loginWithCookie('acf_auth=invalid; dy_authid=invalid');
    expect(douyu.isLoggedIn, isFalse);
  });

  test('DLSite rejects invalid cookie', () async {
    final dlsite = DLSiteAuth.instance;
    await dlsite.loginWithCookie('login_secure_id=invalid; ckcy=invalid');
    expect(dlsite.isLoggedIn, isFalse);
  });

  test('YouTube rejects invalid cookie', () async {
    final youtube = YouTubeAuth();
    await youtube.loginWithCookie('SID=invalid-cookie-value; HSID=invalid');
    expect(youtube.isLoggedIn, isFalse);
  });
}
