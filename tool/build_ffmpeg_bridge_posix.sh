#!/usr/bin/env bash
# Builds libffmpeg_bridge.so / .dylib against the system FFmpeg.
# Used by Linux CI (and locally on macOS/Linux).
#
# Usage: bash tool/build_ffmpeg_bridge_posix.sh
# Requires: gcc/clang, pkg-config, libavformat-dev libavcodec-dev
#           libavutil-dev libswresample-dev (or ffmpeg on macOS).

set -euo pipefail
cd "$(dirname "$0")/.."

FF_DIR="third_party/ffmpeg"
mkdir -p "$FF_DIR"

case "$(uname -s)" in
  Darwin*)
    OUT="libffmpeg_bridge.dylib"
    ;;
  Linux*)
    OUT="libffmpeg_bridge.so"
    ;;
  *)
    echo "Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

echo "==> Compiling $OUT against system FFmpeg..."
cc -shared -O2 -fPIC -o "$FF_DIR/$OUT" "$FF_DIR/ffmpeg_bridge.c" \
  $(pkg-config --cflags --libs libavformat libavcodec libavutil libswresample)

echo "==> Built $FF_DIR/$OUT"
