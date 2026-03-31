# Building gencamsrc for Windows

Build the gencamsrc GStreamer plugin to use GenICam cameras with DL Streamer on Windows.

## Quick Start

```powershell
# 1. Install DL Streamer (includes GStreamer)
# Download from: https://github.com/open-edge-platform/edge-ai-libraries/releases
cd C:\dlstreamer_dlls
.\setup_dls_env.ps1

# 2. Build gencamsrc
cd path\to\src-gst-gencamsrc
.\build-windows.ps1

# 3. Set GenTL path (required for camera detection)
$env:GENICAM_GENTL64_PATH = "C:\Program Files\Basler\pylon 7\Runtime\x64"

# 4. Test
gst-inspect-1.0 gencamsrc
gst-launch-1.0 gencamsrc serial=YOUR_CAMERA_SERIAL ! videoconvert ! autovideosink
```

## Prerequisites

1. **DL Streamer** (includes GStreamer)
   - Download: https://github.com/open-edge-platform/edge-ai-libraries/releases
   - Extract and run `setup_dls_env.ps1`

2. **Visual Studio Build Tools** (free C++ compiler, ~7GB)
   - Download: https://visualstudio.microsoft.com/downloads/ → "Build Tools for Visual Studio"
   - Select: "Desktop development with C++"

3. **CMake 3.15+**
   - `winget install Kitware.CMake` or download from cmake.org

4. **Camera SDK** (includes GenICam + GenTL producer)
   - **Basler**: Download Pylon from https://www.baslerweb.com/
   - **Balluff**: Download mvIMPACT Acquire
   - **FLIR**: Download Spinnaker SDK

## Common Camera Vendor Paths

| Vendor | GENICAM_ROOT | GENICAM_GENTL64_PATH |
|--------|-------------|---------------------|
| **Basler Pylon** | `C:\Program Files\Basler\pylon 7\Runtime` | `C:\Program Files\Basler\pylon 7\Runtime\x64` |
| **Balluff** | `C:\mvIMPACT_Acquire` | `C:\mvIMPACT_Acquire\lib\x86_64` |
| **FLIR Spinnaker** | `C:\Program Files\FLIR Systems\Spinnaker` | `C:\Program Files\FLIR Systems\Spinnaker\cti64\vs2015` |

## Build Instructions

**PowerShell Script (Easy):**
```powershell
cd src-gst-gencamsrc
.\build-windows.ps1
```
Script will prompt for camera SDK paths if needed.

**Manual Build:**
```cmd
mkdir build && cd build
cmake .. -G "Visual Studio 17 2022" -A x64 -DCMAKE_BUILD_TYPE=Release -DGENICAM_ROOT="C:\Program Files\Basler\pylon 7\Runtime"
cmake --build . --config Release
cmake --install .
```

## Environment Setup

**Required:**
```powershell
$env:GENICAM_GENTL64_PATH = "C:\Program Files\Basler\pylon 7\Runtime\x64"
```

**To make permanent (admin PowerShell):**
```powershell
[System.Environment]::SetEnvironmentVariable("GENICAM_GENTL64_PATH", "C:\Program Files\Basler\pylon 7\Runtime\x64", "Machine")
```

## Verify & Test

```powershell
# Verify plugin installed
gst-inspect-1.0 gencamsrc

# Test camera (find serial number using vendor's camera viewer)
gst-launch-1.0 gencamsrc serial=22034422 ! videoconvert ! autovideosink

# With DL Streamer inference
gst-launch-1.0 gencamsrc serial=22034422 ! gvadetect model=model.xml ! gvawatermark ! autovideosink
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| **Plugin not found** | Check: `dir "C:\gstreamer\lib\gstreamer-1.0\gstgencamsrc.dll"`<br>Set: `$env:GST_PLUGIN_PATH = "C:\gstreamer\lib\gstreamer-1.0"` |
| **No transport layers** | Check: `dir "$env:GENICAM_GENTL64_PATH\*.cti"`<br>Set: `$env:GENICAM_GENTL64_PATH = "C:\...\pylon 7\Runtime\x64"` |
| **Missing GenICam DLLs** | Copy from camera SDK: `copy "C:\...\pylon\Runtime\x64\*.dll" C:\gstreamer\bin\` |
| **Camera not detected** | Test with vendor's viewer first (e.g., Pylon Viewer, mvIMPACT viewer) |
| **Build fails** | Open "x64 Native Tools Command Prompt for VS" before running cmake |

**Enable debug output:**
```powershell
$env:GST_DEBUG = "gencamsrc:5"
gst-launch-1.0 gencamsrc serial=22034422 ! videoconvert ! autovideosink
```

## Additional Resources

**DL Streamer Documentation:**
- **Installation (Pre-built)**: https://docs.openedgeplatform.intel.com/dev/edge-ai-libraries/dlstreamer/get_started/install/install_guide_windows.html
- **Build from Source**: https://docs.openedgeplatform.intel.com/dev/edge-ai-libraries/dlstreamer/dev_guide/advanced_install/advanced_install_on_windows.html
- Tutorial: https://docs.openedgeplatform.intel.com/dev/edge-ai-libraries/dlstreamer/get_started/tutorial.html

**Other Resources:**
- GStreamer Windows Documentation: https://gstreamer.freedesktop.org/documentation/installing/on-windows.html
- GenICam Standard: https://www.emva.org/standards-technology/genicam/

**Camera Vendor SDKs:**
- Basler Pylon: https://www.baslerweb.com/
- Balluff: https://www.balluff.com/
- FLIR Spinnaker: https://www.flir.com/

## Can I Cross-Compile from Linux?

**Short answer: Not recommended.**

While cross-compilation from Ubuntu to Windows is technically possible using MinGW-w64, it's **more effort than building natively** because you'd need:

1. **MinGW-w64 cross-compiler toolchain** on Linux
2. **Windows versions of all dependencies**:
   - GStreamer Windows libraries
   - GenICam Windows libraries  
   - Camera SDK Windows libraries
3. **CMake toolchain file** for cross-compilation
4. **Manual dependency management** (pkg-config won't work across platforms)

**Better alternatives:**

- **Build natively on Windows** (5 minutes with the PowerShell script)
- **Use WSL2** with X11 forwarding if you want to stay on Linux (but camera hardware access is limited)
- **Use a Windows VM** if you don't have native Windows access

**For Linux deployment:** Just build on Linux normally - no cross-compilation needed!

## Technical Notes

### Why gentl_wrapper_windows.cc?

The original code has `gentl_wrapper_linux.cc` which uses Linux-specific APIs that don't exist on Windows:

- **Linux**: Uses `dlopen()`, `dlsym()`, `dlerror()` for loading `.so` libraries
- **Windows**: Uses `LoadLibrary()`, `GetProcAddress()`, `GetLastError()` for loading `.dll`/`.cti` files

Other platform differences:
- Path separators: Linux uses `:` in PATH-like variables, Windows uses `;`
- File search APIs: Linux uses `opendir/readdir`, Windows uses `FindFirstFile/FindNextFile`
- Directory separators: Linux `/`, Windows `\`

The Windows version (`gentl_wrapper_windows.cc`) is required for the plugin to compile and run on Windows.

## License

See LICENSE file in the project root for licensing information.
