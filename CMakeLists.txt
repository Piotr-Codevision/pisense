cmake_minimum_required(VERSION 3.16)

project(PiSense
    VERSION 0.1.0
    DESCRIPTION "Educational IoT environmental monitoring for Raspberry Pi Zero W"
    LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Debug CACHE STRING "Build type" FORCE)
endif()

# Common warning flags shared by all project targets.
add_library(pisense_warnings INTERFACE)
target_compile_options(pisense_warnings INTERFACE -Wall -Wextra -Wpedantic)

add_executable(pisense src/main.cpp)
target_include_directories(pisense PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/inc)
target_link_libraries(pisense PRIVATE pisense_warnings)

# Host-based unit tests (DEV #3). Disabled by default when cross-compiling;
# for native builds on the Raspberry Pi pass -DPISENSE_BUILD_TESTS=OFF.
if(CMAKE_CROSSCOMPILING)
    set(_pisense_tests_default OFF)
else()
    set(_pisense_tests_default ON)
endif()
option(PISENSE_BUILD_TESTS "Build host-based unit tests" ${_pisense_tests_default})

if(PISENSE_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()
