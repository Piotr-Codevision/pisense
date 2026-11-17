# PiSense Development

This document describes the development toolchain, environment and related decisions.

## Decisions

### DEV #1: Use CMake as a build system
- **Decision:** CMake (minimum 3.16) with out-of-source builds in `build/`.
- **Rationale:** De-facto standard for C++ projects, broad IDE support, toolchain files
  for cross-compilation, and readily available on Raspberry Pi OS.

### DEV #2: Use clang for cross-platform compilation
- **Status:** TBD — host builds use clang; the Raspberry Pi cross-build setup is not yet
  defined or verified.
- **Decision:** clang/clang++ is the project compiler for both host builds and
  Raspberry Pi cross-builds.
- **Rationale:** A single clang installation can generate code for other architectures via
  `--target=` (e.g. `armv6-linux-gnueabihf` for Pi Zero W). Also offers good diagnostics
  and tooling (clang-format, clang-tidy).
- **Cross-compilation requirements:** `--target=` alone is not sufficient. A Pi build also needs:
  - a **sysroot** with the target's headers and libraries (libc, libstdc++, crt files)
    taken from **Raspberry Pi OS** (ARMv6 hard-float). Stock Debian/Ubuntu `armhf`
    sysroots are built for ARMv7 and produce binaries that crash on the Pi Zero W
    with `SIGILL`;
  - a **linker** capable of targeting ARM, e.g. `lld` (`-fuse-ld=lld`);
  - explicit CPU flags matching the Pi Zero W (e.g. `-mcpu=arm1176jzf-s -mfpu=vfp -mfloat-abi=hard`);
  - a CMake **toolchain file** tying the above together.
- **Note:** The compiler is selected at configure time, not hardcoded in `CMakeLists.txt`.

### DEV #3: Use GoogleTest for host-based unit testing
- **Decision:** GoogleTest (with GoogleMock) is the unit-test framework for
  hardware-independent components, run on the development host via CTest.
- **Rationale:** Widely used, mature C++ test framework; GoogleMock allows replacing
  hardware interfaces with mocks so logic can be tested without a Raspberry Pi.
- **Integration:** An installed GoogleTest (>= 1.11, CMake config package) is used if
  found; otherwise v1.17.0 is fetched at configure time via CMake `FetchContent`
  (pinned URL + SHA256). In the fetch case the first configure needs network access.
- **Scope:** Tests are built when `PISENSE_BUILD_TESTS=ON` (default on host builds,
  off when cross-compiling). Unit tests live in `tests/unit/`.
- **Native builds on the Raspberry Pi:** pass `-DPISENSE_BUILD_TESTS=OFF` — building
  GoogleTest on a Pi Zero W is slow and requires network access.

## Environment

| Component | Required    | Tested locally        |
|-----------|-------------|-----------------------|
| OS (host) | Linux       | Ubuntu (WSL2)         |
| CMake     | >= 3.16     | 4.2.3                 |
| clang     | >= 14       | 21.1.8                |

- **Target:** Raspberry Pi Zero W (ARMv6, Raspberry Pi OS)

## Build (host)

```sh
cmake -S . -B build -DCMAKE_CXX_COMPILER=clang++
cmake --build build
./build/pisense
```

## Unit tests (host)

```sh
cmake -S . -B build -DCMAKE_CXX_COMPILER=clang++
cmake --build build
(cd build && ctest --output-on-failure)
```

- To skip building tests, add `-DPISENSE_BUILD_TESTS=OFF` to the configure command.
- Offline: install GoogleTest (e.g. `libgtest-dev` / `googletest` package providing
  `GTestConfig.cmake`), or point CMake at a pre-downloaded source tree with
  `-DFETCHCONTENT_SOURCE_DIR_GOOGLETEST=<path>`.
