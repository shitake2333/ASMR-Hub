# Fetches the FFmpeg 7.1 shared build (BtbN) and compiles ffmpeg_bridge.dll
# for Windows. Run from the repo root (or pass -RepoRoot).
#
# Usage:
#   powershell -File tool/fetch_ffmpeg_windows.ps1
#
# The FFmpeg shared build (~115 MB) is cached under $env:LOCALAPPDATA\ASMRHub\
# ffmpeg_cache and copied into third_party/ffmpeg (git-ignored).

param(
  [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'
$ffDir = Join-Path $RepoRoot 'third_party\ffmpeg'

# ---- 1. FFmpeg 7.1 shared build (BtbN win64-gpl-shared) ---------------------
# This specific version matches the avcodec-61/avformat-61 sonames the bridge
# links against. Update the URL when upgrading FFmpeg.
$ffmpegVersion = '7.1'
$ffmpegUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n${ffmpegVersion}-latest-win64-gpl-shared-7.1.zip"
$cacheDir = Join-Path $env:LOCALAPPDATA 'ASMRHub\ffmpeg_cache'
$zipPath = Join-Path $cacheDir 'ffmpeg-win64-shared.zip'

New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

# The zip's top-level directory name may vary (e.g. ffmpeg-n7.1-latest-
# win64-gpl-shared-7.1); locate bin/ dynamically instead of hardcoding it.
$ffBin = Get-ChildItem $cacheDir -Recurse -Directory -Filter 'bin' |
  Select-Object -First 1 -ExpandProperty FullName

if (-not $ffBin) {
  if (-not (Test-Path $zipPath)) {
    Write-Host "Downloading FFmpeg $ffmpegVersion shared build..."
    Invoke-WebRequest -Uri $ffmpegUrl -OutFile $zipPath -UseBasicParsing
  }
  Write-Host 'Extracting FFmpeg...'
  Expand-Archive -Path $zipPath -DestinationPath $cacheDir -Force
  $ffBin = Get-ChildItem $cacheDir -Recurse -Directory -Filter 'bin' |
    Select-Object -First 1 -ExpandProperty FullName
  if (-not $ffBin) { throw 'FFmpeg bin/ not found after extraction' }
}
$extractDir = Split-Path $ffBin -Parent

Write-Host "FFmpeg binaries at: $ffBin"

# Copy the DLLs the bridge needs next to the app.
New-Item -ItemType Directory -Path $ffDir -Force | Out-Null
foreach ($dll in @('avcodec-61.dll','avformat-61.dll','avutil-59.dll','swresample-5.dll')) {
  $src = Join-Path $ffBin $dll
  if (Test-Path $src) {
    Copy-Item $src (Join-Path $ffDir $dll) -Force
  } else {
    Write-Warning "Missing $dll in FFmpeg build; listing available:"
    Get-ChildItem $ffBin -Filter '*.dll' | Select-Object -ExpandProperty Name | Out-String
  }
}

# ---- 2. Compile ffmpeg_bridge.dll with MinGW -------------------------------
# Requires MinGW-w64 gcc on PATH (scoop: `scoop install mingw`).
$bridgeSrc = Join-Path $ffDir 'ffmpeg_bridge.c'
if (-not (Test-Path $bridgeSrc)) {
  throw 'ffmpeg_bridge.c not found under third_party/ffmpeg'
}

$gcc = Get-Command gcc -ErrorAction SilentlyContinue
if (-not $gcc) {
  throw 'MinGW gcc not found. Install with: scoop install mingw (or add gcc to PATH).'
}

# Import libraries: the FFmpeg shared build ships .dll.a files in lib/.
$ffLib = Join-Path $extractDir 'lib'
if (-not (Test-Path (Join-Path $ffLib 'libavcodec.dll.a'))) {
  $ffLib = Get-ChildItem $extractDir -Recurse -Directory -Filter 'lib' |
    Select-Object -First 1 -ExpandProperty FullName
}

# Headers: BtbN builds do not ship include/; we keep them in the repo (they
# are part of the FFmpeg source tree). If missing, extract from the FFmpeg
# source or use a dev build. The repo tracks include/ so this is satisfied.
$ffInclude = Join-Path $ffDir 'include'
if (-not (Test-Path (Join-Path $ffInclude 'libavformat'))) {
  throw 'FFmpeg headers missing under third_party/ffmpeg/include (they are tracked in git).'
}

Write-Host 'Compiling ffmpeg_bridge.dll...'
& $gcc.Source -shared -O2 -o (Join-Path $ffDir 'ffmpeg_bridge.dll') $bridgeSrc `
  -I $ffInclude -L $ffLib -lavformat -lavcodec -lavutil -lswresample
if ($LASTEXITCODE -ne 0) { throw 'ffmpeg_bridge.dll compilation failed' }

Write-Host "ffmpeg_bridge.dll ready: $(Join-Path $ffDir 'ffmpeg_bridge.dll')"
Write-Host 'Done. Run: flutter build windows'
