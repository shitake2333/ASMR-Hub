#!/usr/bin/env bash
# One-shot Linux release build: FFmpeg bridge + flutter build + bundle the
# system libmpv + tar.gz into dist/asmr_hub-linux-x64.tar.gz.
#
# Usage: bash tool/build_linux.sh
# Requires: libgtk-3-dev ninja-build clang cmake pkg-config
#           libavformat-dev libavcodec-dev libavutil-dev libswresample-dev
#           libmpv-dev (media_kit loads the SYSTEM libmpv on Linux; bundling
#           it below makes the package self-contained)

set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 1/4 FFmpeg bridge (libffmpeg_bridge.so)..."
bash tool/build_ffmpeg_bridge_posix.sh

echo "==> 2/4 Flutter build (release)..."
flutter pub get
flutter build linux --release

echo "==> 3/4 Bundle system libmpv into the bundle lib/ ..."
BUNDLE="build/linux/x64/release/bundle"
LIBDIR="$BUNDLE/lib"
mkdir -p "$LIBDIR"

# Locate the system libmpv (libmpv-dev provides libmpv.so; runtime is
# libmpv.so.2). media_kit probes 'libmpv.so', 'libmpv.so.2', 'libmpv.so.1'
# in that order via dlopen, which searches the executable's RUNPATH
# ($ORIGIN/lib) before the system cache — so shipping the exact names here
# makes the bundle work without libmpv installed on the target machine.
MPV_LIB=""
if command -v pkg-config >/dev/null 2>&1; then
  MPV_LIB="$(pkg-config --variable=libdir mpv 2>/dev/null || true)"
  if [ -n "$MPV_LIB" ]; then
    MPV_LIB="$MPV_LIB/libmpv.so"
    [ -f "$MPV_LIB" ] || MPV_LIB=""
  fi
fi
if [ -z "$MPV_LIB" ]; then
  MPV_LIB="$(ldconfig -p 2>/dev/null | awk '/libmpv\.so\.2/{print $NF; exit}')"
fi
if [ -z "$MPV_LIB" ] || [ ! -f "$MPV_LIB" ]; then
  echo "WARNING: system libmpv not found. The package will require libmpv on"
  echo "         the target machine (Debian/Ubuntu: apt install libmpv-dev)." >&2
else
  cp -L "$MPV_LIB" "$LIBDIR/libmpv.so"
  cp -L "$MPV_LIB" "$LIBDIR/libmpv.so.2"
  echo "    bundled $(basename "$MPV_LIB") -> $LIBDIR/"
fi

echo "==> 4/4 Package dist/asmr_hub-linux-x64.tar.gz ..."
mkdir -p dist
tar -C "$BUNDLE" -czf dist/asmr_hub-linux-x64.tar.gz .
ls -lh dist/asmr_hub-linux-x64.tar.gz
echo "Linux build complete."
