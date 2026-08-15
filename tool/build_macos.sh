#!/usr/bin/env bash
# One-shot macOS release build: FFmpeg bridge + flutter build + bundle the
# FFmpeg dylibs into the .app + zip into dist/asmr_hub-macos-<arch>.zip.
#
# Usage: bash tool/build_macos.sh
# Requires: Xcode, Homebrew FFmpeg (brew install ffmpeg)

set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 1/4 FFmpeg bridge (libffmpeg_bridge.dylib)..."
bash tool/build_ffmpeg_bridge_posix.sh

echo "==> 2/4 Flutter build (release)..."
flutter pub get
flutter build macos --release

echo "==> 3/4 Bundle FFmpeg dylibs + re-sign..."
bash tool/bundle_macos.sh

echo "==> 4/4 Package dist/asmr_hub-macos-<arch>.zip ..."
mkdir -p dist
ARCH="$(uname -m)"
case "$ARCH" in
  arm64) ZIP_ARCH="arm64" ;;
  x86_64) ZIP_ARCH="x64" ;;
  *) echo "WARNING: unknown arch $ARCH; naming zip as-is" >&2; ZIP_ARCH="$ARCH" ;;
esac
ditto -c -k --keepParent \
  "build/macos/Build/Products/Release/ASMR Hub.app" \
  "dist/asmr_hub-macos-$ZIP_ARCH.zip"
ls -lh "dist/asmr_hub-macos-$ZIP_ARCH.zip"
echo "macOS build complete."
