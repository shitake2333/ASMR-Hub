#!/usr/bin/env bash
# Bundles the FFmpeg bridge + FFmpeg dylibs into the macOS .app and re-signs
# it ad hoc. Run AFTER `flutter build macos --release` (and after
# tool/build_ffmpeg_bridge_posix.sh).
#
# Usage: bash tool/bundle_macos.sh
# Requires: Homebrew FFmpeg (brew install ffmpeg), Xcode command line tools.
#
# What it does:
#  1. Copies libffmpeg_bridge.dylib + the FFmpeg dylibs (avcodec/avformat/
#     avutil/swresample) into ASMR Hub.app/Contents/Frameworks/.
#  2. Rewrites the dylibs' install names to @loader_path so the app finds them
#     inside the bundle without Homebrew installed.
#  3. Ad-hoc codesigns every dylib and the app (no Developer ID needed).

set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/macos/Build/Products/Release/ASMR Hub.app"
if [ ! -d "$APP" ]; then
  echo "App not found: $APP — run 'flutter build macos --release' first." >&2
  exit 1
fi

FFPREFIX="$(brew --prefix ffmpeg)"
BRIDGE="third_party/ffmpeg/libffmpeg_bridge.dylib"
if [ ! -f "$BRIDGE" ]; then
  echo "Bridge missing: run 'bash tool/build_ffmpeg_bridge_posix.sh' first." >&2
  exit 1
fi

FRAMEWORKS="$APP/Contents/Frameworks"
mkdir -p "$FRAMEWORKS"

# FFmpeg dylibs the bridge links against (sonames for FFmpeg 7.x).
LIBS=(libavcodec.61.dylib libavformat.61.dylib libavutil.59.dylib libswresample.5.dylib)

cp "$BRIDGE" "$FRAMEWORKS/libffmpeg_bridge.dylib"
for lib in "${LIBS[@]}"; do
  src="$FFPREFIX/lib/$lib"
  if [ -f "$src" ]; then
    cp "$src" "$FRAMEWORKS/$lib"
  else
    echo "Warning: $src not found — bridge may fail to load at runtime." >&2
  fi
done

# Rewrite install names: every reference to the Homebrew path becomes
# @loader_path/<name> (same directory → Frameworks).
for dylib in "$FRAMEWORKS"/*.dylib; do
  for lib in "${LIBS[@]}"; do
    old="$FFPREFIX/lib/$lib"
    if otool -L "$dylib" 2>/dev/null | grep -qF "$old"; then
      install_name_tool -change "$old" "@loader_path/$lib" "$dylib"
    fi
  done
  # Ensure each dylib's own identity is rpath-relative.
  install_name_tool -id "@rpath/$(basename "$dylib")" "$dylib" 2>/dev/null || true
  codesign --force --sign - "$dylib"
done

# Ad-hoc re-sign the whole app (the new dylibs invalidated the previous seal).
codesign --force --deep --sign - "$APP"
echo "Bundled FFmpeg dylibs into $APP"
echo "Verify: codesign --verify --deep --strict '$APP'"
