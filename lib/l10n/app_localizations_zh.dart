// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get settingsTitle => '设置';

  @override
  String get accountSettings => '账号设置';

  @override
  String get appearanceSettings => '外观设置';

  @override
  String get darkMode => '深色模式';

  @override
  String get darkModeSubtitle => '切换应用主题';

  @override
  String get themeColor => '主题颜色';

  @override
  String get themeColorSubtitle => '选择应用主色调';

  @override
  String get fontSettings => '字体设置';

  @override
  String get fontSettingsSubtitle => '调整字体样式和大小';

  @override
  String get fontFamily => '字体系列';

  @override
  String get defaultFont => '默认';

  @override
  String get fontSize => '字体大小';

  @override
  String get systemDefault => '系统默认';

  @override
  String get playSettings => '播放设置';

  @override
  String get sourceAccountManagement => '源账号管理';

  @override
  String get sourceAccountManagementSubtitle => '管理各平台账号登录状态';

  @override
  String get autoPlay => '自动播放';

  @override
  String get autoPlaySubtitle => '歌曲结束后自动播放下一首';

  @override
  String get sleepTimer => '睡眠定时器';

  @override
  String sleepTimerSubtitle(int minutes) {
    return '$minutes 分钟后停止播放';
  }

  @override
  String get sleepTimerActiveTitle => '定时关闭已开启';

  @override
  String sleepTimerEndsAt(Object time) {
    return '将在 $time 停止播放';
  }

  @override
  String sleepTimerRemaining(Object time) {
    return '剩余 $time';
  }

  @override
  String get sleepTimerPresetLabel => '快捷预设';

  @override
  String get sleepTimerCustomLabel => '自定义';

  @override
  String get sleepTimerCustomHint => '分钟 (1-480)';

  @override
  String get sleepTimerOff => '关闭定时器';

  @override
  String get sleepTimerOffHint => '定时结束后停止播放';

  @override
  String get sleepTimerPlayUntilEnd => '当前曲目结束后停止';

  @override
  String get sleepTimerSetStart => '启动定时器';

  @override
  String get smartSleepDetection => '智能睡眠检测';

  @override
  String get smartSleepDetectionSubtitle => '检测到入睡后停止播放';

  @override
  String get notificationSettings => '通知设置';

  @override
  String get pushNotification => '推送通知';

  @override
  String get pushNotificationSubtitle => '接收新内容和更新通知';

  @override
  String get storageSettings => '存储设置';

  @override
  String get cachePath => '缓存路径';

  @override
  String get cacheFormat => '缓存格式';

  @override
  String get cacheFormatOffSubtitle => '不缓存解码后的音频';

  @override
  String get cacheFormatWavSubtitle => 'WAV 无损（约 10 MB/分钟，可拖动进度）';

  @override
  String get cacheFormatMp3Subtitle => 'MP3 压缩（约 1.4 MB/分钟，推荐）';

  @override
  String get cacheFormatFlacSubtitle => 'FLAC 无损（约 5 MB/分钟）';

  @override
  String get downloadSettings => '下载设置';

  @override
  String get downloadSettingsSubtitle => '下载速率、并发线程与缓存格式';

  @override
  String get maxDownloadRate => '最大下载速率';

  @override
  String get maxDownloadRateSubtitle => '0 表示不限速';

  @override
  String get maxDownloadRateUnit => 'KB/s';

  @override
  String get maxDownloadThreads => '最大下载线程';

  @override
  String get maxDownloadThreadsSubtitle => '同时进行的下载任务数';

  @override
  String get downloadPath => '下载路径';

  @override
  String get resetPath => '重置路径';

  @override
  String get resetPathSubtitle => '恢复默认存储位置';

  @override
  String get storageManagement => '存储管理';

  @override
  String get storageManagementSubtitle => '管理下载内容和缓存';

  @override
  String get otherSettings => '其他';

  @override
  String get systemLog => '系统日志';

  @override
  String get systemLogSubtitle => '查看应用运行日志';

  @override
  String get aboutApp => '关于应用';

  @override
  String get aboutAppSubtitle => '版本信息和开发者信息';

  @override
  String get githubRepo => 'GitHub 仓库';

  @override
  String get githubRepoSubtitle => '查看源码和反馈问题';

  @override
  String get language => '语言';

  @override
  String get languageSubtitle => '切换应用语言';

  @override
  String get navSource => '源';

  @override
  String get navSourceTitle => 'ASMR 源';

  @override
  String get navPlayer => '播放器';

  @override
  String get navPlayerTitle => '播放器';

  @override
  String get navPlaylist => '列表';

  @override
  String get navPlaylistTitle => '播放列表';

  @override
  String get appDescription => '一款专注于ASMR音频播放的应用，为您提供高质量的放松体验。';

  @override
  String developer(String name) {
    return '开发者：$name';
  }

  @override
  String email(String address) {
    return '联系邮箱：$address';
  }

  @override
  String get settingsTooltip => '设置';

  @override
  String get noContent => '暂无播放内容';

  @override
  String get goToSource => '去\"源\"页面选择内容播放吧';

  @override
  String get nowPlaying => '正在播放';

  @override
  String get favoriteTooltip => '收藏';

  @override
  String get shareTooltip => '分享';

  @override
  String get moreTooltip => '更多';

  @override
  String get immersiveAudio => '沉浸式助眠音景，保持放松节奏。';

  @override
  String get downloadAudio => '下载音频';

  @override
  String get downloadAll => '全部缓存';

  @override
  String downloadAllConfirm(int count) {
    return '下载全部 $count 个音轨？';
  }

  @override
  String downloadAllStarted(int count) {
    return '正在下载 $count 个音轨';
  }

  @override
  String get downloadAllAlready => '所有音轨都已缓存';

  @override
  String get downloadAllDone => '没有可下载的音轨';

  @override
  String get clearAllCache => '清除所有缓存';

  @override
  String get clearAllCacheConfirm => '清除该源的全部下载文件？';

  @override
  String clearAllCacheContent(String size) {
    return '将删除 $size 的已下载文件。';
  }

  @override
  String downloadUsage(String size) {
    return '已占用：$size';
  }

  @override
  String get clearDownloads => '清除';

  @override
  String get playQueue => '播放队列';

  @override
  String get clearQueue => '清空列表';

  @override
  String tracksCount(int count) {
    return '$count 首待播';
  }

  @override
  String get shuffleTooltip => '随机播放';

  @override
  String get repeatTooltip => '循环播放';

  @override
  String get muteTooltip => '静音';

  @override
  String get unmuteTooltip => '取消静音';

  @override
  String get createPlaylistTitle => '创建新播放列表';

  @override
  String get playlistNameHint => '输入列表名称';

  @override
  String get playlistNameLabel => '名称';

  @override
  String get cancel => '取消';

  @override
  String get create => '创建';

  @override
  String get playlistEmpty => '播放列表为空';

  @override
  String startPlaying(String name) {
    return '开始播放: $name';
  }

  @override
  String get confirmDeleteTitle => '确认删除';

  @override
  String confirmDeleteContent(String name) {
    return '确定要删除播放列表 \"$name\" 吗？';
  }

  @override
  String get delete => '删除';

  @override
  String get deleteSource => '删除源';

  @override
  String get deleteSourceConfirm => '删除这个源？';

  @override
  String deleteSourceContent(String name) {
    return '将从源列表中移除 \"$name\"。';
  }

  @override
  String get myPlaylists => '我的列表';

  @override
  String get currentQueue => '当前队列';

  @override
  String get customPlaylists => '自定义列表';

  @override
  String get newPlaylist => '新建';

  @override
  String get noPlaylists => '暂无播放列表，点击右上角新建';

  @override
  String get tracksCountSuffix => ' 首歌曲';

  @override
  String get playAllTooltip => '播放全部';

  @override
  String get deletePlaylistTooltip => '删除列表';

  @override
  String get clearQueueTooltip => '清空队列';

  @override
  String get queueEmpty => '当前队列为空';

  @override
  String get searchHint => '搜索ASMR内容...';

  @override
  String get searchTooltip => '搜索';

  @override
  String get sourceFilter => '来源';

  @override
  String get allSources => '全部来源';

  @override
  String get typeFilter => '类型';

  @override
  String get allTypes => '全部类型';

  @override
  String get liveStream => '直播流';

  @override
  String get fileVideo => '文件/视频';

  @override
  String get tagFilter => '标签';

  @override
  String get selectTag => '选择标签筛选...';

  @override
  String get mySourcesTab => '我的源';

  @override
  String get searchResultsTab => '搜索结果';

  @override
  String get recommendationsTab => '推荐';

  @override
  String get addSourceFab => '添加源';

  @override
  String get noSourcesFound => '没有找到符合条件的源';

  @override
  String get clearFilterHint => '尝试清除筛选或添加新源';

  @override
  String get searchContent => '搜索ASMR音频内容';

  @override
  String get searchDescription => '支持搜索YouTube、哔哩哔哩等平台内容';

  @override
  String loadingFailed(String error) {
    return '加载失败: $error';
  }

  @override
  String get retry => '重试';

  @override
  String get noRecommendations => '暂无推荐内容';

  @override
  String get addSourceTitle => '添加 ASMR 源';

  @override
  String get sourceNameLabel => '名称';

  @override
  String get sourceNameHint => '给这个源起个名字';

  @override
  String get sourceTypeLabel => '来源类型';

  @override
  String get localPathLabel => '本地路径';

  @override
  String get localPathHint => '请选择文件或文件夹';

  @override
  String get selectFile => '选择文件';

  @override
  String get selectFolder => '选择文件夹';

  @override
  String get urlPathLabel => 'URL / 路径';

  @override
  String get urlPathHint => '输入链接或文件路径';

  @override
  String get tagsLabel => '标签';

  @override
  String get tagsHint => '用逗号分隔 (例如: ASMR, 助眠)';

  @override
  String get add => '添加';

  @override
  String searchFailed(String error) {
    return '搜索失败: $error';
  }

  @override
  String get minutesSuffix => ' 分钟';

  @override
  String get hoursSuffix => ' 小时';

  @override
  String sleepTimerSet(int minutes) {
    return '睡眠定时器设置为 $minutes 分钟';
  }

  @override
  String get confirm => '确定';

  @override
  String get pathReset => '路径已重置为默认值';

  @override
  String get cacheManagementTitle => '缓存管理';

  @override
  String get totalCacheSize => '总缓存大小';

  @override
  String get confirmClearTitle => '确认清除';

  @override
  String get confirmClearAllContent => '确定要清除所有缓存吗？';

  @override
  String get confirmClearSourceContent => '确定要清除该源的缓存吗？';

  @override
  String get clear => '清除';

  @override
  String get cacheCleared => '缓存已清除';

  @override
  String spaceUsed(String size) {
    return '占用空间: $size';
  }

  @override
  String get systemLogTitle => '系统日志';

  @override
  String get logsCopied => '日志已复制到剪贴板';

  @override
  String get sourceAccountManagementTitle => '源账号管理';

  @override
  String loggedIn(String user) {
    return '已登录: $user';
  }

  @override
  String get notLoggedIn => '未登录';

  @override
  String get scanQrCodeLogin => '扫码登录';

  @override
  String get cookieLogin => 'Cookie登录';

  @override
  String cookieLoginTitle(String source) {
    return '$source Cookie登录';
  }

  @override
  String get enterCookieHint => '请输入Cookie';

  @override
  String get login => '登录';

  @override
  String startPlayingCount(int count) {
    return '开始播放: $count 首';
  }

  @override
  String get addToPlaylist => '添加到播放列表';

  @override
  String addedToQueue(int count) {
    return '已添加 $count 首到当前队列';
  }

  @override
  String get noCustomPlaylists => '暂无自定义列表';

  @override
  String addedToPlaylist(int count, String name) {
    return '已添加 $count 首到 $name';
  }

  @override
  String createdAndAddedToPlaylist(int count, String name) {
    return '已创建并添加 $count 首到 $name';
  }

  @override
  String get refresh => '刷新';

  @override
  String get recordLive => '录制直播';

  @override
  String get recordFailed => '录制失败（直播可能未开播）';

  @override
  String get liveNow => '直播中';

  @override
  String get liveOffline => '未开播';

  @override
  String get recordings => '录播';

  @override
  String get recordingInProgress => '录制中…';

  @override
  String get stopRecording => '停止录制';

  @override
  String get playAll => '全部播放';

  @override
  String get addAll => '全部加入';

  @override
  String get tagManagement => '标签管理';

  @override
  String get addTag => '添加标签';

  @override
  String get tagNameHint => '输入标签名称';

  @override
  String fileList(int count) {
    return '文件列表 ($count)';
  }

  @override
  String get noAudioFilesFound => '未找到音频文件';

  @override
  String get bilibiliQrLogin => '哔哩哔哩扫码登录';

  @override
  String get scanWithApp => '请使用哔哩哔哩App扫码';

  @override
  String get sourceLocal => '本地文件';

  @override
  String get unknownArtist => '未知艺术家';

  @override
  String get audioEffects => '音效';

  @override
  String get effectNoiseReduction => '降噪';

  @override
  String get effectNoiseReductionDesc => '减少如静电或风扇等高频噪音。';

  @override
  String get effectSafeSleep => '安全睡眠';

  @override
  String get effectSafeSleepDesc => '柔化音频并防止突发大音量。';

  @override
  String get effectLimiter => '限制器';

  @override
  String get effectLimiterDesc => '防止音频削波和突发大音量峰值。';

  @override
  String get paramCutoff => '截止频率';

  @override
  String get paramCutoffDesc => '高于此值的频率将被衰减。';

  @override
  String get paramResonance => '共振';

  @override
  String get paramResonanceDesc => '滤波器的共振值。';

  @override
  String get paramEnableLimiter => '启用限制器';

  @override
  String get paramEnableLimiterDesc => '防止突发大音量。';

  @override
  String get paramSoftness => '柔和度 (截止频率)';

  @override
  String get paramSoftnessDesc => '数值越低，声音越柔和。';

  @override
  String get volume => '音量';

  @override
  String get close => '关闭';

  @override
  String get sourceHelp => '帮助';

  @override
  String get downloadCompleted => '下载完成';

  @override
  String get cachedTooltip => '已缓存 - 点击移除';

  @override
  String downloadFailed(String error) {
    return '下载失败：$error';
  }

  @override
  String get downloadManagement => '下载管理';

  @override
  String get downloadManagementSubtitle => '查看正在后台执行的下载任务';

  @override
  String get importFromAccounts => '从账号导入源';

  @override
  String get importFromAccountsSubtitle => '自动添加已登录平台的收藏夹、关注主播和播放列表';

  @override
  String get importing => '正在导入...';

  @override
  String importResult(int count) {
    return '已导入 %count% 个源';
  }

  @override
  String get importEmpty => '没有可导入的内容';

  @override
  String get importSelectTitle => '导入源';

  @override
  String get importSelectHint => '选择来源和类型';

  @override
  String get importNotLoggedIn => '未登录';

  @override
  String importSelected(int count) {
    return '导入选中 (%count%)';
  }

  @override
  String get importNoSelection => '请先勾选要导入的内容';

  @override
  String get importBilibiliFavorites => 'B站收藏夹';

  @override
  String get importBilibiliFollowings => 'B站关注主播';

  @override
  String get importDouyuFollows => '斗鱼关注主播';

  @override
  String get importAsmrOnePlaylists => 'asmr.one 播放列表';

  @override
  String get importDlsiteLibrary => 'DLsite 已购作品';

  @override
  String get downloadsTab => '下载任务';

  @override
  String get watchRoomsTab => '录播监控';

  @override
  String get watchRoomsHint =>
      '添加直播间后，即使没有播放，软件也会定时检测开播状态；开播后自动开始后台录制，下播后自动停止。';

  @override
  String get noWatchRooms => '暂无监控的直播间，点击下方按钮添加';

  @override
  String get addRoom => '添加直播间';

  @override
  String get addRoomFailed => '无法识别该直播链接';

  @override
  String get roomRecording => '录制中';

  @override
  String get roomWatching => '监控中';

  @override
  String get roomPaused => '已暂停';

  @override
  String liveFor(Object time) {
    return '已开播 $time';
  }

  @override
  String recordingFor(Object time) {
    return '录制中 $time';
  }

  @override
  String get playbackSettings => '播放设置';

  @override
  String get audioQuality => '音频质量';

  @override
  String get audioQualitySubtitle => '远程点播的音频质量（部分质量需要登录）';

  @override
  String get qualityAuto => '自动（最高）';

  @override
  String get scanWithDouyuApp => '请使用斗鱼App扫码';

  @override
  String get renameSource => '重命名源';

  @override
  String get renameSourceHint => '输入新的名称';

  @override
  String get accountLogin => '账号登录';

  @override
  String accountLoginTitle(Object source) {
    return '登录 $source';
  }

  @override
  String get username => '用户名';

  @override
  String get password => '密码';

  @override
  String get removeFromQueue => '从队列移除';

  @override
  String get downloadStarted => '已开始下载';

  @override
  String get liveEnded => '直播已下播';

  @override
  String get navDownloads => '下载';

  @override
  String get navDownloadsTitle => '下载管理';

  @override
  String get noDownloads => '暂无下载任务';

  @override
  String get downloadQueued => '等待中';

  @override
  String get downloading => '下载中';

  @override
  String get downloadCompletedShort => '已完成';

  @override
  String get downloadFailedShort => '失败';

  @override
  String get downloadCanceled => '已取消';

  @override
  String get downloadOffHint => '下载格式为 Off，请先在设置中开启';

  @override
  String get buffering => '缓冲中…';

  @override
  String get playbackError => '播放失败';

  @override
  String get loading => '加载中…';

  @override
  String get networkError => '网络错误，请检查网络后重试';

  @override
  String get toggleDesktopLayout => '切换桌面布局';

  @override
  String launchUrlFailed(String url) {
    return '无法打开链接 $url';
  }

  @override
  String get unknownUser => '未知用户';

  @override
  String get webLogin => '网页登录';
}
