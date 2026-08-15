# CMake build for the FFmpeg audio bridge on Android.
#
# Builds libffmpeg_bridge.so from third_party/ffmpeg/ffmpeg_bridge.c and links
# it against the FFmpeg shared libraries shipped in jniLibs/<abi>/:
#   libavformat.so, libavcodec.so, libavutil.so, libswresample.so
#
# The bridge is optional: when the FFmpeg libs are absent (e.g. a fresh
# checkout before tool/build_ffmpeg_android.sh ran, or a build where native
# FFmpeg was skipped), no library is produced and the app still builds — the
# download/record features just fall back to "unavailable" at runtime
# (FfmpegBridge.instance == null).
#
# Prerequisites: place prebuilt FFmpeg .so files (built for the same FFmpeg
# version the bridge expects) in android/app/src/main/jniLibs/<abi>/.
# See tool/build_ffmpeg_android.sh for how to produce them.
cmake_minimum_required(VERSION 3.10)
project(ffmpeg_bridge C)

# Repo-root relative paths: this file lives at android/app/src/main/cpp/, so
# the repo root is five levels up (cpp -> main -> src -> app -> android -> root).
set(BRIDGE_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/ffmpeg/ffmpeg_bridge.c")
set(JNI_LIBS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}")

set(FFMPEG_LIBS
    "${JNI_LIBS_DIR}/libavformat.so"
    "${JNI_LIBS_DIR}/libavcodec.so"
    "${JNI_LIBS_DIR}/libavutil.so"
    "${JNI_LIBS_DIR}/libswresample.so")

set(ALL_PRESENT TRUE)
foreach(lib ${FFMPEG_LIBS})
    if(NOT EXISTS "${lib}")
        set(ALL_PRESENT FALSE)
    endif()
endforeach()

if(NOT ALL_PRESENT)
    message(WARNING
        "FFmpeg jniLibs missing for ${ANDROID_ABI}; "
        "skipping libffmpeg_bridge.so (download/record unavailable). "
        "Run tool/build_ffmpeg_android.sh to build them.")
    return()
endif()

if(NOT EXISTS "${BRIDGE_SRC}")
    message(FATAL_ERROR "ffmpeg_bridge.c not found at ${BRIDGE_SRC}")
endif()

# Headers of the FFmpeg dev tree (include/libavformat etc.).
set(FFMPEG_INCLUDE "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/ffmpeg/include")

add_library(ffmpeg_bridge SHARED ${BRIDGE_SRC})

target_include_directories(ffmpeg_bridge PRIVATE "${FFMPEG_INCLUDE}")

# Link against the FFmpeg libs from jniLibs/<abi>.
target_link_libraries(ffmpeg_bridge
    "${JNI_LIBS_DIR}/libavformat.so"
    "${JNI_LIBS_DIR}/libavcodec.so"
    "${JNI_LIBS_DIR}/libavutil.so"
    "${JNI_LIBS_DIR}/libswresample.so"
)

# Export the bridge symbols (EXPORT macro already handles visibility on
# non-Windows, but be explicit for Android).
set_target_properties(ffmpeg_bridge PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    POSITION_INDEPENDENT_CODE ON
    BUILD_RPATH ""
)
