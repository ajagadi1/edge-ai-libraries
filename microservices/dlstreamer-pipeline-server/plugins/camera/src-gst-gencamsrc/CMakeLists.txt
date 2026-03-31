cmake_minimum_required(VERSION 3.15)
project(gst-gencamsrc VERSION 1.3.0 LANGUAGES C CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Options for configuration
option(BUILD_SHARED_LIBS "Build shared libraries" ON)

# Platform detection
if(WIN32)
    set(PLATFORM_WINDOWS TRUE)
elseif(UNIX AND NOT APPLE)
    set(PLATFORM_LINUX TRUE)
endif()

# Find required packages
find_package(PkgConfig REQUIRED)

# Find GStreamer
pkg_check_modules(GSTREAMER REQUIRED 
    gstreamer-1.0>=1.0.0
    gstreamer-base-1.0>=1.0.0
    gstreamer-controller-1.0>=1.0.0
)

# GenICam configuration
set(GENICAM_ROOT "" CACHE PATH "GenICam root directory (e.g., C:/GenICam)")
set(GENICAM_GENTL_PATH "" CACHE PATH "GenTL producer path (e.g., C:/Pylon/Runtime/x64)")

if(NOT GENICAM_ROOT)
    message(FATAL_ERROR "GENICAM_ROOT must be set to GenICam installation directory")
endif()

# GenICam include directories
set(GENICAM_INCLUDE_DIR "${GENICAM_ROOT}/include")
if(NOT EXISTS "${GENICAM_INCLUDE_DIR}")
    set(GENICAM_INCLUDE_DIR "${PROJECT_SOURCE_DIR}/plugins/genicam-core/genicam/include")
endif()

# GenICam library configuration based on platform
if(PLATFORM_WINDOWS)
    # Windows GenICam libraries (adjust version suffix based on your GenICam version)
    # Common suffixes: MD_VC141_v3_1, MD_VC142_v3_1, MD_VC143_v3_1
    set(GENICAM_LIB_SUFFIX "MD_VC141_v3_1" CACHE STRING "GenICam library suffix")
    set(GENICAM_BIN_DIR "${GENICAM_ROOT}/bin/Win64_x64")
    
    set(GENICAM_LIBRARIES
        "${GENICAM_BIN_DIR}/GenApi_${GENICAM_LIB_SUFFIX}.lib"
        "${GENICAM_BIN_DIR}/GCBase_${GENICAM_LIB_SUFFIX}.lib"
        "${GENICAM_BIN_DIR}/Log_${GENICAM_LIB_SUFFIX}.lib"
        "${GENICAM_BIN_DIR}/MathParser_${GENICAM_LIB_SUFFIX}.lib"
        "${GENICAM_BIN_DIR}/XmlParser_${GENICAM_LIB_SUFFIX}.lib"
        "${GENICAM_BIN_DIR}/NodeMapData_${GENICAM_LIB_SUFFIX}.lib"
    )
    
    # Windows-specific defines
    add_compile_definitions(
        _WINDOWS
        WIN32_LEAN_AND_MEAN
        NOMINMAX
    )
    
    set(GENTL_WRAPPER_SOURCE "plugins/genicam-core/rc_genicam_api/gentl_wrapper_windows.cc")
    
elseif(PLATFORM_LINUX)
    # Linux GenICam libraries
    set(GENICAM_BIN_DIR "${GENICAM_ROOT}/bin/Linux64_x64")
    if(NOT EXISTS "${GENICAM_BIN_DIR}")
        set(GENICAM_BIN_DIR "/usr/lib/x86_64-linux-gnu")
    endif()
    
    set(GENICAM_LIBRARIES
        "-lGenApi_gcc7_v3_1"
        "-lGCBase_gcc7_v3_1"
        "-llog4cpp_gcc7_v3_1"
        "-lLog_gcc7_v3_1"
        "-lMathParser_gcc7_v3_1"
        "-lXmlParser_gcc7_v3_1"
        "-lNodeMapData_gcc7_v3_1"
    )
    
    set(GENTL_WRAPPER_SOURCE "plugins/genicam-core/rc_genicam_api/gentl_wrapper_linux.cc")
endif()

# Check if GenTL wrapper exists, otherwise use the Linux one as template
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${GENTL_WRAPPER_SOURCE}")
    message(WARNING "Platform-specific GenTL wrapper not found. Using gentl_wrapper_linux.cc")
    set(GENTL_WRAPPER_SOURCE "plugins/genicam-core/rc_genicam_api/gentl_wrapper_linux.cc")
endif()

#
# Build rc_genicam_api library
#
add_library(genicamapi STATIC
    plugins/genicam-core/rc_genicam_api/buffer.cc
    plugins/genicam-core/rc_genicam_api/buffer.h
    plugins/genicam-core/rc_genicam_api/config.cc
    plugins/genicam-core/rc_genicam_api/config.h
    plugins/genicam-core/rc_genicam_api/cport.cc
    plugins/genicam-core/rc_genicam_api/cport.h
    plugins/genicam-core/rc_genicam_api/device.cc
    plugins/genicam-core/rc_genicam_api/device.h
    plugins/genicam-core/rc_genicam_api/exception.cc
    plugins/genicam-core/rc_genicam_api/exception.h
    plugins/genicam-core/rc_genicam_api/gentl_wrapper.h
    ${GENTL_WRAPPER_SOURCE}
    plugins/genicam-core/rc_genicam_api/image.cc
    plugins/genicam-core/rc_genicam_api/image.h
    plugins/genicam-core/rc_genicam_api/imagelist.cc
    plugins/genicam-core/rc_genicam_api/imagelist.h
    plugins/genicam-core/rc_genicam_api/image_store.cc
    plugins/genicam-core/rc_genicam_api/image_store.h
    plugins/genicam-core/rc_genicam_api/interface.cc
    plugins/genicam-core/rc_genicam_api/interface.h
    plugins/genicam-core/rc_genicam_api/pixel_formats.h
    plugins/genicam-core/rc_genicam_api/pointcloud.cc
    plugins/genicam-core/rc_genicam_api/pointcloud.h
    plugins/genicam-core/rc_genicam_api/stream.cc
    plugins/genicam-core/rc_genicam_api/stream.h
    plugins/genicam-core/rc_genicam_api/system.cc
    plugins/genicam-core/rc_genicam_api/system.h
)

target_include_directories(genicamapi
    PUBLIC
        ${GENICAM_INCLUDE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/plugins/genicam-core/rc_genicam_api
)

target_link_directories(genicamapi
    PUBLIC
        ${GENICAM_BIN_DIR}
)

if(PLATFORM_WINDOWS)
    target_link_libraries(genicamapi
        PUBLIC
            ${GENICAM_LIBRARIES}
    )
else()
    target_link_libraries(genicamapi
        PUBLIC
            ${GENICAM_LIBRARIES}
            ${CMAKE_DL_LIBS}
    )
endif()

#
# Build gencamsrc GStreamer plugin
#
add_library(gstgencamsrc MODULE
    plugins/gstgencamsrc.c
    plugins/gstgencamsrc.h
    plugins/gencambase.cc
    plugins/gencambase.h
    plugins/genicam.cc
    plugins/genicam.h
)

# Set the plugin naming convention
set_target_properties(gstgencamsrc PROPERTIES
    PREFIX ""
    OUTPUT_NAME "gstgencamsrc"
)

if(PLATFORM_WINDOWS)
    # Windows: plugins are DLLs
    set_target_properties(gstgencamsrc PROPERTIES
        SUFFIX ".dll"
    )
else()
    # Linux: plugins are .so files
    set_target_properties(gstgencamsrc PROPERTIES
        SUFFIX ".so"
    )
endif()

target_include_directories(gstgencamsrc
    PRIVATE
        ${GSTREAMER_INCLUDE_DIRS}
        ${CMAKE_CURRENT_SOURCE_DIR}/plugins
        ${CMAKE_CURRENT_SOURCE_DIR}/plugins/genicam-core/rc_genicam_api
        ${GENICAM_INCLUDE_DIR}
)

target_link_directories(gstgencamsrc
    PRIVATE
        ${GSTREAMER_LIBRARY_DIRS}
)

target_link_libraries(gstgencamsrc
    PRIVATE
        ${GSTREAMER_LIBRARIES}
        genicamapi
)

# Compile options
if(MSVC)
    target_compile_options(gstgencamsrc PRIVATE /W3)
    target_compile_options(genicamapi PRIVATE /W3)
else()
    target_compile_options(gstgencamsrc PRIVATE -Wall)
    target_compile_options(genicamapi PRIVATE -Wall)
endif()

#
# Installation
#
# Determine GStreamer plugin installation directory
if(PLATFORM_WINDOWS)
    # On Windows, install to GStreamer plugin directory
    if(DEFINED ENV{GSTREAMER_ROOT_X86_64})
        set(GST_PLUGIN_DIR "$ENV{GSTREAMER_ROOT_X86_64}/lib/gstreamer-1.0")
    else()
        set(GST_PLUGIN_DIR "C:/gstreamer/lib/gstreamer-1.0")
    endif()
else()
    # On Linux, use standard paths
    if(CMAKE_INSTALL_PREFIX STREQUAL "$ENV{HOME}")
        set(GST_PLUGIN_DIR "$ENV{HOME}/.gstreamer-1.0/plugins")
    else()
        set(GST_PLUGIN_DIR "${CMAKE_INSTALL_PREFIX}/lib/gstreamer-1.0")
    endif()
endif()

# Allow user to override plugin directory
set(GSTREAMER_PLUGIN_DIR "${GST_PLUGIN_DIR}" CACHE PATH "GStreamer plugin installation directory")

install(TARGETS gstgencamsrc
    LIBRARY DESTINATION ${GSTREAMER_PLUGIN_DIR}
    RUNTIME DESTINATION ${GSTREAMER_PLUGIN_DIR}
)

# Install GenICam runtime dependencies on Windows
if(PLATFORM_WINDOWS AND EXISTS "${GENICAM_BIN_DIR}")
    file(GLOB GENICAM_DLLS "${GENICAM_BIN_DIR}/*.dll")
    install(FILES ${GENICAM_DLLS}
        DESTINATION ${GSTREAMER_PLUGIN_DIR}
    )
endif()

#
# Print configuration summary
#
message(STATUS "")
message(STATUS "=== gst-gencamsrc Configuration ===")
message(STATUS "Version: ${PROJECT_VERSION}")
message(STATUS "Platform: ${CMAKE_SYSTEM_NAME}")
message(STATUS "C++ Compiler: ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
message(STATUS "")
message(STATUS "GStreamer:")
message(STATUS "  Include dirs: ${GSTREAMER_INCLUDE_DIRS}")
message(STATUS "  Libraries: ${GSTREAMER_LIBRARIES}")
message(STATUS "")
message(STATUS "GenICam:")
message(STATUS "  Root: ${GENICAM_ROOT}")
message(STATUS "  Include dir: ${GENICAM_INCLUDE_DIR}")
message(STATUS "  Binary dir: ${GENICAM_BIN_DIR}")
message(STATUS "  Libraries: ${GENICAM_LIBRARIES}")
message(STATUS "")
message(STATUS "Installation:")
message(STATUS "  Plugin directory: ${GSTREAMER_PLUGIN_DIR}")
if(GENICAM_GENTL_PATH)
    message(STATUS "  GenTL path: ${GENICAM_GENTL_PATH}")
endif()
message(STATUS "")
message(STATUS "Build configuration:")
message(STATUS "  Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "  Shared libs: ${BUILD_SHARED_LIBS}")
message(STATUS "")
message(STATUS "==================================")
message(STATUS "")
