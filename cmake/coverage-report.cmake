# Runs the unit tests with coverage instrumentation and produces reports (DEV #6).
# Invoked by the `coverage` target:
#   cmake -DLLVM_PROFDATA=... -DLLVM_COV=... -DCTEST=... -DBUILD_DIR=... -DOUTPUT_DIR=...
#         -DOBJECTS=<bin1;bin2> -DIGNORE_REGEX=... -P coverage-report.cmake

foreach(var LLVM_PROFDATA LLVM_COV CTEST BUILD_DIR OUTPUT_DIR OBJECTS IGNORE_REGEX)
    if(NOT DEFINED ${var})
        message(FATAL_ERROR "coverage-report.cmake: ${var} is not set")
    endif()
endforeach()

# Runs a command and stops on failure (COMMAND_ERROR_IS_FATAL needs CMake 3.19).
function(run_checked)
    execute_process(COMMAND ${ARGN} RESULT_VARIABLE result)
    if(NOT result EQUAL 0)
        message(FATAL_ERROR "Command failed (${result}): ${ARGN}")
    endif()
endfunction()

file(REMOVE_RECURSE "${OUTPUT_DIR}")
file(MAKE_DIRECTORY "${OUTPUT_DIR}/profraw")

# 1. Run the tests; every test process writes its own raw profile.
set(ENV{LLVM_PROFILE_FILE} "${OUTPUT_DIR}/profraw/%p.profraw")
execute_process(
    COMMAND "${CTEST}" --output-on-failure
    WORKING_DIRECTORY "${BUILD_DIR}"
    RESULT_VARIABLE test_result)
if(NOT test_result EQUAL 0)
    message(WARNING "Some tests failed; the coverage report reflects the executed tests only")
endif()

# 2. Merge the raw profiles.
file(GLOB raw_profiles "${OUTPUT_DIR}/profraw/*.profraw")
if(NOT raw_profiles)
    message(FATAL_ERROR "No coverage profiles were written; were the tests built with coverage?")
endif()
set(profdata "${OUTPUT_DIR}/pisense.profdata")
run_checked("${LLVM_PROFDATA}" merge -sparse ${raw_profiles} -o "${profdata}")

# 3. Reports: console summary, HTML and lcov.
set(objects "")
foreach(object IN LISTS OBJECTS)
    if(objects)
        list(APPEND objects "-object=${object}")
    else()
        list(APPEND objects "${object}")
    endif()
endforeach()
set(common_args ${objects} "-instr-profile=${profdata}" "-ignore-filename-regex=${IGNORE_REGEX}")

run_checked("${LLVM_COV}" report ${common_args})
run_checked("${LLVM_COV}" show ${common_args} -format=html -show-line-counts-or-regions
            "-output-dir=${OUTPUT_DIR}/html")
execute_process(
    COMMAND "${LLVM_COV}" export ${common_args} -format=lcov
    OUTPUT_FILE "${OUTPUT_DIR}/coverage.lcov"
    RESULT_VARIABLE export_result)
if(NOT export_result EQUAL 0)
    message(FATAL_ERROR "llvm-cov export failed (${export_result})")
endif()

message(STATUS "HTML report: ${OUTPUT_DIR}/html/index.html")
message(STATUS "lcov report: ${OUTPUT_DIR}/coverage.lcov")
