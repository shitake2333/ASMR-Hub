import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @accountSettings.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountSettings;

  /// No description provided for @appearanceSettings.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceSettings;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @darkModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Switch application theme'**
  String get darkModeSubtitle;

  /// No description provided for @themeColor.
  ///
  /// In en, this message translates to:
  /// **'Theme Color'**
  String get themeColor;

  /// No description provided for @themeColorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose application primary color'**
  String get themeColorSubtitle;

  /// No description provided for @fontSettings.
  ///
  /// In en, this message translates to:
  /// **'Font Settings'**
  String get fontSettings;

  /// No description provided for @fontSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Adjust font style and size'**
  String get fontSettingsSubtitle;

  /// No description provided for @fontFamily.
  ///
  /// In en, this message translates to:
  /// **'Font Family'**
  String get fontFamily;

  /// No description provided for @defaultFont.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultFont;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get fontSize;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get systemDefault;

  /// No description provided for @playSettings.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get playSettings;

  /// No description provided for @sourceAccountManagement.
  ///
  /// In en, this message translates to:
  /// **'Source Account Management'**
  String get sourceAccountManagement;

  /// No description provided for @sourceAccountManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage login status of platforms'**
  String get sourceAccountManagementSubtitle;

  /// No description provided for @autoPlay.
  ///
  /// In en, this message translates to:
  /// **'Auto Play'**
  String get autoPlay;

  /// No description provided for @autoPlaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically play next song'**
  String get autoPlaySubtitle;

  /// No description provided for @sleepTimer.
  ///
  /// In en, this message translates to:
  /// **'Sleep Timer'**
  String get sleepTimer;

  /// No description provided for @sleepTimerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes later stop playing'**
  String sleepTimerSubtitle(int minutes);

  /// No description provided for @sleepTimerActiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer active'**
  String get sleepTimerActiveTitle;

  /// No description provided for @sleepTimerEndsAt.
  ///
  /// In en, this message translates to:
  /// **'Playback stops at {time}'**
  String sleepTimerEndsAt(Object time);

  /// No description provided for @sleepTimerRemaining.
  ///
  /// In en, this message translates to:
  /// **'{time} remaining'**
  String sleepTimerRemaining(Object time);

  /// No description provided for @sleepTimerPresetLabel.
  ///
  /// In en, this message translates to:
  /// **'Quick presets'**
  String get sleepTimerPresetLabel;

  /// No description provided for @sleepTimerCustomLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get sleepTimerCustomLabel;

  /// No description provided for @sleepTimerCustomHint.
  ///
  /// In en, this message translates to:
  /// **'Minutes (1-480)'**
  String get sleepTimerCustomHint;

  /// No description provided for @sleepTimerOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off timer'**
  String get sleepTimerOff;

  /// No description provided for @sleepTimerOffHint.
  ///
  /// In en, this message translates to:
  /// **'Stops playback when the timer ends'**
  String get sleepTimerOffHint;

  /// No description provided for @sleepTimerPlayUntilEnd.
  ///
  /// In en, this message translates to:
  /// **'Stop at end of track'**
  String get sleepTimerPlayUntilEnd;

  /// No description provided for @sleepTimerSetStart.
  ///
  /// In en, this message translates to:
  /// **'Start timer'**
  String get sleepTimerSetStart;

  /// No description provided for @smartSleepDetection.
  ///
  /// In en, this message translates to:
  /// **'Smart Sleep Detection'**
  String get smartSleepDetection;

  /// No description provided for @smartSleepDetectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stop playback when sleep is detected'**
  String get smartSleepDetectionSubtitle;

  /// No description provided for @notificationSettings.
  ///
  /// In en, this message translates to:
  /// **'Notification'**
  String get notificationSettings;

  /// No description provided for @pushNotification.
  ///
  /// In en, this message translates to:
  /// **'Push Notification'**
  String get pushNotification;

  /// No description provided for @pushNotificationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Receive new content and update notifications'**
  String get pushNotificationSubtitle;

  /// No description provided for @storageSettings.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storageSettings;

  /// No description provided for @cachePath.
  ///
  /// In en, this message translates to:
  /// **'Cache Path'**
  String get cachePath;

  /// No description provided for @cacheFormat.
  ///
  /// In en, this message translates to:
  /// **'Cache Format'**
  String get cacheFormat;

  /// No description provided for @cacheFormatOffSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Do not cache decoded audio'**
  String get cacheFormatOffSubtitle;

  /// No description provided for @cacheFormatWavSubtitle.
  ///
  /// In en, this message translates to:
  /// **'WAV lossless (~10 MB/min, seekable)'**
  String get cacheFormatWavSubtitle;

  /// No description provided for @cacheFormatMp3Subtitle.
  ///
  /// In en, this message translates to:
  /// **'MP3 compressed (~1.4 MB/min, recommended)'**
  String get cacheFormatMp3Subtitle;

  /// No description provided for @cacheFormatFlacSubtitle.
  ///
  /// In en, this message translates to:
  /// **'FLAC lossless (~5 MB/min)'**
  String get cacheFormatFlacSubtitle;

  /// No description provided for @downloadSettings.
  ///
  /// In en, this message translates to:
  /// **'Download Settings'**
  String get downloadSettings;

  /// No description provided for @downloadSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Download rate, concurrency and cache format'**
  String get downloadSettingsSubtitle;

  /// No description provided for @maxDownloadRate.
  ///
  /// In en, this message translates to:
  /// **'Max Download Rate'**
  String get maxDownloadRate;

  /// No description provided for @maxDownloadRateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'0 means unlimited'**
  String get maxDownloadRateSubtitle;

  /// No description provided for @maxDownloadRateUnit.
  ///
  /// In en, this message translates to:
  /// **'KB/s'**
  String get maxDownloadRateUnit;

  /// No description provided for @maxDownloadThreads.
  ///
  /// In en, this message translates to:
  /// **'Max Download Threads'**
  String get maxDownloadThreads;

  /// No description provided for @maxDownloadThreadsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Concurrent download tasks'**
  String get maxDownloadThreadsSubtitle;

  /// No description provided for @downloadPath.
  ///
  /// In en, this message translates to:
  /// **'Download Path'**
  String get downloadPath;

  /// No description provided for @resetPath.
  ///
  /// In en, this message translates to:
  /// **'Reset Path'**
  String get resetPath;

  /// No description provided for @resetPathSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Restore default storage location'**
  String get resetPathSubtitle;

  /// No description provided for @storageManagement.
  ///
  /// In en, this message translates to:
  /// **'Storage Management'**
  String get storageManagement;

  /// No description provided for @storageManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage downloads and cache'**
  String get storageManagementSubtitle;

  /// No description provided for @otherSettings.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get otherSettings;

  /// No description provided for @systemLog.
  ///
  /// In en, this message translates to:
  /// **'System Log'**
  String get systemLog;

  /// No description provided for @systemLogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View application run logs'**
  String get systemLogSubtitle;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About App'**
  String get aboutApp;

  /// No description provided for @aboutAppSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Version and developer info'**
  String get aboutAppSubtitle;

  /// No description provided for @githubRepo.
  ///
  /// In en, this message translates to:
  /// **'GitHub Repository'**
  String get githubRepo;

  /// No description provided for @githubRepoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View source code and report issues'**
  String get githubRepoSubtitle;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Switch application language'**
  String get languageSubtitle;

  /// No description provided for @navSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get navSource;

  /// No description provided for @navSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'ASMR Source'**
  String get navSourceTitle;

  /// No description provided for @navPlayer.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get navPlayer;

  /// No description provided for @navPlayerTitle.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get navPlayerTitle;

  /// No description provided for @navPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get navPlaylist;

  /// No description provided for @navPlaylistTitle.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get navPlaylistTitle;

  /// No description provided for @appDescription.
  ///
  /// In en, this message translates to:
  /// **'An application focused on ASMR audio playback, providing you with a high-quality relaxation experience.'**
  String get appDescription;

  /// No description provided for @developer.
  ///
  /// In en, this message translates to:
  /// **'Developer: {name}'**
  String developer(String name);

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Contact Email: {address}'**
  String email(String address);

  /// No description provided for @settingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltip;

  /// No description provided for @noContent.
  ///
  /// In en, this message translates to:
  /// **'No content playing'**
  String get noContent;

  /// No description provided for @goToSource.
  ///
  /// In en, this message translates to:
  /// **'Go to \"Source\" page to select content'**
  String get goToSource;

  /// No description provided for @nowPlaying.
  ///
  /// In en, this message translates to:
  /// **'Now Playing'**
  String get nowPlaying;

  /// No description provided for @favoriteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favoriteTooltip;

  /// No description provided for @shareTooltip.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareTooltip;

  /// No description provided for @moreTooltip.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreTooltip;

  /// No description provided for @immersiveAudio.
  ///
  /// In en, this message translates to:
  /// **'Immersive ASMR soundscapes, keep relaxed.'**
  String get immersiveAudio;

  /// No description provided for @downloadAudio.
  ///
  /// In en, this message translates to:
  /// **'Download Audio'**
  String get downloadAudio;

  /// No description provided for @downloadAll.
  ///
  /// In en, this message translates to:
  /// **'Download all'**
  String get downloadAll;

  /// No description provided for @downloadAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'Download all {count} tracks?'**
  String downloadAllConfirm(int count);

  /// No description provided for @downloadAllStarted.
  ///
  /// In en, this message translates to:
  /// **'Downloading {count} tracks'**
  String downloadAllStarted(int count);

  /// No description provided for @downloadAllAlready.
  ///
  /// In en, this message translates to:
  /// **'All tracks are already downloaded'**
  String get downloadAllAlready;

  /// No description provided for @downloadAllDone.
  ///
  /// In en, this message translates to:
  /// **'Nothing to download'**
  String get downloadAllDone;

  /// No description provided for @clearAllCache.
  ///
  /// In en, this message translates to:
  /// **'Clear All Cache'**
  String get clearAllCache;

  /// No description provided for @clearAllCacheConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all downloads of this source?'**
  String get clearAllCacheConfirm;

  /// No description provided for @clearAllCacheContent.
  ///
  /// In en, this message translates to:
  /// **'This deletes {size} of downloaded files.'**
  String clearAllCacheContent(String size);

  /// No description provided for @downloadUsage.
  ///
  /// In en, this message translates to:
  /// **'Downloads: {size}'**
  String downloadUsage(String size);

  /// No description provided for @clearDownloads.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearDownloads;

  /// No description provided for @playQueue.
  ///
  /// In en, this message translates to:
  /// **'Play Queue'**
  String get playQueue;

  /// No description provided for @clearQueue.
  ///
  /// In en, this message translates to:
  /// **'Clear Queue'**
  String get clearQueue;

  /// No description provided for @tracksCount.
  ///
  /// In en, this message translates to:
  /// **'{count} tracks'**
  String tracksCount(int count);

  /// No description provided for @shuffleTooltip.
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get shuffleTooltip;

  /// No description provided for @repeatTooltip.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get repeatTooltip;

  /// No description provided for @muteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get muteTooltip;

  /// No description provided for @unmuteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmuteTooltip;

  /// No description provided for @createPlaylistTitle.
  ///
  /// In en, this message translates to:
  /// **'Create New Playlist'**
  String get createPlaylistTitle;

  /// No description provided for @playlistNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter playlist name'**
  String get playlistNameHint;

  /// No description provided for @playlistNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get playlistNameLabel;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @playlistEmpty.
  ///
  /// In en, this message translates to:
  /// **'Playlist is empty'**
  String get playlistEmpty;

  /// No description provided for @startPlaying.
  ///
  /// In en, this message translates to:
  /// **'Start playing: {name}'**
  String startPlaying(String name);

  /// No description provided for @confirmDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Delete'**
  String get confirmDeleteTitle;

  /// No description provided for @confirmDeleteContent.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete playlist \"{name}\"?'**
  String confirmDeleteContent(String name);

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteSource.
  ///
  /// In en, this message translates to:
  /// **'Delete source'**
  String get deleteSource;

  /// No description provided for @deleteSourceConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this source?'**
  String get deleteSourceConfirm;

  /// No description provided for @deleteSourceContent.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will be removed from your source list.'**
  String deleteSourceContent(String name);

  /// No description provided for @myPlaylists.
  ///
  /// In en, this message translates to:
  /// **'My Playlists'**
  String get myPlaylists;

  /// No description provided for @currentQueue.
  ///
  /// In en, this message translates to:
  /// **'Current Queue'**
  String get currentQueue;

  /// No description provided for @customPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Custom Playlists'**
  String get customPlaylists;

  /// No description provided for @newPlaylist.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newPlaylist;

  /// No description provided for @noPlaylists.
  ///
  /// In en, this message translates to:
  /// **'No playlists, click top right to create'**
  String get noPlaylists;

  /// No description provided for @tracksCountSuffix.
  ///
  /// In en, this message translates to:
  /// **' tracks'**
  String get tracksCountSuffix;

  /// No description provided for @playAllTooltip.
  ///
  /// In en, this message translates to:
  /// **'Play All'**
  String get playAllTooltip;

  /// No description provided for @deletePlaylistTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete Playlist'**
  String get deletePlaylistTooltip;

  /// No description provided for @clearQueueTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear Queue'**
  String get clearQueueTooltip;

  /// No description provided for @queueEmpty.
  ///
  /// In en, this message translates to:
  /// **'Current queue is empty'**
  String get queueEmpty;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search ASMR content...'**
  String get searchHint;

  /// No description provided for @searchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTooltip;

  /// No description provided for @sourceFilter.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get sourceFilter;

  /// No description provided for @allSources.
  ///
  /// In en, this message translates to:
  /// **'All Sources'**
  String get allSources;

  /// No description provided for @typeFilter.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get typeFilter;

  /// No description provided for @allTypes.
  ///
  /// In en, this message translates to:
  /// **'All Types'**
  String get allTypes;

  /// No description provided for @liveStream.
  ///
  /// In en, this message translates to:
  /// **'Live Stream'**
  String get liveStream;

  /// No description provided for @fileVideo.
  ///
  /// In en, this message translates to:
  /// **'File/Video'**
  String get fileVideo;

  /// No description provided for @tagFilter.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tagFilter;

  /// No description provided for @selectTag.
  ///
  /// In en, this message translates to:
  /// **'Select tag to filter...'**
  String get selectTag;

  /// No description provided for @mySourcesTab.
  ///
  /// In en, this message translates to:
  /// **'My Sources'**
  String get mySourcesTab;

  /// No description provided for @searchResultsTab.
  ///
  /// In en, this message translates to:
  /// **'Search Results'**
  String get searchResultsTab;

  /// No description provided for @recommendationsTab.
  ///
  /// In en, this message translates to:
  /// **'Recommendations'**
  String get recommendationsTab;

  /// No description provided for @addSourceFab.
  ///
  /// In en, this message translates to:
  /// **'Add Source'**
  String get addSourceFab;

  /// No description provided for @noSourcesFound.
  ///
  /// In en, this message translates to:
  /// **'No sources found'**
  String get noSourcesFound;

  /// No description provided for @clearFilterHint.
  ///
  /// In en, this message translates to:
  /// **'Try clearing filters or adding new sources'**
  String get clearFilterHint;

  /// No description provided for @searchContent.
  ///
  /// In en, this message translates to:
  /// **'Search ASMR Audio Content'**
  String get searchContent;

  /// No description provided for @searchDescription.
  ///
  /// In en, this message translates to:
  /// **'Support searching YouTube, Bilibili, etc.'**
  String get searchDescription;

  /// No description provided for @loadingFailed.
  ///
  /// In en, this message translates to:
  /// **'Loading failed: {error}'**
  String loadingFailed(String error);

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @noRecommendations.
  ///
  /// In en, this message translates to:
  /// **'No recommendations'**
  String get noRecommendations;

  /// No description provided for @addSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'Add ASMR Source'**
  String get addSourceTitle;

  /// No description provided for @sourceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sourceNameLabel;

  /// No description provided for @sourceNameHint.
  ///
  /// In en, this message translates to:
  /// **'Name this source'**
  String get sourceNameHint;

  /// No description provided for @sourceTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Source Type'**
  String get sourceTypeLabel;

  /// No description provided for @localPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Local Path'**
  String get localPathLabel;

  /// No description provided for @localPathHint.
  ///
  /// In en, this message translates to:
  /// **'Select file or folder'**
  String get localPathHint;

  /// No description provided for @selectFile.
  ///
  /// In en, this message translates to:
  /// **'Select File'**
  String get selectFile;

  /// No description provided for @selectFolder.
  ///
  /// In en, this message translates to:
  /// **'Select Folder'**
  String get selectFolder;

  /// No description provided for @urlPathLabel.
  ///
  /// In en, this message translates to:
  /// **'URL / Path'**
  String get urlPathLabel;

  /// No description provided for @urlPathHint.
  ///
  /// In en, this message translates to:
  /// **'Enter link or file path'**
  String get urlPathHint;

  /// No description provided for @tagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tagsLabel;

  /// No description provided for @tagsHint.
  ///
  /// In en, this message translates to:
  /// **'Comma separated (e.g. ASMR, Sleep)'**
  String get tagsHint;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @searchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search failed: {error}'**
  String searchFailed(String error);

  /// No description provided for @minutesSuffix.
  ///
  /// In en, this message translates to:
  /// **' Minutes'**
  String get minutesSuffix;

  /// No description provided for @hoursSuffix.
  ///
  /// In en, this message translates to:
  /// **'h'**
  String get hoursSuffix;

  /// No description provided for @sleepTimerSet.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer set to {minutes} minutes'**
  String sleepTimerSet(int minutes);

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get confirm;

  /// No description provided for @pathReset.
  ///
  /// In en, this message translates to:
  /// **'Path reset to default'**
  String get pathReset;

  /// No description provided for @cacheManagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Cache Management'**
  String get cacheManagementTitle;

  /// No description provided for @totalCacheSize.
  ///
  /// In en, this message translates to:
  /// **'Total Cache Size'**
  String get totalCacheSize;

  /// No description provided for @confirmClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Clear'**
  String get confirmClearTitle;

  /// No description provided for @confirmClearAllContent.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear all cache?'**
  String get confirmClearAllContent;

  /// No description provided for @confirmClearSourceContent.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear cache for this source?'**
  String get confirmClearSourceContent;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @cacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared'**
  String get cacheCleared;

  /// No description provided for @spaceUsed.
  ///
  /// In en, this message translates to:
  /// **'Space used: {size}'**
  String spaceUsed(String size);

  /// No description provided for @systemLogTitle.
  ///
  /// In en, this message translates to:
  /// **'System Log'**
  String get systemLogTitle;

  /// No description provided for @logsCopied.
  ///
  /// In en, this message translates to:
  /// **'Logs copied to clipboard'**
  String get logsCopied;

  /// No description provided for @sourceAccountManagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Source Account Management'**
  String get sourceAccountManagementTitle;

  /// No description provided for @loggedIn.
  ///
  /// In en, this message translates to:
  /// **'Logged in: {user}'**
  String loggedIn(String user);

  /// No description provided for @notLoggedIn.
  ///
  /// In en, this message translates to:
  /// **'Not logged in'**
  String get notLoggedIn;

  /// No description provided for @scanQrCodeLogin.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code Login'**
  String get scanQrCodeLogin;

  /// No description provided for @cookieLogin.
  ///
  /// In en, this message translates to:
  /// **'Cookie Login'**
  String get cookieLogin;

  /// No description provided for @cookieLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'{source} Cookie Login'**
  String cookieLoginTitle(String source);

  /// No description provided for @enterCookieHint.
  ///
  /// In en, this message translates to:
  /// **'Enter Cookie'**
  String get enterCookieHint;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @startPlayingCount.
  ///
  /// In en, this message translates to:
  /// **'Start playing: {count} tracks'**
  String startPlayingCount(int count);

  /// No description provided for @addToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add to Playlist'**
  String get addToPlaylist;

  /// No description provided for @addedToQueue.
  ///
  /// In en, this message translates to:
  /// **'Added {count} tracks to current queue'**
  String addedToQueue(int count);

  /// No description provided for @noCustomPlaylists.
  ///
  /// In en, this message translates to:
  /// **'No custom playlists'**
  String get noCustomPlaylists;

  /// No description provided for @addedToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Added {count} tracks to {name}'**
  String addedToPlaylist(int count, String name);

  /// No description provided for @createdAndAddedToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Created and added {count} tracks to {name}'**
  String createdAndAddedToPlaylist(int count, String name);

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @recordLive.
  ///
  /// In en, this message translates to:
  /// **'Record live'**
  String get recordLive;

  /// No description provided for @recordFailed.
  ///
  /// In en, this message translates to:
  /// **'Recording failed (live may be offline)'**
  String get recordFailed;

  /// No description provided for @liveNow.
  ///
  /// In en, this message translates to:
  /// **'Live now'**
  String get liveNow;

  /// No description provided for @liveOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get liveOffline;

  /// No description provided for @recordings.
  ///
  /// In en, this message translates to:
  /// **'Recordings'**
  String get recordings;

  /// No description provided for @recordingInProgress.
  ///
  /// In en, this message translates to:
  /// **'Recording…'**
  String get recordingInProgress;

  /// No description provided for @stopRecording.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get stopRecording;

  /// No description provided for @playAll.
  ///
  /// In en, this message translates to:
  /// **'Play All'**
  String get playAll;

  /// No description provided for @addAll.
  ///
  /// In en, this message translates to:
  /// **'Add All'**
  String get addAll;

  /// No description provided for @tagManagement.
  ///
  /// In en, this message translates to:
  /// **'Tag Management'**
  String get tagManagement;

  /// No description provided for @addTag.
  ///
  /// In en, this message translates to:
  /// **'Add Tag'**
  String get addTag;

  /// No description provided for @tagNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter tag name'**
  String get tagNameHint;

  /// No description provided for @fileList.
  ///
  /// In en, this message translates to:
  /// **'File List ({count})'**
  String fileList(int count);

  /// No description provided for @noAudioFilesFound.
  ///
  /// In en, this message translates to:
  /// **'No audio files found'**
  String get noAudioFilesFound;

  /// No description provided for @bilibiliQrLogin.
  ///
  /// In en, this message translates to:
  /// **'Bilibili QR Login'**
  String get bilibiliQrLogin;

  /// No description provided for @scanWithApp.
  ///
  /// In en, this message translates to:
  /// **'Please scan with Bilibili App'**
  String get scanWithApp;

  /// No description provided for @sourceLocal.
  ///
  /// In en, this message translates to:
  /// **'Local Files'**
  String get sourceLocal;

  /// No description provided for @unknownArtist.
  ///
  /// In en, this message translates to:
  /// **'Unknown Artist'**
  String get unknownArtist;

  /// No description provided for @audioEffects.
  ///
  /// In en, this message translates to:
  /// **'Audio Effects'**
  String get audioEffects;

  /// No description provided for @effectNoiseReduction.
  ///
  /// In en, this message translates to:
  /// **'Noise Reduction'**
  String get effectNoiseReduction;

  /// No description provided for @effectNoiseReductionDesc.
  ///
  /// In en, this message translates to:
  /// **'Reduces high frequency noise like static or fans.'**
  String get effectNoiseReductionDesc;

  /// No description provided for @effectSafeSleep.
  ///
  /// In en, this message translates to:
  /// **'Safe Sleep'**
  String get effectSafeSleep;

  /// No description provided for @effectSafeSleepDesc.
  ///
  /// In en, this message translates to:
  /// **'Softens audio and prevents sudden loud noises.'**
  String get effectSafeSleepDesc;

  /// No description provided for @effectLimiter.
  ///
  /// In en, this message translates to:
  /// **'Limiter'**
  String get effectLimiter;

  /// No description provided for @effectLimiterDesc.
  ///
  /// In en, this message translates to:
  /// **'Prevents audio clipping and sudden loud peaks.'**
  String get effectLimiterDesc;

  /// No description provided for @paramCutoff.
  ///
  /// In en, this message translates to:
  /// **'Cutoff Frequency'**
  String get paramCutoff;

  /// No description provided for @paramCutoffDesc.
  ///
  /// In en, this message translates to:
  /// **'Frequencies above this value will be reduced.'**
  String get paramCutoffDesc;

  /// No description provided for @paramResonance.
  ///
  /// In en, this message translates to:
  /// **'Resonance'**
  String get paramResonance;

  /// No description provided for @paramResonanceDesc.
  ///
  /// In en, this message translates to:
  /// **'Resonance of the filter.'**
  String get paramResonanceDesc;

  /// No description provided for @paramEnableLimiter.
  ///
  /// In en, this message translates to:
  /// **'Enable Limiter'**
  String get paramEnableLimiter;

  /// No description provided for @paramEnableLimiterDesc.
  ///
  /// In en, this message translates to:
  /// **'Prevents sudden loud noises.'**
  String get paramEnableLimiterDesc;

  /// No description provided for @paramSoftness.
  ///
  /// In en, this message translates to:
  /// **'Softness (Cutoff)'**
  String get paramSoftness;

  /// No description provided for @paramSoftnessDesc.
  ///
  /// In en, this message translates to:
  /// **'Lower values make audio softer.'**
  String get paramSoftnessDesc;

  /// No description provided for @volume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volume;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @sourceHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get sourceHelp;

  /// No description provided for @downloadCompleted.
  ///
  /// In en, this message translates to:
  /// **'Download completed'**
  String get downloadCompleted;

  /// No description provided for @cachedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Cached - tap to remove'**
  String get cachedTooltip;

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String downloadFailed(String error);

  /// No description provided for @downloadManagement.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloadManagement;

  /// No description provided for @downloadManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View background download tasks'**
  String get downloadManagementSubtitle;

  /// No description provided for @importFromAccounts.
  ///
  /// In en, this message translates to:
  /// **'Import from Accounts'**
  String get importFromAccounts;

  /// No description provided for @importFromAccountsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-add favorites, followed channels and playlists from logged-in platforms'**
  String get importFromAccountsSubtitle;

  /// No description provided for @importing.
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get importing;

  /// No description provided for @importResult.
  ///
  /// In en, this message translates to:
  /// **'Imported %count% sources'**
  String importResult(int count);

  /// No description provided for @importEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing to import'**
  String get importEmpty;

  /// No description provided for @importSelectTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Sources'**
  String get importSelectTitle;

  /// No description provided for @importSelectHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a platform and type'**
  String get importSelectHint;

  /// No description provided for @importNotLoggedIn.
  ///
  /// In en, this message translates to:
  /// **'Not logged in'**
  String get importNotLoggedIn;

  /// No description provided for @importSelected.
  ///
  /// In en, this message translates to:
  /// **'Import Selected (%count%)'**
  String importSelected(int count);

  /// No description provided for @importNoSelection.
  ///
  /// In en, this message translates to:
  /// **'Check something to import first'**
  String get importNoSelection;

  /// No description provided for @importBilibiliFavorites.
  ///
  /// In en, this message translates to:
  /// **'Bilibili Favorites'**
  String get importBilibiliFavorites;

  /// No description provided for @importBilibiliFollowings.
  ///
  /// In en, this message translates to:
  /// **'Bilibili Followings'**
  String get importBilibiliFollowings;

  /// No description provided for @importDouyuFollows.
  ///
  /// In en, this message translates to:
  /// **'Douyu Follows'**
  String get importDouyuFollows;

  /// No description provided for @importAsmrOnePlaylists.
  ///
  /// In en, this message translates to:
  /// **'asmr.one Playlists'**
  String get importAsmrOnePlaylists;

  /// No description provided for @importDlsiteLibrary.
  ///
  /// In en, this message translates to:
  /// **'DLsite Purchased'**
  String get importDlsiteLibrary;

  /// No description provided for @downloadsTab.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloadsTab;

  /// No description provided for @watchRoomsTab.
  ///
  /// In en, this message translates to:
  /// **'Live watch'**
  String get watchRoomsTab;

  /// No description provided for @watchRoomsHint.
  ///
  /// In en, this message translates to:
  /// **'Add live rooms: the app probes them periodically even without playback and records automatically once they go live, stopping when they go offline.'**
  String get watchRoomsHint;

  /// No description provided for @noWatchRooms.
  ///
  /// In en, this message translates to:
  /// **'No watched rooms yet. Add one below.'**
  String get noWatchRooms;

  /// No description provided for @addRoom.
  ///
  /// In en, this message translates to:
  /// **'Add room'**
  String get addRoom;

  /// No description provided for @addRoomFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot recognize this live URL'**
  String get addRoomFailed;

  /// No description provided for @roomRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get roomRecording;

  /// No description provided for @roomWatching.
  ///
  /// In en, this message translates to:
  /// **'Watching'**
  String get roomWatching;

  /// No description provided for @roomPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get roomPaused;

  /// No description provided for @liveFor.
  ///
  /// In en, this message translates to:
  /// **'Live for {time}'**
  String liveFor(Object time);

  /// No description provided for @recordingFor.
  ///
  /// In en, this message translates to:
  /// **'Recording {time}'**
  String recordingFor(Object time);

  /// No description provided for @playbackSettings.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get playbackSettings;

  /// No description provided for @audioQuality.
  ///
  /// In en, this message translates to:
  /// **'Audio quality'**
  String get audioQuality;

  /// No description provided for @audioQualitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Quality for remote on-demand media (some require login)'**
  String get audioQualitySubtitle;

  /// No description provided for @qualityAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (highest)'**
  String get qualityAuto;

  /// No description provided for @scanWithDouyuApp.
  ///
  /// In en, this message translates to:
  /// **'Scan with the Douyu app'**
  String get scanWithDouyuApp;

  /// No description provided for @renameSource.
  ///
  /// In en, this message translates to:
  /// **'Rename source'**
  String get renameSource;

  /// No description provided for @renameSourceHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a new name'**
  String get renameSourceHint;

  /// No description provided for @accountLogin.
  ///
  /// In en, this message translates to:
  /// **'Account login'**
  String get accountLogin;

  /// No description provided for @accountLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Login {source}'**
  String accountLoginTitle(Object source);

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @removeFromQueue.
  ///
  /// In en, this message translates to:
  /// **'Remove from queue'**
  String get removeFromQueue;

  /// No description provided for @downloadStarted.
  ///
  /// In en, this message translates to:
  /// **'Download started'**
  String get downloadStarted;

  /// No description provided for @liveEnded.
  ///
  /// In en, this message translates to:
  /// **'The stream has ended'**
  String get liveEnded;

  /// No description provided for @navDownloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get navDownloads;

  /// No description provided for @navDownloadsTitle.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get navDownloadsTitle;

  /// No description provided for @noDownloads.
  ///
  /// In en, this message translates to:
  /// **'No download tasks'**
  String get noDownloads;

  /// No description provided for @downloadQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get downloadQueued;

  /// No description provided for @downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get downloading;

  /// No description provided for @downloadCompletedShort.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get downloadCompletedShort;

  /// No description provided for @downloadFailedShort.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get downloadFailedShort;

  /// No description provided for @downloadCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get downloadCanceled;

  /// No description provided for @downloadOffHint.
  ///
  /// In en, this message translates to:
  /// **'Download format is Off, enable it in Settings first'**
  String get downloadOffHint;

  /// No description provided for @buffering.
  ///
  /// In en, this message translates to:
  /// **'Buffering…'**
  String get buffering;

  /// No description provided for @playbackError.
  ///
  /// In en, this message translates to:
  /// **'Playback failed'**
  String get playbackError;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Network error, please check your connection and retry'**
  String get networkError;

  /// No description provided for @toggleDesktopLayout.
  ///
  /// In en, this message translates to:
  /// **'Toggle Desktop Layout'**
  String get toggleDesktopLayout;

  /// No description provided for @launchUrlFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not launch {url}'**
  String launchUrlFailed(String url);

  /// No description provided for @unknownUser.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknownUser;

  /// No description provided for @webLogin.
  ///
  /// In en, this message translates to:
  /// **'Web Login'**
  String get webLogin;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
