# ASMR Hub

[中文](README.md) | **English**

ASMR Hub is a cross-platform Flutter app that aggregates and plays ASMR content
from multiple platforms, with download and live-recording support.

## Features

- **Multi-source aggregation**: local files, YouTube, Bilibili, DLsite, Douyu, asmr.one, Twitch
- **Player**: media_kit (libmpv) with live streams (FLV/HLS), anti-hotlink request headers, lavfi effects, resume playback
- **Playlists**: mixed across sources, loop/shuffle, quality switching
- **Download & live recording**: concurrent downloads, rate limiting, cache formats (MP3/WAV/FLAC); multi-room watchdog auto-recording
- **Account import**: two-step wizard to bulk-import from logged-in platforms (see [Account Import](#account-import))
- **Sleep timer**, theme (light/dark/system), zh/en UI
- **Cross-platform**: Windows / Linux / macOS / Android

## Supported Sources

| Source | Content types | Live | Record/watch | Login |
| :--- | :--- | :--- | :--- | :--- |
| **Local files** | Audio files / folders | ❌ | ❌ | None |
| **Bilibili** | Single video / season·collection / favorites | ✅ Rooms | ✅ | QR / Browser / Cookie |
| **Douyu** | Live rooms | ✅ | ✅ | QR / Cookie |
| **YouTube** | Videos / playlists (audio only) | ❌ | ❌ | Browser / Cookie (optional) |
| **DLsite** | Work pages RJ{id} (multi-track) | ❌ | ❌ | Username / password / Cookie |
| **asmr.one** | Work pages / playlists | ❌ | ❌ | Username / password / Cookie |
| **Twitch** | Channels (audio-only) | ✅ | ✅ | Anonymous (optional Cookie) |

### Per-source details

**Local files** — add local audio files or folders directly
(mp3/wav/flac/m4a/ogg, …). No network or login required; recordings produced by
live recording can be added as well.

**Bilibili** — supported links:
- Single video: `https://www.bilibili.com/video/BVxxxxxxxxxx`
- Season / multi-P collection: `https://www.bilibili.com/bangumi/...` or collection page
- Favorites: `https://space.bilibili.com/{uid}/favlist?fid={fid}`
- Live room: `https://live.bilibili.com/{roomId}` (listen, record, background watch)
- `b23.tv` short links are resolved automatically

> High-quality audio requires login (QR login recommended); Bilibili's CDN is
> anti-hotlink protected, so downloads automatically attach a browser UA + Referer.

**Douyu** — live rooms: `https://www.douyu.com/{roomId}` (e.g. `/92020`).
Listen, record and background-watch while live; QR login unlocks the full room
list and high quality. Some rooms are region/DRM restricted and will show a
notice if unplayable; room cards show "Stream ended" when the host goes offline.

**YouTube** — single videos: `https://www.youtube.com/watch?v={id}`,
short links `https://youtu.be/{id}`; playlists
`https://www.youtube.com/playlist?list={id}` are added as multiple tracks.
Audio only (no video); browser/cookie login can access member-only or
restricted content.

**DLsite** — work pages:
`https://www.dlsite.com/maniax/work/=/product_id/RJ{id}.html`, added as a
multi-track playlist. Login is required (browser login recommended) to play
purchased works; unpurchased works cannot be played.

**asmr.one** — work pages: `https://asmr.one/work/{id}` (multi-track),
playlists: `https://asmr.one/playlist?id={uuid}`. Playlists require login
(username/password; free registration, no e-mail needed).

**Twitch** — channel pages: `https://www.twitch.tv/{channel}`. Public channels
can be listened to anonymously (audio-only), with recording and background
watch; "Stream ended" is shown when the streamer goes offline.

> Live streams (FLV/HLS) are played through libmpv (media_kit), which natively
> handles FLV, AAC, HLS, etc. "Record/watch" means transcoding a live stream to
> a local file plus a background multi-room watchdog.

## Account Import

Source page → "Import from accounts" opens the two-step import wizard:

1. **Step 1 — pick platform & type** (unauthenticated platforms show a lock icon)
2. **Step 2 — check items and import in bulk** (multi-select supported)

Supported import groups:

| Group | Content | Login required |
| :--- | :--- | :--- |
| Bilibili favorites | Favorite list (import a favorite as a video collection) | Bilibili |
| Bilibili followings | Followed live rooms (`live.bilibili.com/{mid}`) | Bilibili |
| asmr.one playlists | Liked works / marked works | asmr.one |
| Douyu follows | Followed live rooms | Douyu |
| DLsite purchased | Purchased works | DLsite |

## Installation

Download the package for your platform from
[Releases](https://github.com/shitake2333/ASMR-Hub/releases) (built and uploaded
automatically by `.github/workflows/release.yml` on tags):

- **Windows**: `asmr_hub-windows-x64.zip` (unzip and run)
- **Android**: `asmr_hub-android.apk`
- **Linux**: `asmr_hub-linux-x64.tar.gz`
- **macOS**: `asmr_hub-macos-arm64.zip` / `asmr_hub-macos-x64.zip`

## Building from Source

### Prerequisites

- Flutter 3.47+ (Dart 3.10+)
- Windows build: Visual Studio (MSVC) + MinGW-w64 gcc (to compile the FFmpeg bridge)
- Linux build: GTK 3 dev packages + FFmpeg dev libraries (libavformat-dev, …)
- macOS build: Xcode + Homebrew FFmpeg
- Android build: Android SDK/NDK (default NDK 28.2.13676358)

### Windows

```powershell
# Fetch FFmpeg DLLs, compile ffmpeg_bridge.dll (MinGW), flutter build,
# package dist/asmr_hub-windows-x64.zip
powershell -File tool/build_windows.ps1 -Release
```

### Linux

```bash
# FFmpeg bridge + flutter build + bundle the system libmpv (self-contained)
# + package dist/asmr_hub-linux-x64.tar.gz
# Deps: libgtk-3-dev ninja-build clang cmake pkg-config + FFmpeg dev libs + libmpv-dev
bash tool/build_linux.sh
```

### macOS

```bash
# FFmpeg bridge + flutter build + bundle FFmpeg dylibs into the .app and
# re-sign + package dist/asmr_hub-macos-<arch>.zip
# Deps: Xcode + Homebrew FFmpeg
bash tool/build_macos.sh
```

### Android

```bash
# (Optional) NDK cross-compile of FFmpeg 7.1 into jniLibs (without it the APK
# still builds, download/recording just won't work) + flutter build apk
# + copy dist/asmr_hub-android.apk
bash tool/build_android.sh
```

> Every platform uses media_kit's bundled libmpv, which is verified to
> support the lavfi audio filters — no manual replacement is needed.

## Project Structure

```
lib/
├── main.dart                 # Entry: MediaKit init, Provider wiring, main tab shell
├── pages/                    # UI pages (source list/detail, player, playlist,
│                             #   downloads, settings, import wizard, web login, …)
├── providers/                # State (AudioPlayerProvider, PlaylistProvider,
│                             #   ThemeProvider, EffectsProvider, AuthProvider, …)
├── services/                 # Business services
│   ├── mpv_player_engine.dart    # media_kit player engine wrapper (lazy Player)
│   ├── audio_provider.dart       # Playback state machine: routing, loop/shuffle,
│   │                             #   sleep timer, persistence
│   ├── download_manager.dart     # Concurrent downloads + rate limit + cache format
│   │                             #   (transcoded via the FFmpeg bridge)
│   ├── live_recorder.dart        # Live recording (FFmpeg bridge)
│   ├── live_watch_manager.dart   # Background multi-room watchdog
│   ├── source_import_service.dart# Account import (favorites/followings/playlists/purchased)
│   └── ffmpeg/                   # Dart FFI bindings for the FFmpeg bridge (decode/encode)
├── sources/                  # Per-platform source implementations
│   ├── base/                     # BaseAudioSource / SourceAuth / SourceScraper
│   ├── bilibili/ douyu/ youtube/ dlsite/ asmrone/ twitch/ local/
├── models/                   # Data models (AudioTrack, ASMRSource, account data, …)
├── effects/                  # Audio filter chain generation (lavfi)
└── l10n/                     # ARB localization + generated app_localizations

third_party/ffmpeg/           # FFmpeg bridge C source + committed headers (binaries fetched at build time)
tool/                         # Per-platform build scripts (see "Building from Source")
.github/workflows/            # CI + release workflows
test/  test_network/          # Offline tests / network-dependent tests
```

## Development

### Localization

ARB files live under `lib/l10n/` (`app_en.arb` / `app_zh.arb`). After editing:

```bash
flutter gen-l10n
```

### Adding a New Source

1. Create an implementation under `lib/sources/<name>/` (subclass
   `BaseAudioSource`, providing a `SourceAuth` and a `SourceScraper`)
2. Register it in `_registerSources` in
   `lib/services/audio_source_manager.dart`
3. Add a default config in `_loadConfigs`
4. (Optional) add account-import support in
   `lib/services/source_import_service.dart`

### Testing

- `test/`: offline unit/widget tests (this is the only directory CI runs with
  `flutter test`)
- `test_network/`: tests that depend on real network/external state
  (Bilibili, Douyu, YouTube APIs, …); run manually:
  `flutter test test_network`

### Audio Architecture

- **Playback**: media_kit (libmpv) — decoding, streaming, live, headers, lavfi filters
- **Download/recording transcoding**: FFmpeg bridge
  (`third_party/ffmpeg/ffmpeg_bridge.c`, pure-C FFI)
  - Windows: `ffmpeg_bridge.dll` + avcodec-61/avformat-61/avutil-59/swresample-5,
    fetched/compiled by `tool/fetch_ffmpeg_windows.ps1` (binaries are not
    committed; the FFmpeg headers in `third_party/ffmpeg/include/` are)
  - Linux: `libffmpeg_bridge.so`, linked against the system FFmpeg by
    `tool/build_ffmpeg_bridge_posix.sh`, bundled into the app's `lib/` by CMake
  - macOS: `libffmpeg_bridge.dylib`, compiled by the same posix script;
    `tool/bundle_macos.sh` copies the dylibs into the .app Frameworks and
    re-signs ad hoc
  - Android: `tool/build_ffmpeg_android.sh` cross-compiles FFmpeg 7.1 into
    jniLibs; Gradle CMake then builds `libffmpeg_bridge.so`
- **Effects**: mpv `af` filter chain (lavfi: alimiter / lowpass), generated by `EffectsProvider`
- **Volume model**: 0-1 end to end (persisted as 0-1), converted to mpv's 0-100
  only at the engine boundary; volume is persisted immediately on every change

## CI / Release

GitHub Actions workflows (remote: `git@github.com:shitake2333/ASMR-Hub.git`):

- `.github/workflows/ci.yml`: on push/PR to `main` runs `flutter analyze` +
  `flutter test` (offline suite) + format check
- `.github/workflows/release.yml`: on a `v*` tag builds Windows / Linux /
  macOS (arm64+x64) / Android packages and uploads them to GitHub Releases:

```bash
git tag v1.0.0
git push origin v1.0.0
```

## License

MIT License — see [LICENSE](LICENSE).
