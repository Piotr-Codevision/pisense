# pisense
A lightweight IoT environmental monitoring system built in modern C++ for Raspberry Pi.

## Build

```sh
cmake -S . -B build -DCMAKE_CXX_COMPILER=clang++
cmake --build build
./build/pisense
```

See [docs/development.md](docs/development.md) for toolchain and environment details.
