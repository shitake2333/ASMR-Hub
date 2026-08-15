# Builds the Windows release bundle: fetches FFmpeg + bridge, builds with
# Flutter, swaps in the full libmpv build (lavfi filters), and zips the
# result. Run from the repo root (or pass -RepoRoot).
#
# Usage:
#   powershell -File tool/build_windows.ps1          # debug
#   powershell -File tool/build_windows.ps1 -Release  # release + zip

param(
  [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
  [switch]$Release
)

$ErrorActionPreference = 'Stop'
Set-Location $RepoRoot

# ---- 0. FFmpeg + bridge (needed by the CMake POST_BUILD copy) -------------
& (Join-Path $PSScriptRoot 'fetch_ffmpeg_windows.ps1') -RepoRoot $RepoRoot

# ---- 1. Full libmpv (lavfi filters) ---------------------------------------
# media_kit bundles a "video" libmpv without lavfi audio filters (limiter,
# lowpass). The full build (shinchiro/mpv-winbuild-cmake) supports them. It
# is downloaded once and cached, then copied over the bundled libmpv-2.dll.
$mpvCache = Join-Path $env:LOCALAPPDATA 'ASMRHub\mpv_cache'
New-Item -ItemType Directory -Path $mpvCache -Force | Out-Null

# Latest mpv-dev x86_64 (full lavfi). Find the newest release tag.
$mpvTag = '20260814'  # fallback; see fetch below
$mpvAsset = "mpv-dev-x86_64-$mpvTag-git-7b8915bc1d.7z"  # adjust if tag changes
$mpvUrl = "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/$mpvTag/$mpvAsset"
$mpvZip = Join-Path $mpvCache $mpvAsset
$mpvExtract = Join-Path $mpvCache 'mpv_full'

if (-not (Test-Path (Join-Path $mpvExtract 'libmpv-2.dll'))) {
  if (-not (Test-Path $mpvZip)) {
    Write-Host "Downloading full libmpv ($mpvTag)..."
    # curl handles the large binary better than Invoke-WebRequest.
    & curl.exe -L --retry 3 -o $mpvZip $mpvUrl
    if ($LASTEXITCODE -ne 0) { throw 'libmpv download failed' }
  }
  Write-Host 'Extracting full libmpv...'
  New-Item -ItemType Directory -Path $mpvExtract -Force | Out-Null
  # 7z archives: use tar (Windows 10+ ships bsdtar with 7z support).
  & tar.exe -xf $mpvZip -C $mpvExtract
  if ($LASTEXITCODE -ne 0) { throw 'libmpv extraction failed' }
  # Find libmpv-2.dll in the extracted tree.
  $found = Get-ChildItem $mpvExtract -Recurse -Filter 'libmpv-2.dll' |
    Select-Object -First 1
  if (-not $found) { throw 'libmpv-2.dll not found after extraction' }
  # Move it to a predictable location.
  if ($found.DirectoryName -ne $mpvExtract) {
    Move-Item $found.FullName (Join-Path $mpvExtract 'libmpv-2.dll') -Force
  }
}

# ---- 2. Flutter build -------------------------------------------------------
$mode = if ($Release) { '--release' } else { '--debug' }
Write-Host "Building Windows $mode..."
& flutter build windows $mode
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

# ---- 3. Swap in the full libmpv --------------------------------------------
$buildDir = Join-Path $RepoRoot "build\windows\x64\runner\$(
  if ($Release) { 'Release' } else { 'Debug' })"
$targetMpv = Join-Path $buildDir 'libmpv-2.dll'
if (-not (Test-Path $targetMpv)) { throw "Build output not found: $buildDir" }
Copy-Item (Join-Path $mpvExtract 'libmpv-2.dll') $targetMpv -Force
Write-Host "Replaced libmpv-2.dll with full build: $((Get-Item $targetMpv).Length/1MB) MB"

# ---- 4. Package (release only) ---------------------------------------------
if ($Release) {
  $zipName = 'asmr_hub-windows-x64.zip'
  $zipPath = Join-Path $RepoRoot "dist\$zipName"
  New-Item -ItemType Directory -Path (Join-Path $RepoRoot 'dist') -Force | Out-Null
  if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
  Write-Host "Packaging $zipName..."
  Compress-Archive -Path (Join-Path $buildDir '*') -DestinationPath $zipPath
  Write-Host "Created: $zipPath"
}

Write-Host 'Windows build complete.'
