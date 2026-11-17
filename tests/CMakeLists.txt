# Prefer an installed GoogleTest; otherwise download a pinned release.
find_package(GTest 1.11 CONFIG QUIET)

if(GTest_FOUND)
    message(STATUS "Using installed GoogleTest ${GTest_VERSION}")
else()
    message(STATUS "GoogleTest not found, fetching v1.17.0")
    include(FetchContent)

    # CMake >= 3.24: use extraction time as file timestamps (avoids warning).
    if(POLICY CMP0135)
        cmake_policy(SET CMP0135 NEW)
    endif()

    FetchContent_Declare(
        googletest
        URL https://github.com/google/googletest/releases/download/v1.17.0/googletest-1.17.0.tar.gz
        URL_HASH SHA256=65fab701d9829d38cb77c14acdc431d2108bfdbf8979e40eb8ae567edf10b27c
    )
    # Do not install GoogleTest with the project (user may still override).
    set(INSTALL_GTEST OFF CACHE BOOL "Install GoogleTest")
    FetchContent_MakeAvailable(googletest)
endif()

include(GoogleTest)

add_executable(pisense_unit_tests
    unit/sanity_test.cpp
)
target_include_directories(pisense_unit_tests PRIVATE ${PROJECT_SOURCE_DIR}/inc)
target_link_libraries(pisense_unit_tests PRIVATE
    pisense_warnings
    GTest::gtest_main
    GTest::gmock
)

# gtest_discover_tests runs the test binary at build time, which is impossible
# when cross-compiling without an emulator; fall back to scanning sources.
if(CMAKE_CROSSCOMPILING AND NOT CMAKE_CROSSCOMPILING_EMULATOR)
    gtest_add_tests(TARGET pisense_unit_tests)
else()
    gtest_discover_tests(pisense_unit_tests)
endif()
