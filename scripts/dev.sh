#!/usr/bin/env bash
# Repeatable build and verification procedures with compact output (DEV #7).
#
# Output contract (stable, meant to be read by people and by Claude skills):
#   [PASS|FAIL] <step> (<secs>s)          one line per step
#   [SKIP] <step> (<reason>)              optional step not run (e.g. tool not installed)
#   <= 40 relevant lines + log path       only for a failed step (errors first, then
#                                         warnings and notes)
#   RESULT: PASS [(skipped: <steps>)]     last line, exit code 0
#   RESULT: FAIL (<step>)                 last line, exit code 1 (2 = usage error)
# Full logs: <build dir>/logs/<step>.log

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_DIR="$ROOT/build"
RPI_DIR="$ROOT/build-rpi"
COV_DIR="$ROOT/build-coverage"
SYSROOT="${RPI_SYSROOT:-$HOME/rpi-sysroot}"
MAX_LINES=40
CONTEXT_LINES=4 # lines kept after each error match (CMake reasons, GoogleTest values)
ERROR_RE='error|Error|FAILED|Failed|Failure'
SKIPPED=()

usage() {
    cat <<'EOF'
Usage:
  scripts/dev.sh build [host|rpi|coverage]   configure + build (default: host)
  scripts/dev.sh verify [--coverage]         rebuild, tests, format-check, shellcheck, tidy
  scripts/dev.sh build-verify [--coverage]   build host, then verify
EOF
    exit 2
}

fail() { # fail <step> <message>
    echo "[FAIL] $1"
    echo "  $2"
    echo "RESULT: FAIL ($1)"
    exit 1
}

# excerpt <log>: error lines with context first, then warnings and notes (shellcheck reports
# info/style findings as notes), at most MAX_LINES in total;
# the log tail if nothing matches.
excerpt() {
    local log="$1" errors warnings n
    errors="$(grep -E -A "$CONTEXT_LINES" --no-group-separator "$ERROR_RE" "$log" |
        head -n "$MAX_LINES")"
    n=$(printf '%s' "$errors" | grep -c '' || true)
    if ((n < MAX_LINES)); then
        warnings="$(grep -E -A 2 --no-group-separator 'warning:|note:' "$log" | head -n $((MAX_LINES - n)))"
        errors="$(printf '%s\n%s' "$errors" "$warnings" | sed '/^$/d')"
    fi
    [[ -n $errors ]] || errors="$(tail -n "$MAX_LINES" "$log")"
    # Drop make's recursive "*** ... Error N" lines and repeated lines (overlapping context).
    printf '%s\n' "$errors" | grep -vE '^g?make(\[[0-9]+\])?: \*\*\*' | awk '!seen[$0]++'
}

# run_step <step> <log dir> <command...>: runs the command with output to a log file,
# prints one status line and, on failure, a short excerpt; exits the script on failure.
run_step() {
    local step="$1" logdir="$2"
    shift 2
    mkdir -p "$logdir"
    local log="$logdir/$step.log" start=$SECONDS rc=0
    "$@" >"$log" 2>&1 || rc=$?
    # clang-tidy does not fail on findings (WarningsAsErrors is empty): treat any as failure.
    if [[ $rc -eq 0 && $step == tidy ]] && grep -qE '(warning|error): ' "$log"; then
        rc=1
    fi
    local secs=$((SECONDS - start))
    if [[ $rc -eq 0 ]]; then
        echo "[PASS] $step (${secs}s)"
        return 0
    fi
    echo "[FAIL] $step (${secs}s)"
    excerpt "$log" | sed 's/^/  /'
    echo "  full log: ${log#"$ROOT"/}"
    echo "RESULT: FAIL ($step)"
    exit 1
}

# has_tool <cache variable>: true when CMake found the tool in the host build.
has_tool() {
    local path
    path="$(sed -n "s/^$1:FILEPATH=//p" "$HOST_DIR/CMakeCache.txt")"
    [[ -n $path && $path != *-NOTFOUND ]]
}

# require_tool <step> <cache variable> <tool name>: fails clearly when CMake did not find
# a required tool, instead of reporting a missing target as a code problem.
require_tool() {
    has_tool "$2" ||
        fail "$1" "$3 not found by CMake; install it (see docs/development.md) and re-run: scripts/dev.sh build"
}

# skip_step <step> <reason>: reports an optional step that was not run.
skip_step() {
    echo "[SKIP] $1 ($2)"
    SKIPPED+=("$1")
}

run_tests() (
    cd "$HOST_DIR" && ctest --output-on-failure
)

build_host() {
    run_step configure "$HOST_DIR/logs" cmake -S "$ROOT" -B "$HOST_DIR" -DCMAKE_CXX_COMPILER=clang++
    run_step build "$HOST_DIR/logs" cmake --build "$HOST_DIR" -j "$(nproc)"
}

build_rpi() {
    [[ -d $SYSROOT ]] || fail sysroot "Sysroot '$SYSROOT' not found. Sync it from the Pi first: PI_HOST=pi@<pi-address> scripts/sync-sysroot.sh"
    command -v file >/dev/null || fail arch-check "'file' utility not found; install it (package 'file')"
    run_step configure "$RPI_DIR/logs" cmake -S "$ROOT" -B "$RPI_DIR" \
        -DCMAKE_TOOLCHAIN_FILE="$ROOT/cmake/toolchain-rpi-zero.cmake" -DRPI_SYSROOT="$SYSROOT"
    run_step build "$RPI_DIR/logs" cmake --build "$RPI_DIR" -j "$(nproc)"
    local info
    info="$(file -b "$RPI_DIR/pisense")"
    [[ $info == *ARM* ]] || fail arch-check "build-rpi/pisense is not an ARM binary: $info"
    echo "[PASS] arch-check (ARM ELF)"
}

# build_coverage [target]: configure the coverage tree and build all targets or one target.
build_coverage() {
    run_step coverage-configure "$COV_DIR/logs" cmake -S "$ROOT" -B "$COV_DIR" \
        -DCMAKE_CXX_COMPILER=clang++ -DPISENSE_ENABLE_COVERAGE=ON
    run_step coverage-build "$COV_DIR/logs" cmake --build "$COV_DIR" -j "$(nproc)" \
        ${1:+--target "$1"}
}

# verify <with_coverage> <skip_rebuild>
verify() {
    [[ -f $HOST_DIR/CMakeCache.txt ]] || fail verify "No host build in build/. Run: scripts/dev.sh build"
    # Incremental rebuild so tests never run against stale binaries (no-op when up to date).
    [[ $2 -eq 1 ]] || run_step build "$HOST_DIR/logs" cmake --build "$HOST_DIR" -j "$(nproc)"
    run_step test "$HOST_DIR/logs" run_tests
    grep -E 'tests passed' "$HOST_DIR/logs/test.log" | sed 's/^/  /'
    require_tool format-check CLANG_FORMAT_EXE clang-format
    run_step format-check "$HOST_DIR/logs" cmake --build "$HOST_DIR" --target format-check
    # Optional: shell scripts are not part of the product build.
    if has_tool SHELLCHECK_EXE; then
        run_step shellcheck "$HOST_DIR/logs" cmake --build "$HOST_DIR" --target shellcheck
    else
        skip_step shellcheck "not installed"
    fi
    require_tool tidy CLANG_TIDY_EXE clang-tidy
    run_step tidy "$HOST_DIR/logs" cmake --build "$HOST_DIR" --target tidy
    if [[ $1 -eq 1 ]]; then
        build_coverage pisense_unit_tests
        run_step coverage "$COV_DIR/logs" cmake --build "$COV_DIR" --target coverage
        grep -E '^TOTAL' "$COV_DIR/logs/coverage.log" | tr -s ' ' | sed 's/^/  /'
        echo "  report: build-coverage/coverage/html/index.html"
    fi
}

# Validate all arguments before doing any work.
cmd="${1:-}"
[[ $# -gt 0 ]] && shift
[[ $# -le 1 ]] || usage
arg="${1:-}"
with_coverage=0
case "$cmd" in
    build)
        case "${arg:-host}" in
            host | rpi | coverage) ;;
            *) usage ;;
        esac
        ;;
    verify | build-verify)
        case "$arg" in
            "") ;;
            --coverage) with_coverage=1 ;;
            *) usage ;;
        esac
        ;;
    *) usage ;;
esac

case "$cmd" in
    build)
        case "${arg:-host}" in
            host) build_host ;;
            rpi) build_rpi ;;
            coverage) build_coverage ;;
        esac
        ;;
    verify) verify "$with_coverage" 0 ;;
    build-verify)
        build_host
        verify "$with_coverage" 1
        ;;
esac
if ((${#SKIPPED[@]})); then
    echo "RESULT: PASS (skipped: ${SKIPPED[*]})"
else
    echo "RESULT: PASS"
fi
