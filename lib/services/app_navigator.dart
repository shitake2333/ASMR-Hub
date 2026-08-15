import 'package:flutter/foundation.dart';

/// Lightweight cross-page navigation for the main shell.
///
/// The main page owns the bottom/navigation-rail index; pages that live
/// inside its IndexedStack (source page, playlist page, ...) use this to ask
/// the shell to switch tabs — e.g. after starting playback, jump to the
/// player tab.
class AppNavigator {
  AppNavigator._();

  static final ValueNotifier<int?> _tabRequest = ValueNotifier<int?>(null);

  /// Requests the shell to switch to tab [index]. The shell listens and
  /// clears the request after applying it.
  static void goToTab(int index) {
    _tabRequest.value = index;
  }

  /// The shell should call this to subscribe to tab requests.
  static ValueNotifier<int?> get tabRequest => _tabRequest;
}
