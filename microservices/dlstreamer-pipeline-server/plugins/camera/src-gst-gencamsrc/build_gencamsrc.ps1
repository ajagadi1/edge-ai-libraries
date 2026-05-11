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
#   .\build_gencamsrc.ps1 -FetchGenicamSdk          # download SDK automatically
# ==============================================================================

param(
    [string]$GenicamRoot     = "",
    [string]$VcVersion       = "120",   # 120=VS2013, 141=VS2017, 142=VS2019, 143=VS2022
    [string]$BuildType       = "Release",
    [switch]$FetchGenicamSdk              # download EMVA GenICam SDK v3.1 automatically
)

$ErrorActionPreference = "Stop"
$SRC_DIR = $PSScriptRoot

# ============================================================================
# Fetch GenICam SDK (auto-triggered when bundled folder is absent and no
# -GenicamRoot / env var is provided, or when -FetchGenicamSdk is passed)
# ============================================================================
$BUNDLED_GENICAM = "$SRC_DIR\plugins\genicam-core\genicam_win"

$needFetch = $FetchGenicamSdk -or (
    ($GenicamRoot -eq "") -and
    (-Not $env:GENICAM_ROOT64) -and
    (-Not $env:GENICAM_ROOT) -and
    (-Not (Test-Path $BUNDLED_GENICAM))
)

if ($needFetch) {
    # EMVA GenICam Package 2018.06 contains GenApi 3.1.0 + VC120 binaries
    $GENICAM_DOWNLOAD_URL = "https://www.emva.org/wp-content/uploads/GenICam_Package_2018.06.zip"
    $GENICAM_ZIP          = "$env:TEMP\GenICam_Package_2018.06.zip"
    $GENICAM_EXTRACT_DIR  = "$env:TEMP\genicam_extract_$PID"

    Write-Host ""
    Write-Host "========== Fetching GenICam SDK =========="
    Write-Host "URL    : $GENICAM_DOWNLOAD_URL"
    Write-Host "Target : $BUNDLED_GENICAM"

    try {
        if (-Not (Test-Path $GENICAM_ZIP)) {
            Write-Host "Downloading..."
            Invoke-WebRequest -Uri $GENICAM_DOWNLOAD_URL -OutFile $GENICAM_ZIP -UseBasicParsing
        } else {
            Write-Host "Using cached zip: $GENICAM_ZIP"
        }

        Write-Host "Extracting..."
        if (Test-Path $GENICAM_EXTRACT_DIR) { Remove-Item -Recurse -Force $GENICAM_EXTRACT_DIR }
        Expand-Archive -Path $GENICAM_ZIP -DestinationPath $GENICAM_EXTRACT_DIR -Force

        # Probe the extracted layout:
        #   Case A: Dev\ and Runtime\ sit directly inside the extract dir
        #   Case B: a single top-level subdirectory wraps them
        $devDir     = Join-Path $GENICAM_EXTRACT_DIR "Dev"
        $runtimeDir = Join-Path $GENICAM_EXTRACT_DIR "Runtime"

        if (-Not (Test-Path $devDir)) {
            # Look one level deeper
            $topItems = Get-ChildItem $GENICAM_EXTRACT_DIR -Directory
            if ($topItems.Count -eq 1) {
                $subdirRoot = $topItems[0].FullName
                $devDir     = Join-Path $subdirRoot "Dev"
                $runtimeDir = Join-Path $subdirRoot "Runtime"
            }
        }

        if (-Not (Test-Path $devDir)) {
            Write-Host "Extracted contents:"
            Get-ChildItem $GENICAM_EXTRACT_DIR | ForEach-Object { Write-Host "  $_" }
            throw "Cannot locate Dev\ inside the GenICam zip.  Unexpected layout - please inspect the extracted folder and re-run with -GenicamRoot <path>."
        }

        # Assemble genicam_win from extracted Dev + Runtime
        if (Test-Path $BUNDLED_GENICAM) { Remove-Item -Recurse -Force $BUNDLED_GENICAM }
        New-Item -ItemType Directory -Path $BUNDLED_GENICAM | Out-Null
        Copy-Item $devDir     -Destination "$BUNDLED_GENICAM\Dev"     -Recurse -Force
        Copy-Item $runtimeDir -Destination "$BUNDLED_GENICAM\Runtime" -Recurse -Force

        # Verify version header
        $verHeader = "$BUNDLED_GENICAM\Dev\library\CPP\include\_GenICamVersion.h"
        if (Test-Path $verHeader) {
            $verText = Get-Content $verHeader -Raw
            Write-Host "GenICam version info:"
            $verText -split "`n" | Where-Object { $_ -match 'VERSION|COMPILER|REVISION' } | ForEach-Object { Write-Host "  $_" }
        } else {
            Write-Warning "_GenICamVersion.h not found - zip structure may differ from expected."
        }

        Write-Host "GenICam SDK extracted to: $BUNDLED_GENICAM"
    } catch {
        Write-Error "GenICam SDK fetch failed: $_`n`nManual download: $GENICAM_DOWNLOAD_URL`nExtract Dev\ and Runtime\ into: $BUNDLED_GENICAM"
        exit 1
    } finally {
        if (Test-Path $GENICAM_EXTRACT_DIR) { Remove-Item -Recurse -Force $GENICAM_EXTRACT_DIR }
    }

    # Override GenicamRoot so the locate block below uses the freshly fetched SDK
    $GenicamRoot = $BUNDLED_GENICAM
}

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
} elseif (Test-Path $BUNDLED_GENICAM) {
    # Fall back to the bundled SDK inside the repository
    $GENICAM_ROOT = $BUNDLED_GENICAM
    Write-Host "Using bundled GenICam SDK at: $GENICAM_ROOT"
} else {
    Write-Error "GenICam SDK root not specified.`nOptions:`n  1. Pass -GenicamRoot <path>`n  2. Set GENICAM_ROOT64 / GENICAM_ROOT environment variable`n  3. Pass -FetchGenicamSdk to download automatically`n  4. Manually place the SDK at: $BUNDLED_GENICAM"
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
