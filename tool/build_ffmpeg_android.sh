#!/usr/bin/env bash
# Builds FFmpeg 7.1 shared libraries for Android and installs them into
# android/app/src/main/jniLibs/<abi>/. The Gradle CMake step then compiles
# libffmpeg_bridge.so against them, enabling download/record on Android.
#
# Usage: bash tool/build_ffmpeg_android.sh
# Requires:
#   - ANDROID_HOME (or ANDROID_SDK_ROOT) with an NDK installed, or
#     ANDROID_NDK_ROOT pointing at an NDK.
#   - make, curl, tar (xz).
#
# Output: android/app/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64}/
#         libavformat.so, libavcodec.so, libavutil.so, libswresample.so
# Each lib is shipped under both its unversioned name (for the link step)
# and its SONAME (e.g. libavcodec.so.61) so the Android linker can resolve
# the bridge's DT_NEEDED entries at runtime.

set -euo pipefail
cd "$(dirname "$0")/.."

FF_VERSION="7.1"
API=24
JNI="android/app/src/main/jniLibs"
MBEDTLS_VERSION="3.6.7"

echo "==> Locating NDK..."
NDK="${ANDROID_NDK_ROOT:-${ANDROID_NDK:-}}"
if [ -z "$NDK" ]; then
  SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [ -z "$SDK" ]; then
    echo "ERROR: set ANDROID_HOME or ANDROID_NDK_ROOT." >&2
    exit 1
  fi
  NDK="$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
  if [ -z "$NDK" ] || [ ! -d "$NDK" ]; then
    echo "ERROR: no NDK under $SDK/ndk. Install one: sdkmanager 'ndk;28.2.13676358'" >&2
    exit 1
  fi
fi
echo "    NDK: $NDK"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  HOST="linux-x86_64" ;;
  Darwin-arm64)  HOST="darwin-arm64" ;;
  Darwin-x86_64) HOST="darwin-x86_64" ;;
  *) echo "ERROR: unsupported host $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST"
BIN="$TOOLCHAIN/bin"
[ -x "$BIN/llvm-ar" ] || { echo "ERROR: NDK toolchain missing at $TOOLCHAIN" >&2; exit 1; }

# ---- FFmpeg source ----------------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SRC="$WORK/ffmpeg-$FF_VERSION"
if [ ! -d "$SRC" ]; then
  echo "==> Downloading FFmpeg $FF_VERSION source..."
  curl -L --retry 3 -o "$WORK/ffmpeg.tar.xz" \
    "https://ffmpeg.org/releases/ffmpeg-$FF_VERSION.tar.xz"
  tar -xf "$WORK/ffmpeg.tar.xz" -C "$WORK"
fi

# ---- mbedtls (TLS backend so https URLs work) --------------------------------
# FFmpeg's https protocol needs a TLS library; without one the bridge cannot
# open https URLs (all Bilibili streams etc.). Cross-compile mbedtls per ABI
# and statically link it into libavformat.so (no extra .so to ship).
MBEDTLS_SRC="$WORK/mbedtls-$MBEDTLS_VERSION"
if [ ! -d "$MBEDTLS_SRC" ]; then
  echo "==> Downloading mbedtls $MBEDTLS_VERSION..."
  curl -L --retry 3 -o "$WORK/mbedtls.tar.gz" \
    "https://github.com/Mbed-TLS/mbedtls/archive/refs/tags/v$MBEDTLS_VERSION.tar.gz"
  tar -xzf "$WORK/mbedtls.tar.gz" -C "$WORK"
fi

build_mbedtls() {
  local abi="$1"
  local prefix="$WORK/mbedtls-$abi"
  local bdir="$WORK/mbedtls-build-$abi"
  echo "==> Building mbedtls for $abi ..."
  cmake -S "$MBEDTLS_SRC" -B "$bdir" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" \
    -DANDROID_PLATFORM="android-$API" \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF -DENABLE_ZLIB_SUPPORT=OFF \
    -DCMAKE_BUILD_TYPE=Release >/dev/null
  cmake --build "$bdir" -j"$(nproc 2>/dev/null || echo 2)" >/dev/null
  cmake --install "$bdir" >/dev/null
}

# ---- Build per ABI ----------------------------------------------------------
build_abi() {
  local abi="$1" arch="$2" cc_suffix="$3" extra=("${@:4}")
  echo "==> Building FFmpeg for $abi ..."
  local mbed="$WORK/mbedtls-$abi"
  build_mbedtls "$abi"
  local bdir="$WORK/build-$abi"
  mkdir -p "$bdir"
  (
    cd "$SRC"
    make distclean >/dev/null 2>&1 || true
    # Let FFmpeg's configure find mbedtls via its pkg-config file.
    export PKG_CONFIG_PATH="$mbed/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    ./configure \
      --prefix="$bdir/install" \
      --target-os=android \
      --enable-cross-compile \
      --arch="$arch" \
      --cc="$BIN/${cc_suffix}${API}-clang" \
      --cxx="$BIN/${cc_suffix}${API}-clang++" \
      --ar="$BIN/llvm-ar" \
      --ranlib="$BIN/llvm-ranlib" \
      --nm="$BIN/llvm-nm" \
      --strip="$BIN/llvm-strip" \
      --enable-shared \
      --disable-static \
      --disable-programs \
      --disable-doc \
      --disable-debug \
      --disable-avdevice \
      --disable-postproc \
      --disable-avfilter \
      --disable-swscale \
      --enable-mbedtls \
      --extra-cflags="-I$mbed/include" \
      --extra-ldflags="-L$mbed/lib" \
      "${extra[@]}"
    make -j"$(nproc 2>/dev/null || echo 2)" >/dev/null
    make install >/dev/null
  )
  # Copy the four libs (unversioned + SONAME) into jniLibs.
  local out="$JNI/$abi"
  mkdir -p "$out"
  rm -f "$out"/libav*.so*
  for name in libavformat libavcodec libavutil libswresample; do
    local lib="$bdir/install/lib/$name.so"
    [ -f "$lib" ] || { echo "ERROR: $lib not built" >&2; exit 1; }
    cp -L "$lib" "$out/$name.so"
    # SONAME (e.g. libavcodec.so.61) — needed by the Android loader.
    local soname
    soname="$("$BIN/llvm-readelf" -d "$out/$name.so" | awk '/SONAME/ {print $NF; exit}')"
    if [ -n "$soname" ] && [ "$soname" != "$name.so" ]; then
      cp -L "$out/$name.so" "$out/$soname"
    fi
  done
  echo "    -> $out"
}

build_abi arm64-v8a  aarch64  aarch64-linux-android
build_abi armeabi-v7a arm     armv7a-linux-androideabi --cpu=armv7-a
build_abi x86_64     x86_64   x86_64-linux-android     --disable-x86asm

echo "==> Done. Android FFmpeg libs installed under $JNI"
echo "    Next: flutter build apk --release (Gradle compiles libffmpeg_bridge.so)"