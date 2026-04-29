# ==============================================================================
# Build script for gstgencamsrc GStreamer GenICam source plugin (Windows)
#
# Prerequisites
# -------------
#   1. GStreamer MSVC x86_64 installer from https://gstreamer.freedesktop.org
#      (install both runtime AND development packages)
#   2. GenICam SDK (Windows) installed, with GENICAM_ROOT64 or GENICAM_ROOT
#      environment variable set by the SDK installer.
#      Override with -GenicamRoot <path> if needed.
#   3. Visual Studio 2017 or later (Build Tools are sufficient).
#   4. pkg-config on PATH – bundled inside the GStreamer MSVC install at
#      <GStreamer>\bin\pkg-config.exe.
#
# Usage
#   .\build_gencamsrc.ps1
#   .\build_gencamsrc.ps1 -GenicamRoot "D:\GenICam" -VcVersion 120
# ==============================================================================

param(
    [string]$GenicamRoot = "",
    [string]$VcVersion   = "120",   # 120=VS2013, 141=VS2017, 142=VS2019, 143=VS2022
    [string]$BuildType   = "Release"
)

$ErrorActionPreference = "Stop"
$SRC_DIR = $PSScriptRoot

# ============================================================================
# Locate Visual Studio
# ============================================================================
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-Not (Test-Path $vswhere)) {
    Write-Error "vswhere.exe not found. Install Visual Studio Build Tools first."
    exit 1
}
$vsPath = & $vswhere -latest -products * -property installationPath
if (-Not $vsPath) {
    Write-Error "No Visual Studio installation detected by vswhere."
    exit 1
}
Write-Host "VS installation  : $vsPath"

# ============================================================================
# Locate GStreamer (mirrors build_gvasmartclassroom.ps1 logic)
# ============================================================================
$regPath = "HKLM:\SOFTWARE\GStreamer1.0\x86_64"
$regInstallDir = (Get-ItemProperty -Path $regPath -Name "InstallDir" -ErrorAction SilentlyContinue).InstallDir
if ($regInstallDir) {
    $GSTREAMER_ROOT = $regInstallDir.TrimEnd('\')
    if (-Not $GSTREAMER_ROOT.EndsWith('\1.0\msvc_x86_64')) {
        $GSTREAMER_ROOT = "$GSTREAMER_ROOT\1.0\msvc_x86_64"
    }
} else {
    $GSTREAMER_ROOT = "$env:ProgramFiles\gstreamer\1.0\msvc_x86_64"
}
if (-Not (Test-Path $GSTREAMER_ROOT)) {
    Write-Error "GStreamer not found at $GSTREAMER_ROOT.`nInstall from https://gstreamer.freedesktop.org (MSVC x86_64 packages)."
    exit 1
}
Write-Host "GStreamer root   : $GSTREAMER_ROOT"

# Point pkg-config at GStreamer's own .pc files
$env:PKG_CONFIG_PATH = "$GSTREAMER_ROOT\lib\pkgconfig"
# Also add GStreamer's pkg-config.exe to PATH if not already there
$env:PATH = "$GSTREAMER_ROOT\bin;$env:PATH"
Write-Host "PKG_CONFIG_PATH  : $env:PKG_CONFIG_PATH"

# ============================================================================
# Locate GenICam SDK
# ============================================================================
if ($GenicamRoot -ne "") {
    $GENICAM_ROOT = $GenicamRoot
} elseif ($env:GENICAM_ROOT64) {
    $GENICAM_ROOT = $env:GENICAM_ROOT64
} elseif ($env:GENICAM_ROOT) {
    $GENICAM_ROOT = $env:GENICAM_ROOT
} else {
    Write-Error "GenICam SDK root not specified.`nPass -GenicamRoot <path> or set the GENICAM_ROOT64 / GENICAM_ROOT environment variable."
    exit 1
}
if (-Not (Test-Path $GENICAM_ROOT)) {
    Write-Error "GenICam SDK not found at $GENICAM_ROOT.`nInstall the GenICam SDK and set GENICAM_ROOT64 / GENICAM_ROOT, or pass -GenicamRoot <path>."
    exit 1
}
Write-Host "GenICam root     : $GENICAM_ROOT"
Write-Host "GenICam VC ver   : $VcVersion"

# ============================================================================
# Launch VS Developer Shell (sets cl.exe, link.exe, etc. on PATH)
# ============================================================================
$VSDEVSHELL = Join-Path $vsPath "Common7\Tools\Launch-VsDevShell.ps1"
if (Test-Path $VSDEVSHELL) {
    Write-Host "Launching VS Dev Shell..."
    & $VSDEVSHELL -Arch amd64
} else {
    Write-Error "VS Dev Shell script not found at $VSDEVSHELL"
    exit 1
}

# ============================================================================
# CMake configure + build
# ============================================================================
$BUILD_DIR = "$SRC_DIR\build"
if (Test-Path $BUILD_DIR) {
    Write-Host "Removing existing build directory..."
    Remove-Item -Recurse -Force $BUILD_DIR
}
New-Item -ItemType Directory -Path $BUILD_DIR | Out-Null
Write-Host "Build directory  : $BUILD_DIR"

Write-Host ""
Write-Host "========== CMake Configure =========="
cmake `
    -S "$SRC_DIR" `
    -B "$BUILD_DIR" `
    -DCMAKE_BUILD_TYPE="$BuildType" `
    -DGSTREAMER_ROOT="$GSTREAMER_ROOT" `
    -DGENICAM_ROOT="$GENICAM_ROOT" `
    -DGENICAM_VC_VERSION="$VcVersion"

if ($LASTEXITCODE -ne 0) {
    Write-Error "CMake configure failed (exit code $LASTEXITCODE)"
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "========== CMake Build =========="
cmake --build "$BUILD_DIR" --config "$BuildType" --parallel $env:NUMBER_OF_PROCESSORS

if ($LASTEXITCODE -ne 0) {
    Write-Error "CMake build failed (exit code $LASTEXITCODE)"
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "========== Build Complete =========="
Write-Host "Plugin DLL : $BUILD_DIR\bin\$BuildType\gstgencamsrc.dll"
Write-Host ""
Write-Host "To install, run:"
Write-Host "  cmake --install $BUILD_DIR --config $BuildType"
Write-Host ""
Write-Host "Or copy the DLL manually to your GStreamer plugin directory:"
Write-Host "  $GSTREAMER_ROOT\lib\gstreamer-1.0\"
