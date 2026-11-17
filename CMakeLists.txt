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

add_executable(pisense src/main.cpp)
target_include_directories(pisense PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/inc)
target_compile_options(pisense PRIVATE -Wall -Wextra -Wpedantic)
