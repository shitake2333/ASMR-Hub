# FFmpeg Bridge 跨平台支持

ASMR Hub 的音频解码通过 `third_party/ffmpeg/ffmpeg_bridge` 完成：一个极小的 C 桥接库
封装 FFmpeg 的 avformat/avcodec/swresample，向 Dart 暴露 8 个 FFI 函数。桥接层本身
是纯 C（可移植），FFmpeg 库按平台分发。

## 平台支持

| 平台 | 桥文件名 | FFmpeg 依赖 | 构建方式 |
|------|----------|-------------|----------|
| Windows | `ffmpeg_bridge.dll` | `avcodec-61.dll` `avformat-61.dll` `avutil-59.dll` `swresample-5.dll` | MinGW，见 `tool/build_ffmpeg_bridge.ps1` |
| Linux | `libffmpeg_bridge.so` | `libavcodec.so.*` `libavformat.so.*` `libavutil.so.*` `libswresample.so.*` | `tool/build_ffmpeg_bridge.sh` |
| macOS | `libffmpeg_bridge.dylib` | `libavcodec.*.dylib` `libavformat.*.dylib` `libavutil.*.dylib` `libswresample.*.dylib` | `tool/build_ffmpeg_bridge.sh` |

## 运行时加载顺序（`lib/services/ffmpeg/ffmpeg_bridge.dart`）

1. 可执行文件同目录（Windows 由 CMake POST_BUILD 拷贝；其他平台手动放置）
2. 项目 `third_party/ffmpeg/`（开发 / `flutter test` 场景）
3. 裸库名（系统库路径 / `LD_LIBRARY_PATH` / `DYLD_LIBRARY_PATH`）

依赖库会在打开桥之前按依赖顺序预加载（Windows 需要，其他平台为稳妥同样尝试）。

## Linux 构建

```bash
# 方案 A：使用系统 FFmpeg（推荐，自动适配发行版库版本）
sudo apt install libavformat-dev libavcodec-dev libavutil-dev libswresample-dev
bash tool/build_ffmpeg_bridge.sh --system

# 方案 B：使用 third_party/ffmpeg 内置的 FFmpeg 7.1 树
bash tool/build_ffmpeg_bridge.sh --bundled

# 运行后需让系统找到 FFmpeg 共享库（视构建方式）
export LD_LIBRARY_PATH=$PWD/third_party/ffmpeg:$LD_LIBRARY_PATH
flutter run -d linux
```

## macOS 构建

```bash
brew install ffmpeg
bash tool/build_ffmpeg_bridge.sh --system   # 或 --bundled

# 若链接 Homebrew FFmpeg，运行前：
export DYLD_LIBRARY_PATH="$(brew --prefix ffmpeg)/lib:$DYLD_LIBRARY_PATH"
flutter run -d macos
```

## Windows 构建

```powershell
# 需要 MinGW-w64 gcc；FFmpeg 7.1 共享构建放 third_party/ffmpeg
powershell -File tool/build_ffmpeg_bridge.ps1
flutter build windows --debug
```

## 移动端支持（Android / iOS）

移动端不捆绑 FFmpeg 时，应用**不会崩溃**：`FfmpegBridge.instance` 加载失败返回
`null`，解码器检测后回退，SoLoud 直接解码 mp3/wav/flac/ogg（这些格式覆盖绝大多数
ASMR 内容）。需要 FFmpeg 的格式（m4a/aac/opus 等）会提示不支持。

要启用完整格式支持，需按平台构建并捆绑 FFmpeg：

### Android

```bash
# 1. 构建 FFmpeg .so（NDK），输出到 android/app/src/main/jniLibs/<abi>/
#    需先设置 ANDROID_NDK_HOME 或 ANDROID_HOME（含 ndk/）
bash tool/build_ffmpeg_android.sh            # 全部 ABI（arm64-v8a/armeabi-v7a/x86_64）

# 2. 构建 APK：CMake（android/app/src/main/cpp/CMakeLists.txt）会自动把
#    ffmpeg_bridge.c 编成 libffmpeg_bridge.so，并链接 jniLibs 里的 FFmpeg
flutter build apk
```

运行时：`FfmpegBridge` 从 APK 的 `lib/<abi>/` 目录加载 `libffmpeg_bridge.so`
（`Platform.resolvedExecutable` 的父目录即 lib 目录）。

### iOS

iOS 禁止运行时加载动态库（App Store），采用**静态链接**：

```bash
# 构建 FFmpeg 静态库 + libffmpeg_bridge.a（arm64 设备 + x86_64 模拟器）
bash tool/build_ffmpeg_ios.sh
# 产物在 ios/ffmpeg_bridge/*.a
```

然后在 Xcode 中：
1. 打开 `ios/Runner.xcodeproj`，把 `ios/ffmpeg_bridge/*.a` 拖入
   Runner target 的 **Link Binary With Libraries**
2. 确保 `ios/ffmpeg_bridge` 在 **Framework Search Paths** 中
3. `flutter build ios`

运行时：Dart 先尝试从 app bundle 找 `libffmpeg_bridge.dylib`，找不到则用
`DynamicLibrary.process()` 从已静态链接的可执行文件解析符号。

> 注意：Android/iOS 的 FFmpeg 构建脚本为最小功能集（file/http/https 协议 +
> 常见音频解码器），体积约为每 ABI 5–15 MB。如需更多格式，编辑脚本的
> `--enable-*` 配置。

## 注意事项

- **库版本**：C 桥使用 FFmpeg 7.x 公共 API。Linux/macOS 用系统 FFmpeg 时，
  发行版版本较旧（如 4.x/5.x）也能编译，因为 API 兼容。若编译报错，
  优先升级系统 FFmpeg 或改用 `--bundled`。
- **测试**：`flutter test` 时桥从 `third_party/ffmpeg/` 加载；请确保该目录
  包含当前平台的桥库与 FFmpeg 共享库。
- **移动端**（Android/iOS）：当前未启用 FFmpeg 桥（移动端 SoLoud 直接解码
  mp3/wav/flac/ogg；m4a 等格式暂不支持，属已知限制）。
