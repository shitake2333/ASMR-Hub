// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settingsTitle => 'Settings';

  @override
  String get accountSettings => 'Account';

  @override
  String get appearanceSettings => 'Appearance';

  @override
  String get darkMode => 'Dark Mode';

  @override
  String get darkModeSubtitle => 'Switch application theme';

  @override
  String get themeColor => 'Theme Color';

  @override
  String get themeColorSubtitle => 'Choose application primary color';

  @override
  String get fontSettings => 'Font Settings';

  @override
  String get fontSettingsSubtitle => 'Adjust font style and size';

  @override
  String get fontFamily => 'Font Family';

  @override
  String get defaultFont => 'Default';

  @override
  String get fontSize => 'Font Size';

  @override
  String get systemDefault => 'System Default';

  @override
  String get playSettings => 'Playback';

  @override
  String get sourceAccountManagement => 'Source Account Management';

  @override
  String get sourceAccountManagementSubtitle =>
      'Manage login status of platforms';

  @override
  String get autoPlay => 'Auto Play';

  @override
  String get autoPlaySubtitle => 'Automatically play next song';

  @override
  String get sleepTimer => 'Sleep Timer';

  @override
  String sleepTimerSubtitle(int minutes) {
    return '$minutes minutes later stop playing';
  }

  @override
  String get sleepTimerActiveTitle => 'Sleep timer active';

  @override
  String sleepTimerEndsAt(Object time) {
    return 'Playback stops at $time';
  }

  @override
  String sleepTimerRemaining(Object time) {
    return '$time remaining';
  }

  @override
  String get sleepTimerPresetLabel => 'Quick presets';

  @override
  String get sleepTimerCustomLabel => 'Custom';

  @override
  String get sleepTimerCustomHint => 'Minutes (1-480)';

  @override
  String get sleepTimerOff => 'Turn off timer';

  @override
  String get sleepTimerOffHint => 'Stops playback when the timer ends';

  @override
  String get sleepTimerPlayUntilEnd => 'Stop at end of track';

  @override
  String get sleepTimerSetStart => 'Start timer';

  @override
  String get smartSleepDetection => 'Smart Sleep Detection';

  @override
  String get smartSleepDetectionSubtitle =>
      'Stop playback when sleep is detected';

  @override
  String get notificationSettings => 'Notification';

  @override
  String get pushNotification => 'Push Notification';

  @override
  String get pushNotificationSubtitle =>
      'Receive new content and update notifications';

  @override
  String get storageSettings => 'Storage';

  @override
  String get cachePath => 'Cache Path';

  @override
  String get cacheFormat => 'Cache Format';

  @override
  String get cacheFormatOffSubtitle => 'Do not cache decoded audio';

  @override
  String get cacheFormatWavSubtitle => 'WAV lossless (~10 MB/min, seekable)';

  @override
  String get cacheFormatMp3Subtitle =>
      'MP3 compressed (~1.4 MB/min, recommended)';

  @override
  String get cacheFormatFlacSubtitle => 'FLAC lossless (~5 MB/min)';

  @override
  String get downloadSettings => 'Download Settings';

  @override
  String get downloadSettingsSubtitle =>
      'Download rate, concurrency and cache format';

  @override
  String get maxDownloadRate => 'Max Download Rate';

  @override
  String get maxDownloadRateSubtitle => '0 means unlimited';

  @override
  String get maxDownloadRateUnit => 'KB/s';

  @override
  String get maxDownloadThreads => 'Max Download Threads';

  @override
  String get maxDownloadThreadsSubtitle => 'Concurrent download tasks';

  @override
  String get downloadPath => 'Download Path';

  @override
  String get resetPath => 'Reset Path';

  @override
  String get resetPathSubtitle => 'Restore default storage location';

  @override
  String get storageManagement => 'Storage Management';

  @override
  String get storageManagementSubtitle => 'Manage downloads and cache';

  @override
  String get otherSettings => 'Other';

  @override
  String get systemLog => 'System Log';

  @override
  String get systemLogSubtitle => 'View application run logs';

  @override
  String get aboutApp => 'About App';

  @override
  String get aboutAppSubtitle => 'Version and developer info';

  @override
  String get githubRepo => 'GitHub Repository';

  @override
  String get githubRepoSubtitle => 'View source code and report issues';

  @override
  String get language => 'Language';

  @override
  String get languageSubtitle => 'Switch application language';

  @override
  String get navSource => 'Source';

  @override
  String get navSourceTitle => 'ASMR Source';

  @override
  String get navPlayer => 'Player';

  @override
  String get navPlayerTitle => 'Player';

  @override
  String get navPlaylist => 'Playlist';

  @override
  String get navPlaylistTitle => 'Playlist';

  @override
  String get appDescription =>
      'An application focused on ASMR audio playback, providing you with a high-quality relaxation experience.';

  @override
  String developer(String name) {
    return 'Developer: $name';
  }

  @override
  String email(String address) {
    return 'Contact Email: $address';
  }

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get noContent => 'No content playing';

  @override
  String get goToSource => 'Go to \"Source\" page to select content';

  @override
  String get nowPlaying => 'Now Playing';

  @override
  String get favoriteTooltip => 'Favorite';

  @override
  String get shareTooltip => 'Share';

  @override
  String get moreTooltip => 'More';

  @override
  String get immersiveAudio => 'Immersive ASMR soundscapes, keep relaxed.';

  @override
  String get downloadAudio => 'Download Audio';

  @override
  String get downloadAll => 'Download all';

  @override
  String downloadAllConfirm(int count) {
    return 'Download all $count tracks?';
  }

  @override
  String downloadAllStarted(int count) {
    return 'Downloading $count tracks';
  }

  @override
  String get downloadAllAlready => 'All tracks are already downloaded';

  @override
  String get downloadAllDone => 'Nothing to download';

  @override
  String get clearAllCache => 'Clear All Cache';

  @override
  String get clearAllCacheConfirm => 'Clear all downloads of this source?';

  @override
  String clearAllCacheContent(String size) {
    return 'This deletes $size of downloaded files.';
  }

  @override
  String downloadUsage(String size) {
    return 'Downloads: $size';
  }

  @override
  String get clearDownloads => 'Clear';

  @override
  String get playQueue => 'Play Queue';

  @override
  String get clearQueue => 'Clear Queue';

  @override
  String tracksCount(int count) {
    return '$count tracks';
  }

  @override
  String get shuffleTooltip => 'Shuffle';

  @override
  String get repeatTooltip => 'Repeat';

  @override
  String get muteTooltip => 'Mute';

  @override
  String get unmuteTooltip => 'Unmute';

  @override
  String get createPlaylistTitle => 'Create New Playlist';

  @override
  String get playlistNameHint => 'Enter playlist name';

  @override
  String get playlistNameLabel => 'Name';

  @override
  String get cancel => 'Cancel';

  @override
  String get create => 'Create';

  @override
  String get playlistEmpty => 'Playlist is empty';

  @override
  String startPlaying(String name) {
    return 'Start playing: $name';
  }

  @override
  String get confirmDeleteTitle => 'Confirm Delete';

  @override
  String confirmDeleteContent(String name) {
    return 'Are you sure you want to delete playlist \"$name\"?';
  }

  @override
  String get delete => 'Delete';

  @override
  String get deleteSource => 'Delete source';

  @override
  String get deleteSourceConfirm => 'Delete this source?';

  @override
  String deleteSourceContent(String name) {
    return '\"$name\" will be removed from your source list.';
  }

  @override
  String get myPlaylists => 'My Playlists';

  @override
  String get currentQueue => 'Current Queue';

  @override
  String get customPlaylists => 'Custom Playlists';

  @override
  String get newPlaylist => 'New';

  @override
  String get noPlaylists => 'No playlists, click top right to create';

  @override
  String get tracksCountSuffix => ' tracks';

  @override
  String get playAllTooltip => 'Play All';

  @override
  String get deletePlaylistTooltip => 'Delete Playlist';

  @override
  String get clearQueueTooltip => 'Clear Queue';

  @override
  String get queueEmpty => 'Current queue is empty';

  @override
  String get searchHint => 'Search ASMR content...';

  @override
  String get searchTooltip => 'Search';

  @override
  String get sourceFilter => 'Source';

  @override
  String get allSources => 'All Sources';

  @override
  String get typeFilter => 'Type';

  @override
  String get allTypes => 'All Types';

  @override
  String get liveStream => 'Live Stream';

  @override
  String get fileVideo => 'File/Video';

  @override
  String get tagFilter => 'Tags';

  @override
  String get selectTag => 'Select tag to filter...';

  @override
  String get mySourcesTab => 'My Sources';

  @override
  String get searchResultsTab => 'Search Results';

  @override
  String get recommendationsTab => 'Recommendations';

  @override
  String get addSourceFab => 'Add Source';

  @override
  String get noSourcesFound => 'No sources found';

  @override
  String get clearFilterHint => 'Try clearing filters or adding new sources';

  @override
  String get searchContent => 'Search ASMR Audio Content';

  @override
  String get searchDescription => 'Support searching YouTube, Bilibili, etc.';

  @override
  String loadingFailed(String error) {
    return 'Loading failed: $error';
  }

  @override
  String get retry => 'Retry';

  @override
  String get noRecommendations => 'No recommendations';

  @override
  String get addSourceTitle => 'Add ASMR Source';

  @override
  String get sourceNameLabel => 'Name';

  @override
  String get sourceNameHint => 'Name this source';

  @override
  String get sourceTypeLabel => 'Source Type';

  @override
  String get localPathLabel => 'Local Path';

  @override
  String get localPathHint => 'Select file or folder';

  @override
  String get selectFile => 'Select File';

  @override
  String get selectFolder => 'Select Folder';

  @override
  String get urlPathLabel => 'URL / Path';

  @override
  String get urlPathHint => 'Enter link or file path';

  @override
  String get tagsLabel => 'Tags';

  @override
  String get tagsHint => 'Comma separated (e.g. ASMR, Sleep)';

  @override
  String get add => 'Add';

  @override
  String searchFailed(String error) {
    return 'Search failed: $error';
  }

  @override
  String get minutesSuffix => ' Minutes';

  @override
  String get hoursSuffix => 'h';

  @override
  String sleepTimerSet(int minutes) {
    return 'Sleep timer set to $minutes minutes';
  }

  @override
  String get confirm => 'OK';

  @override
  String get pathReset => 'Path reset to default';

  @override
  String get cacheManagementTitle => 'Cache Management';

  @override
  String get totalCacheSize => 'Total Cache Size';

  @override
  String get confirmClearTitle => 'Confirm Clear';

  @override
  String get confirmClearAllContent =>
      'Are you sure you want to clear all cache?';

  @override
  String get confirmClearSourceContent =>
      'Are you sure you want to clear cache for this source?';

  @override
  String get clear => 'Clear';

  @override
  String get cacheCleared => 'Cache cleared';

  @override
  String spaceUsed(String size) {
    return 'Space used: $size';
  }

  @override
  String get systemLogTitle => 'System Log';

  @override
  String get logsCopied => 'Logs copied to clipboard';

  @override
  String get sourceAccountManagementTitle => 'Source Account Management';

  @override
  String loggedIn(String user) {
    return 'Logged in: $user';
  }

  @override
  String get notLoggedIn => 'Not logged in';

  @override
  String get scanQrCodeLogin => 'Scan QR Code Login';

  @override
  String get cookieLogin => 'Cookie Login';

  @override
  String cookieLoginTitle(String source) {
    return '$source Cookie Login';
  }

  @override
  String get enterCookieHint => 'Enter Cookie';

  @override
  String get login => 'Login';

  @override
  String startPlayingCount(int count) {
    return 'Start playing: $count tracks';
  }

  @override
  String get addToPlaylist => 'Add to Playlist';

  @override
  String addedToQueue(int count) {
    return 'Added $count tracks to current queue';
  }

  @override
  String get noCustomPlaylists => 'No custom playlists';

  @override
  String addedToPlaylist(int count, String name) {
    return 'Added $count tracks to $name';
  }

  @override
  String createdAndAddedToPlaylist(int count, String name) {
    return 'Created and added $count tracks to $name';
  }

  @override
  String get refresh => 'Refresh';

  @override
  String get recordLive => 'Record live';

  @override
  String get recordFailed => 'Recording failed (live may be offline)';

  @override
  String get liveNow => 'Live now';

  @override
  String get liveOffline => 'Offline';

  @override
  String get recordings => 'Recordings';

  @override
  String get recordingInProgress => 'Recording…';

  @override
  String get stopRecording => 'Stop recording';

  @override
  String get playAll => 'Play All';

  @override
  String get addAll => 'Add All';

  @override
  String get tagManagement => 'Tag Management';

  @override
  String get addTag => 'Add Tag';

  @override
  String get tagNameHint => 'Enter tag name';

  @override
  String fileList(int count) {
    return 'File List ($count)';
  }

  @override
  String get noAudioFilesFound => 'No audio files found';

  @override
  String get bilibiliQrLogin => 'Bilibili QR Login';

  @override
  String get scanWithApp => 'Please scan with Bilibili App';

  @override
  String get sourceLocal => 'Local Files';

  @override
  String get unknownArtist => 'Unknown Artist';

  @override
  String get audioEffects => 'Audio Effects';

  @override
  String get effectNoiseReduction => 'Noise Reduction';

  @override
  String get effectNoiseReductionDesc =>
      'Reduces high frequency noise like static or fans.';

  @override
  String get effectSafeSleep => 'Safe Sleep';

  @override
  String get effectSafeSleepDesc =>
      'Softens audio and prevents sudden loud noises.';

  @override
  String get effectLimiter => 'Limiter';

  @override
  String get effectLimiterDesc =>
      'Prevents audio clipping and sudden loud peaks.';

  @override
  String get paramCutoff => 'Cutoff Frequency';

  @override
  String get paramCutoffDesc => 'Frequencies above this value will be reduced.';

  @override
  String get paramResonance => 'Resonance';

  @override
  String get paramResonanceDesc => 'Resonance of the filter.';

  @override
  String get paramEnableLimiter => 'Enable Limiter';

  @override
  String get paramEnableLimiterDesc => 'Prevents sudden loud noises.';

  @override
  String get paramSoftness => 'Softness (Cutoff)';

  @override
  String get paramSoftnessDesc => 'Lower values make audio softer.';

  @override
  String get volume => 'Volume';

  @override
  String get close => 'Close';

  @override
  String get sourceHelp => 'Help';

  @override
  String get downloadCompleted => 'Download completed';

  @override
  String get cachedTooltip => 'Cached - tap to remove';

  @override
  String downloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String get downloadManagement => 'Downloads';

  @override
  String get downloadManagementSubtitle => 'View background download tasks';

  @override
  String get importFromAccounts => 'Import from Accounts';

  @override
  String get importFromAccountsSubtitle =>
      'Auto-add favorites, followed channels and playlists from logged-in platforms';

  @override
  String get importing => 'Importing...';

  @override
  String importResult(int count) {
    return 'Imported %count% sources';
  }

  @override
  String get importEmpty => 'Nothing to import';

  @override
  String get importSelectTitle => 'Import Sources';

  @override
  String get importSelectHint => 'Choose a platform and type';

  @override
  String get importNotLoggedIn => 'Not logged in';

  @override
  String importSelected(int count) {
    return 'Import Selected (%count%)';
  }

  @override
  String get importNoSelection => 'Check something to import first';

  @override
  String get importBilibiliFavorites => 'Bilibili Favorites';

  @override
  String get importBilibiliFollowings => 'Bilibili Followings';

  @override
  String get importDouyuFollows => 'Douyu Follows';

  @override
  String get importAsmrOnePlaylists => 'asmr.one Playlists';

  @override
  String get importDlsiteLibrary => 'DLsite Purchased';

  @override
  String get downloadsTab => 'Downloads';

  @override
  String get watchRoomsTab => 'Live watch';

  @override
  String get watchRoomsHint =>
      'Add live rooms: the app probes them periodically even without playback and records automatically once they go live, stopping when they go offline.';

  @override
  String get noWatchRooms => 'No watched rooms yet. Add one below.';

  @override
  String get addRoom => 'Add room';

  @override
  String get addRoomFailed => 'Cannot recognize this live URL';

  @override
  String get roomRecording => 'Recording';

  @override
  String get roomWatching => 'Watching';

  @override
  String get roomPaused => 'Paused';

  @override
  String liveFor(Object time) {
    return 'Live for $time';
  }

  @override
  String recordingFor(Object time) {
    return 'Recording $time';
  }

  @override
  String get playbackSettings => 'Playback';

  @override
  String get audioQuality => 'Audio quality';

  @override
  String get audioQualitySubtitle =>
      'Quality for remote on-demand media (some require login)';

  @override
  String get qualityAuto => 'Auto (highest)';

  @override
  String get scanWithDouyuApp => 'Scan with the Douyu app';

  @override
  String get renameSource => 'Rename source';

  @override
  String get renameSourceHint => 'Enter a new name';

  @override
  String get accountLogin => 'Account login';

  @override
  String accountLoginTitle(Object source) {
    return 'Login $source';
  }

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get removeFromQueue => 'Remove from queue';

  @override
  String get downloadStarted => 'Download started';

  @override
  String get liveEnded => 'The stream has ended';

  @override
  String get navDownloads => 'Downloads';

  @override
  String get navDownloadsTitle => 'Downloads';

  @override
  String get noDownloads => 'No download tasks';

  @override
  String get downloadQueued => 'Queued';

  @override
  String get downloading => 'Downloading';

  @override
  String get downloadCompletedShort => 'Done';

  @override
  String get downloadFailedShort => 'Failed';

  @override
  String get downloadCanceled => 'Canceled';

  @override
  String get downloadOffHint =>
      'Download format is Off, enable it in Settings first';

  @override
  String get buffering => 'Buffering…';

  @override
  String get playbackError => 'Playback failed';

  @override
  String get loading => 'Loading…';

  @override
  String get networkError =>
      'Network error, please check your connection and retry';

  @override
  String get toggleDesktopLayout => 'Toggle Desktop Layout';

  @override
  String launchUrlFailed(String url) {
    return 'Could not launch $url';
  }

  @override
  String get unknownUser => 'Unknown';

  @override
  String get webLogin => 'Web Login';
}
