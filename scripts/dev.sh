#!/usr/bin/env bash
# Repeatable build and verification procedures with compact output (DEV #7).
#
# Usage:
#   scripts/dev.sh build [host|rpi|coverage]   configure + build (default: host)
#   scripts/dev.sh verify [--coverage]         tests, format-check, tidy on the host build
#   scripts/dev.sh build-verify [--coverage]   build host, then verify
#
# Output contract (stable, meant to be read by people and by Claude skills):
#   [PASS|FAIL] <step> (<secs>s)       one line per step
#   <= 40 relevant lines + log path    only for a failed step
#   RESULT: PASS | RESULT: FAIL (<step>)  last line; exit code 0 / 1 (2 = usage error)
# Full logs: <build dir>/logs/<step>.log

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_DIR="$ROOT/build"
RPI_DIR="$ROOT/build-rpi"
COV_DIR="$ROOT/build-coverage"
SYSROOT="${RPI_SYSROOT:-$HOME/rpi-sysroot}"
MAX_LINES=40
JUST_BUILT=0

usage() {
    sed -n '4,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 2
}

fail() { # fail <step> <message>
    echo "[FAIL] $1"
    echo "  $2"
    echo "RESULT: FAIL ($1)"
    exit 1
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
    local excerpt
    excerpt="$(grep -E 'error|warning:|FAILED|Failed|Error' "$log" | head -n "$MAX_LINES")"
    [[ -n $excerpt ]] || excerpt="$(tail -n "$MAX_LINES" "$log")"
    printf '%s\n' "$excerpt" | sed 's/^/  /'
    echo "  full log: ${log#"$ROOT"/}"
    echo "RESULT: FAIL ($step)"
    exit 1
}

build_host() {
    run_step configure "$HOST_DIR/logs" cmake -S "$ROOT" -B "$HOST_DIR" -DCMAKE_CXX_COMPILER=clang++
    run_step build "$HOST_DIR/logs" cmake --build "$HOST_DIR" -j "$(nproc)"
}

build_rpi() {
    [[ -d $SYSROOT ]] || fail sysroot "Sysroot '$SYSROOT' not found. Sync it from the Pi first: PI_HOST=pi@<pi-address> scripts/sync-sysroot.sh"
    run_step configure "$RPI_DIR/logs" cmake -S "$ROOT" -B "$RPI_DIR" \
        -DCMAKE_TOOLCHAIN_FILE="$ROOT/cmake/toolchain-rpi-zero.cmake" -DRPI_SYSROOT="$SYSROOT"
    run_step build "$RPI_DIR/logs" cmake --build "$RPI_DIR" -j "$(nproc)"
    local info
    info="$(file -b "$RPI_DIR/pisense")"
    [[ $info == *ARM* ]] || fail arch-check "build-rpi/pisense is not an ARM binary: $info"
    echo "[PASS] arch-check (ARM ELF)"
}

build_coverage() {
    run_step coverage-configure "$COV_DIR/logs" cmake -S "$ROOT" -B "$COV_DIR" \
        -DCMAKE_CXX_COMPILER=clang++ -DPISENSE_ENABLE_COVERAGE=ON
    run_step coverage-build "$COV_DIR/logs" cmake --build "$COV_DIR" -j "$(nproc)"
}

verify() {
    local with_coverage=0
    case "${1:-}" in
        "") ;;
        --coverage) with_coverage=1 ;;
        *) usage ;;
    esac
    [[ -f $HOST_DIR/CMakeCache.txt ]] || fail verify "No host build in build/. Run: scripts/dev.sh build"
    # Incremental rebuild so tests never run against stale binaries (no-op when up to date).
    [[ $JUST_BUILT -eq 1 ]] || run_step build "$HOST_DIR/logs" cmake --build "$HOST_DIR" -j "$(nproc)"
    run_step test "$HOST_DIR/logs" bash -c "cd '$HOST_DIR' && ctest --output-on-failure"
    grep -E 'tests passed' "$HOST_DIR/logs/test.log" | sed 's/^/  /'
    run_step format-check "$HOST_DIR/logs" cmake --build "$HOST_DIR" --target format-check
    run_step tidy "$HOST_DIR/logs" cmake --build "$HOST_DIR" --target tidy
    if [[ $with_coverage -eq 1 ]]; then
        build_coverage
        run_step coverage "$COV_DIR/logs" cmake --build "$COV_DIR" --target coverage
        grep -E '^TOTAL' "$COV_DIR/logs/coverage.log" | tr -s ' ' | sed 's/^/  /'
        echo "  report: build-coverage/coverage/html/index.html"
    fi
}

cmd="${1:-}"
[[ $# -gt 0 ]] && shift
case "$cmd" in
    build)
        [[ $# -le 1 ]] || usage
        case "${1:-host}" in
            host) build_host ;;
            rpi) build_rpi ;;
            coverage) build_coverage ;;
            *) usage ;;
        esac
        ;;
    verify)
        [[ $# -le 1 ]] || usage
        verify "${1:-}"
        ;;
    build-verify)
        [[ $# -le 1 ]] || usage
        build_host
        JUST_BUILT=1
        verify "${1:-}"
        ;;
    *) usage ;;
esac
echo "RESULT: PASS"
