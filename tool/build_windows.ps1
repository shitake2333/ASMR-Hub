# Builds the Windows release bundle: fetches FFmpeg + bridge, builds with
# Flutter, and zips the result. Run from the repo root (or pass -RepoRoot).
#
# media_kit's bundled libmpv already supports the lavfi audio filters used by
# the app's effects, so no libmpv replacement is needed (verified by
# tool/mpv_lavfi_check.dart).
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

# Locate the flutter binary: PATH first, then common install roots.
function Find-Flutter {
  $cmd = Get-Command flutter -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($root in @($env:FLUTTER_ROOT, 'D:\flutter', 'C:\flutter')) {
    if ($root) {
      $candidate = Join-Path $root 'bin\flutter.bat'
      if (Test-Path $candidate) { return $candidate }
    }
  }
  throw 'flutter not found. Install it or add it to PATH (or set FLUTTER_ROOT).'
}

# ---- 1. FFmpeg + bridge (needed by the CMake POST_BUILD copy) -------------
& (Join-Path $PSScriptRoot 'fetch_ffmpeg_windows.ps1') -RepoRoot $RepoRoot

# ---- 2. Flutter build -------------------------------------------------------
$flutter = Find-Flutter
$mode = if ($Release) { '--release' } else { '--debug' }
Write-Host "Building Windows $mode ($flutter)..."
& $flutter build windows $mode
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

# ---- 3. Package (release only) ---------------------------------------------
if ($Release) {
  $buildDir = Join-Path $RepoRoot 'build\windows\x64\runner\Release'
  if (-not (Test-Path $buildDir)) { throw "Build output not found: $buildDir" }
  $zipName = 'asmr_hub-windows-x64.zip'
  $zipPath = Join-Path $RepoRoot "dist\$zipName"
  New-Item -ItemType Directory -Path (Join-Path $RepoRoot 'dist') -Force | Out-Null
  if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
  Write-Host "Packaging $zipName..."
  Compress-Archive -Path (Join-Path $buildDir '*') -DestinationPath $zipPath
  Write-Host "Created: $zipPath"
}

Write-Host 'Windows build complete.'
