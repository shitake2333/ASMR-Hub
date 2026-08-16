# ASMR Hub

**简体中文** | [English](README.en.md)

ASMR Hub 是一个跨平台 Flutter 应用，聚合并播放来自多平台的 ASMR 内容，
支持下载与直播录制。

## 功能特性

- **多源聚合**：本地文件、YouTube、Bilibili、DLsite、斗鱼、asmr.one、Twitch
- **播放器**：media_kit（libmpv）驱动，支持直播流（FLV/HLS）、防盗链请求头、lavfi 音效滤镜、断点续播
- **播放列表**：跨源混合、循环/随机、音质切换
- **下载与直播录制**：并发下载、限速、缓存格式（MP3/WAV/FLAC）；多房间看门狗自动录制
- **账号导入**：两步向导，从已登录平台批量导入（见 [账号导入](#账号导入)）
- **睡眠定时器**、主题（浅/深/系统）、简中/英文界面
- **跨平台**：Windows / Linux / macOS / Android

## 支持的源

| 源 | 内容类型 | 直播 | 录制/监控 | 登录方式 |
| :--- | :--- | :--- | :--- | :--- |
| **本地文件** | 音频文件 / 文件夹 | ❌ | ❌ | 无需登录 |
| **Bilibili** | 单视频 / 合集·剧集 / 收藏夹 | ✅ 直播间 | ✅ | 扫码 / 浏览器 / Cookie |
| **Douyu** | 直播间 | ✅ | ✅ | 扫码 / Cookie |
| **YouTube** | 视频 / 播放列表（仅音频） | ❌ | ❌ | 浏览器 / Cookie（可选） |
| **DLsite** | 作品页 RJ{id}（多音轨） | ❌ | ❌ | 账号密码 / Cookie |
| **asmr.one** | 作品页 / 播放列表 | ❌ | ❌ | 账号密码 / Cookie |
| **Twitch** | 主播频道（audio-only） | ✅ | ✅ | 匿名（可选 Cookie） |

### 各源详细说明

**本地文件** — 直接添加本机音频文件或文件夹（mp3/wav/flac/m4a/ogg 等），
无需网络和登录；直播录制产生的文件也可直接添加。

**Bilibili（哔哩哔哩）** — 支持的链接：
- 单个视频：`https://www.bilibili.com/video/BVxxxxxxxxxx`
- 合集 / 剧集（多P）：`https://www.bilibili.com/bangumi/...` 或合集页
- 收藏夹：`https://space.bilibili.com/{uid}/favlist?fid={fid}`
- 直播房间：`https://live.bilibili.com/{roomId}`（可收听、可录制、可后台监控）
- `b23.tv` 短链自动解析

> 高清音频需要登录（推荐扫码登录）；Bilibili CDN 有防盗链，下载会自动携带
> 浏览器 UA + Referer。

**Douyu（斗鱼）** — 直播房间：`https://www.douyu.com/{roomId}`（如 `/92020`）。
开播时可收听、录制、后台监控；扫码登录后可获得完整房间列表与高清画质。
部分直播间存在地域/鉴权限制，无法播放时会提示；主播下播后房间卡片会显示
「直播已下播」。

**YouTube** — 单个视频：`https://www.youtube.com/watch?v={id}`、
短链 `https://youtu.be/{id}`；播放列表 `https://www.youtube.com/playlist?list={id}`
会以多曲目方式加入。仅提取音频（不播放画面）；浏览器/Cookie 登录可访问会员
或受限内容。

**DLsite** — 作品页：`https://www.dlsite.com/maniax/work/=/product_id/RJ{id}.html`，
作品以多音轨播放列表加入。需要登录（推荐「浏览器登录」）才能播放已购买的作品；
未购买的作品无法播放。

**asmr.one** — 作品页：`https://asmr.one/work/{id}`（多音轨）、
播放列表：`https://asmr.one/playlist?id={uuid}`。播放列表需要登录
（用户名/密码，免费注册无需邮箱）。

**Twitch** — 频道页：`https://www.twitch.tv/{channel}`，匿名即可收听公开频道的
音频流（audio-only），可录制、可后台监控；主播下播后显示「直播已下播」。

> 直播流（FLV/HLS）通过 libmpv（media_kit）播放，原生支持 FLV、AAC、HLS 等格式；
> 「录制/监控」指将直播转码存为本地文件并支持后台多房间看门狗。

## 账号导入

源页 →「从账号导入」打开两步导入向导：

1. **第一步：选择平台与类型**（未登录的平台显示锁定标记）
2. **第二步：勾选条目并批量导入**（可多选）

支持的导入分组：

| 分组 | 内容 | 登录要求 |
| :--- | :--- | :--- |
| Bilibili 收藏夹 | 收藏夹列表（按收藏夹导入视频合集） | B站登录 |
| Bilibili 关注主播 | 关注的直播间（`live.bilibili.com/{mid}`） | B站登录 |
| asmr.one 播放列表 | 我喜欢的音声 / 我标记的音声 | asmr.one 登录 |
| 斗鱼关注 | 关注的直播间 | 斗鱼登录 |
| DLsite 已购 | 已购买的作品 | DLsite 登录 |

## 安装

从 [Releases](https://github.com/shitake2333/ASMR-Hub/releases) 下载对应平台包
（由 `.github/workflows/release.yml` 在打 tag 时自动构建并上传）：

- **Windows**：`asmr_hub-windows-x64.zip`（解压即用）
- **Android**：`asmr_hub-android.apk`
- **Linux**：`asmr_hub-linux-x64.tar.gz`
- **macOS**：`asmr_hub-macos-arm64.zip`（Apple Silicon；Intel Mac 请从源码构建）

## 从源码构建

### 环境

- Flutter 3.47+（Dart 3.10+）
- Windows 构建：Visual Studio（MSVC）+ MinGW-w64 gcc（编译 FFmpeg 桥）
- Linux 构建：GTK 3 开发包 + FFmpeg 开发库（libavformat-dev 等）+
  libmpv-dev + libayatana-appindicator3-dev
- macOS 构建：Xcode + Homebrew FFmpeg
- Android 构建：Android SDK/NDK（默认 NDK 28.2.13676358）

### Windows

```powershell
# 获取 FFmpeg DLL、编译 ffmpeg_bridge.dll（MinGW）、flutter build、
# 打包 dist/asmr_hub-windows-x64.zip
powershell -File tool/build_windows.ps1 -Release
```

### Linux

```bash
# 编译 FFmpeg 桥、flutter build、把系统 libmpv 打进 bundle（自包含）、
# 打包 dist/asmr_hub-linux-x64.tar.gz
# 依赖：libgtk-3-dev ninja-build clang cmake pkg-config + FFmpeg 开发库 + libmpv-dev
bash tool/build_linux.sh
```

### macOS

```bash
# 编译 FFmpeg 桥、flutter build、把 FFmpeg dylib 打进 .app 并重签名、
# 打包 dist/asmr_hub-macos-<arch>.zip
# 依赖：Xcode + Homebrew FFmpeg
bash tool/build_macos.sh
```

### Android

```bash
# （可选）NDK 交叉编译 FFmpeg 7.1 到 jniLibs（没有它 APK 也能构建，
# 只是下载/录音功能不可用）、flutter build apk、复制 dist/asmr_hub-android.apk
bash tool/build_android.sh
```

> 各平台均使用 media_kit 捆绑的 libmpv，已实测支持 lavfi 音效滤镜，无需额外替换。

## 项目结构

```
lib/
├── main.dart                 # 入口：MediaKit 初始化、Provider 装配、主 Tab 壳
├── pages/                    # UI 页面（源列表/详情、播放器、播放列表、下载、
│                             #   设置、导入向导、Web 登录…）
├── providers/                # 状态管理（AudioPlayerProvider、PlaylistProvider、
│                             #   ThemeProvider、EffectsProvider、AuthProvider…）
├── services/                 # 业务服务
│   ├── mpv_player_engine.dart    # media_kit 播放引擎封装（懒加载 Player）
│   ├── audio_provider.dart       # 播放状态机：路由、循环/随机、睡眠定时、持久化
│   ├── download_manager.dart     # 并发下载 + 限速 + 缓存格式（经 FFmpeg 桥转码）
│   ├── live_recorder.dart        # 直播录制（FFmpeg 桥）
│   ├── live_watch_manager.dart   # 多房间后台看门狗
│   ├── source_import_service.dart# 账号导入（收藏夹/关注/播放列表/已购）
│   └── ffmpeg/                   # FFmpeg FFI 桥的 Dart 封装（解码/编码）
├── sources/                  # 各平台源实现
│   ├── base/                     # BaseAudioSource / SourceAuth / SourceScraper
│   ├── bilibili/ douyu/ youtube/ dlsite/ asmrone/ twitch/ local/
├── models/                   # 数据模型（AudioTrack、ASMRSource、账号数据…）
├── effects/                  # 音效滤镜链生成（lavfi）
└── l10n/                     # ARB 本地化 + 生成的 app_localizations

third_party/ffmpeg/           # FFmpeg 桥 C 源码 + 提交的头文件（二进制构建期获取）
tool/                         # 各平台构建脚本（见「从源码构建」）
.github/workflows/            # CI + 发布工作流
test/  test_network/          # 离线测试 / 联网测试
```

## 开发

### 本地化

`lib/l10n/` 下维护 ARB 文件（`app_en.arb` / `app_zh.arb`），修改后运行：

```bash
flutter gen-l10n
```

### 添加新源

1. 在 `lib/sources/<name>/` 创建实现（继承 `BaseAudioSource`，
   提供 `SourceAuth` 与 `SourceScraper`）
2. 在 `lib/services/audio_source_manager.dart` 的 `_registerSources` 注册
3. 在 `_loadConfigs` 添加默认配置
4. （可选）在 `lib/services/source_import_service.dart` 添加账号导入支持

### 测试

- `test/`：离线单元/组件测试（CI 运行 `flutter test` 时只跑这个目录）
- `test_network/`：依赖真实网络/外部状态的测试（B站、斗鱼、YouTube API 等），
  本地手动运行：`flutter test test_network`

### 音频架构

- **播放**：media_kit（libmpv）—— 解码、流式、直播、headers、lavfi 滤镜
- **下载/录音转码**：FFmpeg 桥（`third_party/ffmpeg/ffmpeg_bridge.c`，纯 C FFI）
  - Windows：`ffmpeg_bridge.dll` + avcodec-61/avformat-61/avutil-59/swresample-5，
    由 `tool/fetch_ffmpeg_windows.ps1` 获取/编译（二进制不提交 git；
    FFmpeg 头文件 `third_party/ffmpeg/include/` 提交在仓库里）
  - Linux：`libffmpeg_bridge.so`，`tool/build_ffmpeg_bridge_posix.sh` 链接系统 FFmpeg，
    构建时由 CMake 打进 bundle 的 `lib/`
  - macOS：`libffmpeg_bridge.dylib`，同样由 posix 脚本编译，
    `tool/bundle_macos.sh` 把 dylib 拷入 .app 的 Frameworks 并重签名
  - Android：`tool/build_ffmpeg_android.sh` 用 NDK 编译 FFmpeg 7.1 到 jniLibs，
    Gradle CMake 再编译 `libffmpeg_bridge.so`
- **音效**：mpv `af` 滤镜链（lavfi：alimiter / lowpass），由 `EffectsProvider` 生成
- **音量模型**：全链路 0-1（持久化 0-1），仅在引擎边界换算为 mpv 的 0-100；
  音量在每次调整时立即持久化

## CI / 发布

GitHub Actions 工作流（仓库地址 `git@github.com:shitake2333/ASMR-Hub.git`）：

- `.github/workflows/ci.yml`：push/PR 到 main 时运行 `flutter analyze` + `flutter test`
  （离线测试集）+ 格式检查
- `.github/workflows/release.yml`：推送 `v*` tag 时构建 Windows/Linux/macOS(arm64+x64)/
  Android 包，并自动上传到 GitHub Releases：

```bash
git tag v1.0.0
git push origin v1.0.0
```

## 许可证

MIT License — 见 [LICENSE](LICENSE)。
