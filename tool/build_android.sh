#!/usr/bin/env bash
# One-shot Android release build: optional FFmpeg native build + flutter build
# apk + copy into dist/asmr_hub-android.apk.
#
# Usage: bash tool/build_android.sh
# Requires: Android SDK/NDK (ANDROID_HOME or ANDROID_NDK_ROOT), JDK 17.
# The NDK FFmpeg build (download/recording support) is optional: when the NDK
# is missing or the build fails, the APK is still produced — download and live
# recording just fall back to "unavailable".

set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 1/3 Android FFmpeg (libavformat.so etc. into jniLibs)..."
if [ -n "${ANDROID_NDK_ROOT:-${ANDROID_NDK:-${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}}}" ]; then
  if bash tool/build_ffmpeg_android.sh; then
    echo "    FFmpeg native libs ready."
  else
    echo "WARNING: FFmpeg Android build failed; APK will ship without" >&2
    echo "         download/recording support." >&2
  fi
else
  echo "WARNING: Android NDK not found; skipping FFmpeg (download/recording" >&2
  echo "         unavailable). Set ANDROID_HOME/ANDROID_NDK_ROOT to enable." >&2
fi

echo "==> 2/3 Flutter build (APK, release)..."
flutter pub get
flutter build apk --release

echo "==> 3/3 Copy dist/asmr_hub-android.apk ..."
mkdir -p dist
cp build/app/outputs/flutter-apk/app-release.apk dist/asmr_hub-android.apk
ls -lh dist/asmr_hub-android.apk
echo "Android build complete."
