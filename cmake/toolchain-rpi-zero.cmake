# CMake toolchain file: cross-compile for Raspberry Pi Zero W (ARMv6, hard-float,
# Raspberry Pi OS Bullseye) with clang and lld. See DEV #2 in docs/development.md.
#
# Usage:
#   scripts/sync-sysroot.sh
#   cmake -S . -B build-rpi -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-rpi-zero.cmake
#
# The sysroot location is taken from -DRPI_SYSROOT=..., the RPI_SYSROOT environment
# variable, or defaults to $HOME/rpi-sysroot.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR armv6l)

# --- Sysroot -----------------------------------------------------------------------
if(NOT RPI_SYSROOT)
    if(DEFINED ENV{RPI_SYSROOT})
        set(RPI_SYSROOT "$ENV{RPI_SYSROOT}")
    else()
        set(RPI_SYSROOT "$ENV{HOME}/rpi-sysroot")
    endif()
endif()
set(RPI_SYSROOT "${RPI_SYSROOT}" CACHE PATH "Raspberry Pi sysroot directory")

if(NOT EXISTS "${RPI_SYSROOT}/usr/include/stdio.h")
    message(FATAL_ERROR "Raspberry Pi sysroot not found in '${RPI_SYSROOT}'. "
                        "Run scripts/sync-sysroot.sh or set RPI_SYSROOT.")
endif()

set(CMAKE_SYSROOT "${RPI_SYSROOT}")
# Pass the sysroot location on to CMake's internal try_compile projects.
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES RPI_SYSROOT)

# --- Compiler ------------------------------------------------------------------------
set(RPI_TRIPLE arm-linux-gnueabihf)

set(CMAKE_C_COMPILER clang)
set(CMAKE_CXX_COMPILER clang++)
set(CMAKE_C_COMPILER_TARGET ${RPI_TRIPLE})
set(CMAKE_CXX_COMPILER_TARGET ${RPI_TRIPLE})

# Pi Zero W: ARM1176JZF-S core, ARMv6 with VFPv2, hard-float ABI.
set(RPI_CPU_FLAGS "-mcpu=arm1176jzf-s -mfpu=vfp -mfloat-abi=hard -marm")
set(CMAKE_C_FLAGS_INIT "${RPI_CPU_FLAGS}")
set(CMAKE_CXX_FLAGS_INIT "${RPI_CPU_FLAGS}")

# --- Linker --------------------------------------------------------------------------
find_program(RPI_LLD
    NAMES ld.lld ld.lld-21 ld.lld-20 ld.lld-19 ld.lld-18 ld.lld-17 ld.lld-16 ld.lld-15 ld.lld-14
    NO_CMAKE_FIND_ROOT_PATH)
if(NOT RPI_LLD)
    message(FATAL_ERROR "lld linker not found; install lld (e.g. 'sudo apt install lld')")
endif()

set(CMAKE_EXE_LINKER_FLAGS_INIT "--ld-path=${RPI_LLD}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "--ld-path=${RPI_LLD}")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "--ld-path=${RPI_LLD}")

# --- Search paths ----------------------------------------------------------------------
# Host programs (clang-format, clang-tidy, ...) come from the host; libraries, headers
# and packages only from the sysroot.
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
