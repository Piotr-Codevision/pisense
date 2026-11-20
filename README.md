# pisense

[![CI](https://github.com/Piotr-Codevision/pisense/actions/workflows/ci.yml/badge.svg)](https://github.com/Piotr-Codevision/pisense/actions/workflows/ci.yml)

A lightweight IoT environmental monitoring system built in modern C++ for Raspberry Pi.

## Build

```sh
cmake -S . -B build -DCMAKE_CXX_COMPILER=clang++
cmake --build build
./build/pisense
```

See [docs/development.md](docs/development.md) for toolchain and environment details.

To cross-build for the Raspberry Pi Zero W, see
[docs/development.md](docs/development.md#cross-build-for-raspberry-pi).
