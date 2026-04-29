# gstgencamsrc Windows Port — Project Guidelines

## Overview

GStreamer source plugin for GenICam cameras. Windows port built with CMake + MSVC on top of the upstream Linux autotools build (both coexist).

- Plugin DLL: `C:\dlstreamer_dlls\gstgencamsrc.dll`
- GStreamer: `C:\Program Files\gstreamer\1.0\msvc_x86_64`
- Cameras tested: Basler (serial `24333627`, pylon SDK) and Balluff (serial `FF017289`, Impact Acquire SDK)

## Build

```powershell
cd src-gst-gencamsrc\src-gst-gencamsrc
.\build_gencamsrc.ps1 -GenicamRoot "./plugins/genicam-core/genicam_win/" -VcVersion 120
Copy-Item "build\bin\Release\gstgencamsrc.dll" "C:\dlstreamer_dlls\gstgencamsrc.dll" -Force
```

- GenICam SDK bundled at `plugins\genicam-core\genicam_win\` — all VC120 (VS2013) binaries
- `configure.ac` / `Makefile.am` / `autogen.sh` / `setup.sh` are the Linux autotools build path — do not remove

## Runtime Environment Setup (before gst-inspect / gst-launch)

```powershell
$vc120 = "C:\Users\intel\edge-ai-libraries-main\microservices\dlstreamer-pipeline-server\plugins\camera\src-gst-gencamsrc\plugins\genicam-core\genicam_win\Runtime\bin\Win64_x64"
$gstRoot = "C:\Program Files\gstreamer\1.0\msvc_x86_64"
$dls = "C:\dlstreamer_dlls"
$env:PATH = "$vc120;$gstRoot\bin;$dls;$env:PATH"
$env:GST_PLUGIN_PATH = $dls
$env:GENICAM_GENTL64_PATH = "C:\Program Files\Balluff\ImpactAcquire\bin\x64"
Remove-Item "C:\Temp\gst-registry-clean.bin" -ErrorAction SilentlyContinue
$env:GST_REGISTRY_1_0 = "C:\Temp\gst-registry-clean.bin"
```

**Always delete the GStreamer registry before testing** — stale cache causes "No such element 'gencamsrc'" even when the DLL is valid.

## Key Source Files

| File | Purpose |
|------|---------|
| `plugins\gstgencamsrc.c` | GStreamer plugin registration, element properties |
| `plugins\genicam.cc` | Core camera class; `Genicam::Start()` enumerates and opens device |
| `plugins\genicam-core\rc_genicam_api\gentl_wrapper_win.cc` | Windows CTI loading via `LoadLibraryA` + symbol resolution |
| `plugins\genicam-core\rc_genicam_api\system.cc` | `getSystems()` scans `GENICAM_GENTL64_PATH` for `.cti` files |

## Known Pitfalls — Do Not Repeat

1. **`genicam.cc` try-catch around `rcg::getDevice()` breaks `gst-inspect`** — the try-catch changes the DLL in a way that breaks plugin registration. Do not add it.

2. **`LoadLibraryExA` with `LOAD_WITH_ALTERED_SEARCH_PATH` breaks `gst-inspect`** — reverted; `LoadLibraryA` is correct here.

3. **Stale GStreamer registry** — always `Remove-Item "C:\Temp\gst-registry-clean.bin"` before any `gst-inspect` or `gst-launch` run.

4. **`GST_PLUGIN_SYSTEM_PATH_1_0` is not needed** — GStreamer auto-detects system plugins when `$gstRoot\bin` is in PATH.

## The Balluff Fix (already applied)

**Root cause**: `LoadLibraryA` on `mvGenTLProducer.cti` succeeds, but Balluff's `DllMain` sets Windows error code 183 (ERROR_ALREADY_EXISTS) as a side effect. The subsequent `GetLastError()` check after all `GetProcAddress` calls incorrectly treats this as a symbol resolution failure, discarding the CTI.

**Fix** (`gentl_wrapper_win.cc`): Call `SetLastError(ERROR_SUCCESS)` before the `GetProcAddress` block to clear the stale error.

**Diagnostic** (`system.cc`): Added `std::cerr` warning in the CTI load failure catch block so failures are visible instead of silent.
