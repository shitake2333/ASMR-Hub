import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// FFI bindings for the FFmpeg audio bridge (third_party/ffmpeg/ffmpeg_bridge).
/// The bridge wraps avformat/avcodec/swresample and exposes a tiny C API.
///
/// Platform support:
///  - Windows: ffmpeg_bridge.dll + versioned FFmpeg DLLs (avcodec-61.dll ...)
///  - Linux:   libffmpeg_bridge.so + libavcodec.so.61 ... (system or bundled)
///  - macOS:   libffmpeg_bridge.dylib + libavcodec.61.dylib ...
class FfmpegBridge {
  /// The shared bridge instance, or null when the native library is not
  /// available on this platform/build (e.g. mobile without bundled FFmpeg).
  /// Callers must check for null and fall back to another decode path.
  static FfmpegBridge? _instance;

  static FfmpegBridge? get instance {
    _instance ??= _tryCreate();
    return _instance;
  }

  static FfmpegBridge? _tryCreate() {
    try {
      return FfmpegBridge._();
    } catch (e) {
      // Native FFmpeg unavailable (e.g. mobile without bundled libs).
      // Log once; callers fall back to another decode path.
      assert(() {
        // ignore: avoid_print
        print('FfmpegBridge unavailable: $e');
        return true;
      }());
      return null;
    }
  }

  final DynamicLibrary _lib;

  FfmpegBridge._() : _lib = _load();

  static String get _bridgeFileName {
    if (Platform.isWindows) return 'ffmpeg_bridge.dll';
    if (Platform.isMacOS) return 'libffmpeg_bridge.dylib';
    if (Platform.isAndroid) return 'libffmpeg_bridge.so';
    if (Platform.isIOS) return 'libffmpeg_bridge.dylib';
    return 'libffmpeg_bridge.so'; // Linux
  }

  /// FFmpeg shared-library file names for the current platform. The bridge
  /// depends on these; the OS loader must find them (bundled next to the
  /// executable, in the search path, or via LD_LIBRARY_PATH/DYLD_*).
  static List<String> get _dependencyFileNames {
    if (Platform.isWindows) {
      // Order matters: leaf dependencies first so the Windows loader can
      // resolve them by already-loaded module name.
      return const [
        'avutil-59.dll',
        'swresample-5.dll',
        'avcodec-61.dll',
        'avformat-61.dll',
      ];
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return const [
        'libavutil.59.dylib',
        'libswresample.5.dylib',
        'libavcodec.61.dylib',
        'libavformat.61.dylib',
      ];
    }
    // Linux/Android: soname form.
    return const [
      'libavutil.so.59',
      'libswresample.so.5',
      'libavcodec.so.61',
      'libavformat.so.61',
    ];
  }

  static DynamicLibrary _load() {
    // Candidate directories, in order of preference. This bridge is native
    // (dart:io) only — web is never supported.
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final dirs = <String>[
      // Bundled with the app (same dir as the executable); on Android this
      // is the APK's lib/<abi>/ directory.
      exeDir,
      // iOS: bundled framework inside the app bundle.
      if (Platform.isIOS) _iosBundleDir,
      // macOS: Contents/Frameworks (Flutter bundle layout).
      if (Platform.isMacOS)
        '${File(Platform.resolvedExecutable).parent.parent.path}'
            '${Platform.pathSeparator}Frameworks',
      // Linux: bundle/lib (Flutter bundle layout).
      if (Platform.isLinux) '$exeDir${Platform.pathSeparator}lib',
      // Development / tests: project third_party.
      Directory('third_party/ffmpeg').absolute.path,
    ];
    Object? lastError;
    for (final dir in dirs) {
      final bridgePath = '$dir${Platform.pathSeparator}$_bridgeFileName';
      if (!File(bridgePath).existsSync()) continue;
      try {
        _preloadDependencies(dir);
        return DynamicLibrary.open(bridgePath);
      } catch (e) {
        lastError = e;
      }
    }
    // Android/iOS: try the bare soname — the loader searches the app's
    // lib/bundle dirs automatically.
    try {
      return DynamicLibrary.open(_bridgeFileName);
    } catch (e) {
      lastError = e;
    }
    // iOS static-link fallback: symbols baked into the executable.
    if (Platform.isIOS) {
      try {
        return DynamicLibrary.process();
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError(
      'Cannot load $_bridgeFileName: $lastError\n'
      'Expected one of: '
      '${dirs.map((d) => '$d${Platform.pathSeparator}$_bridgeFileName').join(', ')}',
    );
  }

  /// iOS app bundle directory: `bundle/Frameworks` and `bundle`.
  static String get _iosBundleDir {
    final exe = File(Platform.resolvedExecutable);
    return exe.parent.path; // .../Runner.app/ (Frameworks sits inside)
  }

  static void _preloadDependencies(String dir) {
    for (final dep in _dependencyFileNames) {
      final path = '$dir${Platform.pathSeparator}$dep';
      if (File(path).existsSync()) {
        try {
          DynamicLibrary.open(path);
        } catch (_) {
          // If a dependency fails to load the bridge open below will report
          // the real error.
        }
      }
    }
  }

  late final Pointer<Pointer<Int8>>? Function(
    Pointer<Utf8> url,
    Pointer<Utf8> headers,
    Pointer<Utf8> ua,
    int mp3Bitrate,
    int codec,
  )
  _open = _lib
      .lookupFunction<
        Pointer<Pointer<Int8>>? Function(
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Int32,
          Int32,
        ),
        Pointer<Pointer<Int8>>? Function(
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          int,
          int,
        )
      >('bridge_open');

  late final int Function(Pointer<Pointer<Int8>>) _getSampleRate = _lib
      .lookupFunction<
        Int32 Function(Pointer<Pointer<Int8>>),
        int Function(Pointer<Pointer<Int8>>)
      >('bridge_get_sample_rate');

  late final int Function(Pointer<Pointer<Int8>>) _getChannels = _lib
      .lookupFunction<
        Int32 Function(Pointer<Pointer<Int8>>),
        int Function(Pointer<Pointer<Int8>>)
      >('bridge_get_channels');

  late final double Function(Pointer<Pointer<Int8>>) _getDuration = _lib
      .lookupFunction<
        Double Function(Pointer<Pointer<Int8>>),
        double Function(Pointer<Pointer<Int8>>)
      >('bridge_get_duration');

  late final int Function(Pointer<Pointer<Int8>>, Pointer<Uint8>, int)
  _readPcm = _lib
      .lookupFunction<
        Int32 Function(Pointer<Pointer<Int8>>, Pointer<Uint8>, Int32),
        int Function(Pointer<Pointer<Int8>>, Pointer<Uint8>, int)
      >('bridge_read_pcm');

  late final int Function(Pointer<Pointer<Int8>>, Pointer<Uint8>, int)
  _takeEncoded = _lib
      .lookupFunction<
        Int32 Function(Pointer<Pointer<Int8>>, Pointer<Uint8>, Int32),
        int Function(Pointer<Pointer<Int8>>, Pointer<Uint8>, int)
      >('bridge_take_encoded');

  late final int Function(Pointer<Pointer<Int8>>, double) _seek = _lib
      .lookupFunction<
        Int32 Function(Pointer<Pointer<Int8>>, Double),
        int Function(Pointer<Pointer<Int8>>, double)
      >('bridge_seek');

  late final Pointer<Utf8> Function(Pointer<Pointer<Int8>>) _lastError = _lib
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Pointer<Int8>>),
        Pointer<Utf8> Function(Pointer<Pointer<Int8>>)
      >('bridge_last_error');

  late final void Function(Pointer<Pointer<Int8>>) _close = _lib
      .lookupFunction<
        Void Function(Pointer<Pointer<Int8>>),
        void Function(Pointer<Pointer<Int8>>)
      >('bridge_close');

  /// Opens a media URL (http(s) URL or local path) for audio decoding.
  /// [mp3Bitrate] > 0 additionally encodes the decoded audio to MP3 while
  /// decoding (for writing a compressed cache). [codec] selects the encoder:
  /// 0 = none, 1 = MP3, 2 = FLAC. Returns the opaque handle or null on
  /// failure (including the C NULL pointer).
  Pointer<Pointer<Int8>>? open(
    String url, {
    String? headers,
    String? userAgent,
    int mp3Bitrate = 0,
    int codec = 0,
  }) {
    final urlC = url.toNativeUtf8();
    final headersC = (headers ?? '').toNativeUtf8();
    final uaC = (userAgent ?? '').toNativeUtf8();
    try {
      final h = _open(urlC, headersC, uaC, mp3Bitrate, codec);
      if (h == null || h.address == 0) return null;
      return h;
    } finally {
      malloc.free(urlC);
      malloc.free(headersC);
      malloc.free(uaC);
    }
  }

  int getSampleRate(Pointer<Pointer<Int8>> h) => _getSampleRate(h);

  int getChannels(Pointer<Pointer<Int8>> h) => _getChannels(h);

  /// Media duration in seconds; 0 when unknown (e.g. live).
  double getDuration(Pointer<Pointer<Int8>> h) => _getDuration(h);

  /// Reads up to [capacity] bytes of interleaved s16le PCM.
  /// Returns bytes read; 0 on EOF; negative on error.
  int readPcm(Pointer<Pointer<Int8>> h, Pointer<Uint8> buffer, int capacity) {
    return _readPcm(h, buffer, capacity);
  }

  /// Takes encoded (MP3) bytes produced while decoding.
  /// Returns >0 bytes copied, 0 = none yet, -1 = error, -2 = finished.
  int takeEncoded(
    Pointer<Pointer<Int8>> h,
    Pointer<Uint8> buffer,
    int capacity,
  ) {
    return _takeEncoded(h, buffer, capacity);
  }

  /// Seeks the input to [seconds]. Returns true on success. Resets the
  /// encoder sidecar (discards buffered encoded bytes).
  bool seek(Pointer<Pointer<Int8>> h, double seconds) => _seek(h, seconds) == 0;

  String lastError(Pointer<Pointer<Int8>> h) {
    final p = _lastError(h);
    return p == nullptr ? '' : p.toDartString();
  }

  void close(Pointer<Pointer<Int8>> h) => _close(h);
}
