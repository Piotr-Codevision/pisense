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

# Static analysis (DEV #5). clang-tidy is optional; configuration lives in .clang-tidy.
find_program(CLANG_TIDY_EXE
    NAMES clang-tidy clang-tidy-21 clang-tidy-20 clang-tidy-19 clang-tidy-18
          clang-tidy-17 clang-tidy-16 clang-tidy-15 clang-tidy-14)
option(PISENSE_ENABLE_CLANG_TIDY "Run clang-tidy while compiling project targets" OFF)

if(PISENSE_ENABLE_CLANG_TIDY AND NOT CLANG_TIDY_EXE)
    message(FATAL_ERROR "PISENSE_ENABLE_CLANG_TIDY is ON but clang-tidy was not found")
endif()

# Enables clang-tidy on a project target (third-party targets are left untouched).
function(pisense_enable_clang_tidy target)
    if(PISENSE_ENABLE_CLANG_TIDY)
        set_target_properties(${target} PROPERTIES CXX_CLANG_TIDY "${CLANG_TIDY_EXE}")
    endif()
endfunction()

# Common warning flags shared by all project targets.
add_library(pisense_warnings INTERFACE)
target_compile_options(pisense_warnings INTERFACE -Wall -Wextra -Wpedantic)

add_executable(pisense src/main.cpp)
target_include_directories(pisense PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/inc)
target_link_libraries(pisense PRIVATE pisense_warnings)
pisense_enable_clang_tidy(pisense)

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

# Code formatting (DEV #4). Optional targets, enabled only if clang-format is found.
find_program(CLANG_FORMAT_EXE
    NAMES clang-format clang-format-21 clang-format-20 clang-format-19 clang-format-18
          clang-format-17 clang-format-16 clang-format-15 clang-format-14)

if(CLANG_FORMAT_EXE)
    file(GLOB_RECURSE PISENSE_FORMAT_SOURCES CONFIGURE_DEPENDS
        ${PROJECT_SOURCE_DIR}/src/*.cpp ${PROJECT_SOURCE_DIR}/src/*.h ${PROJECT_SOURCE_DIR}/src/*.hpp
        ${PROJECT_SOURCE_DIR}/inc/*.h ${PROJECT_SOURCE_DIR}/inc/*.hpp
        ${PROJECT_SOURCE_DIR}/tests/*.cpp ${PROJECT_SOURCE_DIR}/tests/*.h ${PROJECT_SOURCE_DIR}/tests/*.hpp)

    add_custom_target(format
        COMMAND ${CLANG_FORMAT_EXE} -i ${PISENSE_FORMAT_SOURCES}
        WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
        COMMENT "Formatting sources with clang-format"
        VERBATIM)

    add_custom_target(format-check
        COMMAND ${CLANG_FORMAT_EXE} --dry-run --Werror ${PISENSE_FORMAT_SOURCES}
        WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
        COMMENT "Checking source formatting with clang-format"
        VERBATIM)
else()
    message(STATUS "clang-format not found: format targets disabled")
endif()

if(CLANG_TIDY_EXE)
    file(GLOB_RECURSE PISENSE_TIDY_SOURCES CONFIGURE_DEPENDS
        ${PROJECT_SOURCE_DIR}/src/*.cpp ${PROJECT_SOURCE_DIR}/tests/*.cpp)

    # Analyze all project sources using the compilation database of this build.
    add_custom_target(tidy
        COMMAND ${CLANG_TIDY_EXE} -p ${CMAKE_BINARY_DIR} --quiet ${PISENSE_TIDY_SOURCES}
        WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
        COMMENT "Running clang-tidy static analysis"
        VERBATIM)
else()
    message(STATUS "clang-tidy not found: tidy target disabled")
endif()
