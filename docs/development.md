# PiSense Development

This document describes the development toolchain, environment and related decisions.

## Decisions

### DEV #1: Use CMake as a build system
- **Decision:** CMake (minimum 3.16) with out-of-source builds in `build/`.
- **Rationale:** De-facto standard for C++ projects, broad IDE support, toolchain files
  for cross-compilation, and readily available on Raspberry Pi OS.

### DEV #2: Use clang for cross-platform compilation
- **Status:** Accepted — cross-build verified on a Raspberry Pi Zero W (Raspbian 11
  Bullseye) on 2026-11-17.
- **Decision:** clang/clang++ is the project compiler for both host builds and
  Raspberry Pi cross-builds; Pi binaries are linked with lld against a sysroot copied
  from the target.
- **Rationale:** A single clang installation can generate code for other architectures via
  `--target=`, so no separate GCC ARM toolchain is needed. Also offers good diagnostics
  and tooling (clang-format, clang-tidy).
- **Cross-compilation setup:**
  - **Toolchain file** `cmake/toolchain-rpi-zero.cmake`: target `arm-linux-gnueabihf`,
    CPU flags `-mcpu=arm1176jzf-s -mfpu=vfp -mfloat-abi=hard -marm`, linker
    `--ld-path=<ld.lld>`, libraries/headers searched only in the sysroot.
  - **Sysroot** copied from the Pi by `scripts/sync-sysroot.sh` (`/usr/include`,
    `/usr/lib/arm-linux-gnueabihf`, `/usr/lib/gcc/arm-linux-gnueabihf/<gcc>`, the dynamic
    loader); absolute symlinks are rewritten to stay inside the sysroot. It must come from
    **Raspberry Pi OS**: stock Debian/Ubuntu `armhf` sysroots are built for ARMv7 and
    produce binaries that crash on the Pi Zero W with `SIGILL`.
  - Binaries link against the Pi's own glibc/libstdc++, so they never require newer
    versions than the target has.
  - `scripts/deploy.sh` copies the binary to the Pi and optionally runs it.
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

### DEV #4: Use clang-format for code style
- **Decision:** All C++ sources are formatted with clang-format using the repository's
  `.clang-format`: LLVM base style, Stroustrup braces (own line for function definitions,
  and for `else`/`catch`; same line for `if`/`for`/`class`), 4-space indent, 100 columns.
- **Rationale:** Consistent style enforced by a tool instead of reviews; ships with the
  clang toolchain (DEV #2); supported by all major editors (format on save).
- **Usage:** CMake targets `format` (rewrites files) and `format-check` (fails on
  unformatted code). They are only available if clang-format is found at configure time.

### DEV #5: Use clang-tidy for static code analysis
- **Decision:** C++ sources are analyzed with clang-tidy using the repository's
  `.clang-tidy`. Enabled check groups: `bugprone`, `clang-analyzer`, `cppcoreguidelines`,
  `misc`, `modernize`, `performance`, `portability`, `readability`. A few noisy checks are
  disabled (magic numbers, trailing return types, identifier length, include-cleaner,
  easily-swappable parameters, non-private members). `tests/.clang-tidy` additionally
  disables checks triggered by GoogleTest macros.
- **Rationale:** Catches bugs and outdated or unsafe constructs early; part of the clang
  toolchain (DEV #2); works on the compilation database produced by CMake (DEV #1).
- **Usage:**
  - `tidy` target: analyzes all project sources on demand.
  - `PISENSE_ENABLE_CLANG_TIDY=ON` (default OFF): runs clang-tidy during compilation of
    project targets (`pisense`, `pisense_unit_tests`); third-party code is not analyzed.
  - Findings are warnings, not errors, for now; this may be tightened once the codebase
    grows.

## Environment

| Component    | Required | Tested locally |
|--------------|----------|----------------|
| OS (host)    | Linux    | Ubuntu (WSL2)  |
| CMake        | >= 3.16  | 4.2.3          |
| clang        | >= 14    | 21.1.8         |
| clang-format | >= 14    | 21.1.8         |
| clang-tidy   | >= 14    | 21.1.8         |
| lld          | >= 14    | 18.1.8         |

### Target (Raspberry Pi Zero W, checked 2026-11-17)

| Item          | Value                                                  |
|---------------|--------------------------------------------------------|
| Board         | Raspberry Pi Zero W Rev 1.1                            |
| OS            | Raspbian GNU/Linux 11 (Bullseye), 32-bit `armhf`       |
| Kernel        | 6.1.21+ (`armv6l`)                                     |
| CPU           | ARM1176JZF-S, ARMv6, VFPv2, hard-float ABI             |
| glibc         | 2.31                                                   |
| libstdc++     | 6.0.28 (GCC 10.2.1, up to `GLIBCXX_3.4.28`)            |
| Memory / disk | 429 MiB RAM, 26 GB SD card                             |
| Libraries     | `libgpiod-dev` 1.6.2 installed                         |
| Interfaces    | `gpiochip0`; I2C/SPI not enabled in `/boot/config.txt` |

Native builds on the Pi are possible (CMake 3.18.4, GCC 10.2.1) but slow; cross-building
on the host is the default workflow.

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

## Code formatting

```sh
cmake --build build --target format        # format all sources in place
cmake --build build --target format-check  # verify formatting (fails on violations)
```

## Static analysis

```sh
cmake --build build --target tidy                         # analyze all project sources
cmake -S . -B build -DPISENSE_ENABLE_CLANG_TIDY=ON         # or: analyze on every compile
```

## Cross-build for Raspberry Pi

```sh
# 1. Copy the sysroot from the Pi (once, and after installing new -dev packages on the Pi)
PI_HOST=pi@<pi-address> scripts/sync-sysroot.sh          # -> $HOME/rpi-sysroot

# 2. Configure and build (tests are off by default when cross-compiling)
cmake -S . -B build-rpi -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-rpi-zero.cmake
cmake --build build-rpi

# 3. Deploy to the Pi and run
PI_HOST=pi@<pi-address> scripts/deploy.sh --run
```

- Override the sysroot location with `RPI_SYSROOT=<dir>` (script and CMake) or
  `-DRPI_SYSROOT=<dir>`.
- The scripts use `ssh`/`rsync`; set up key-based login (`ssh-copy-id pi@<pi-address>`)
  or override the SSH command with `PI_SSH`.
