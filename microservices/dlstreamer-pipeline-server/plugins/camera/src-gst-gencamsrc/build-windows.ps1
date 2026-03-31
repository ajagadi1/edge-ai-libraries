# Build gencamsrc for Windows
#
# This script builds the gencamsrc GStreamer plugin for Windows
#
# Prerequisites:
# - Visual Studio Build Tools 2019 or later (with C++ support) OR full Visual Studio
# - CMake 3.15 or later
# - GStreamer for Windows (installed via DL Streamer)
# - GenICam runtime libraries
# - GenTL producer (e.g., Basler Pylon, Balluff mvIMPACT)

param(
    [string]$GenicamRoot = "",
    [string]$GentlPath = "",
    [string]$BuildType = "Release",
    [string]$Generator = "Visual Studio 17 2022",
    [string]$BuildDir = "build-windows"
)

$ErrorActionPreference = "Stop"

Write-Host "=== gencamsrc Windows Build Script ===" -ForegroundColor Cyan

# Check for required tools
Write-Host "`nChecking prerequisites..." -ForegroundColor Yellow

# Check CMake
$cmake = Get-Command cmake -ErrorAction SilentlyContinue
if (-not $cmake) {
    Write-Error "CMake not found. Please install CMake 3.15 or later."
}
Write-Host "  CMake: $($cmake.Version)" -ForegroundColor Green

# Check for Visual Studio (Build Tools or full IDE)
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -property installationPath
    $vsProduct = & $vswhere -latest -property productId
    Write-Host "  Visual Studio: $vsPath" -ForegroundColor Green
    Write-Host "  Product: $vsProduct" -ForegroundColor Green
} else {
    Write-Warning "  Visual Studio/Build Tools not detected via vswhere (might use MinGW)"
}

# Check for GStreamer
if ($env:GSTREAMER_ROOT_X86_64) {
    Write-Host "  GStreamer: $env:GSTREAMER_ROOT_X86_64" -ForegroundColor Green
} else {
    Write-Warning "  GSTREAMER_ROOT_X86_64 not set. Assuming C:\gstreamer"
    $env:GSTREAMER_ROOT_X86_64 = "C:\gstreamer"
}

# Prompt for GenICam root if not provided
if (-not $GenicamRoot) {
    Write-Host "`nGenICam root directory not specified." -ForegroundColor Yellow
    Write-Host "Examples:"
    Write-Host "  - C:\Program Files\Basler\pylon 7\Runtime"
    Write-Host "  - C:\GenICam"
    Write-Host "  - C:\mvIMPACT_Acquire"
    $GenicamRoot = Read-Host "Enter GenICam root path (or press Enter to use plugins/genicam-core/genicam)"
    
    if (-not $GenicamRoot) {
        $GenicamRoot = "$PSScriptRoot\plugins\genicam-core\genicam"
        Write-Host "Using embedded GenICam: $GenicamRoot" -ForegroundColor Cyan
    }
}

if (-not (Test-Path $GenicamRoot)) {
    Write-Error "GenICam root directory not found: $GenicamRoot"
}

# Prompt for GenTL path if not provided
if (-not $GentlPath) {
    Write-Host "`nGenTL producer path not specified." -ForegroundColor Yellow
    Write-Host "Examples:"
    Write-Host "  - C:\Program Files\Basler\pylon 7\Runtime\x64"
    Write-Host "  - C:\Program Files\Balluff\Impact_Acquire\lib\x86_64"
    $GentlPath = Read-Host "Enter GenTL producer path (or press Enter to skip)"
}

# Create build directory
Write-Host "`nCreating build directory: $BuildDir" -ForegroundColor Yellow
if (Test-Path $BuildDir) {
    Write-Host "Build directory exists, cleaning..." -ForegroundColor Cyan
    Remove-Item -Path $BuildDir -Recurse -Force
}
New-Item -ItemType Directory -Path $BuildDir | Out-Null

# Configure with CMake
Write-Host "`nConfiguring with CMake..." -ForegroundColor Yellow
Push-Location $BuildDir

try {
    $cmakeArgs = @(
        "..",
        "-G", $Generator,
        "-A", "x64",
        "-DCMAKE_BUILD_TYPE=$BuildType",
        "-DGENICAM_ROOT=$GenicamRoot"
    )
    
    if ($GentlPath) {
        $cmakeArgs += "-DGENICAM_GENTL_PATH=$GentlPath"
    }
    
    Write-Host "Running: cmake $($cmakeArgs -join ' ')" -ForegroundColor Cyan
    & cmake @cmakeArgs
    
    if ($LASTEXITCODE -ne 0) {
        throw "CMake configuration failed"
    }
    
    # Build
    Write-Host "`nBuilding..." -ForegroundColor Yellow
    & cmake --build . --config $BuildType
    
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed"
    }
    
    Write-Host "`n=== Build Successful ===" -ForegroundColor Green
    Write-Host "`nPlugin location: $BuildDir\$BuildType\gstgencamsrc.dll" -ForegroundColor Cyan
    
    # Display installation instructions
    Write-Host "`n=== Installation Instructions ===" -ForegroundColor Cyan
    Write-Host "1. Install the plugin:"
    Write-Host "   cmake --install . --config $BuildType" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "2. Or manually copy to GStreamer plugin directory:"
    if ($env:GSTREAMER_ROOT_X86_64) {
        Write-Host "   copy $BuildType\gstgencamsrc.dll `"$env:GSTREAMER_ROOT_X86_64\lib\gstreamer-1.0\`"" -ForegroundColor Yellow
    } else {
        Write-Host "   copy $BuildType\gstgencamsrc.dll C:\gstreamer\lib\gstreamer-1.0\" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "3. Set environment variables:"
    if ($GentlPath) {
        Write-Host "   `$env:GENICAM_GENTL64_PATH = `"$GentlPath`"" -ForegroundColor Yellow
    } else {
        Write-Host "   `$env:GENICAM_GENTL64_PATH = `"<path-to-gentl-producer>`"" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "4. Verify installation:"
    Write-Host "   gst-inspect-1.0 gencamsrc" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "5. Test with a camera:"
    Write-Host "   gst-launch-1.0 gencamsrc serial=YOUR_CAMERA_SERIAL ! videoconvert ! autovideosink" -ForegroundColor Yellow
    Write-Host ""
    
} finally {
    Pop-Location
}

Write-Host "`n=== Build Complete ===" -ForegroundColor Green
