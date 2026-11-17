#!/usr/bin/env bash
# Copies the cross-compiled pisense binary to the Raspberry Pi and optionally runs it.
#
# Usage: scripts/deploy.sh [--run]
# Environment:
#   PI_HOST     SSH destination of the Pi           (default: pi@raspberrypi.local)
#   BUILD_DIR   Cross-build directory               (default: build-rpi)
#   REMOTE_DIR  Target directory on the Pi          (default: pisense, relative to home)
#   PI_SSH      SSH command used by rsync/ssh       (default: ssh)
set -euo pipefail

PI_HOST="${PI_HOST:-pi@raspberrypi.local}"
BUILD_DIR="${BUILD_DIR:-build-rpi}"
REMOTE_DIR="${REMOTE_DIR:-pisense}"
SSH_CMD="${PI_SSH:-ssh}"
BINARY="${BUILD_DIR}/pisense"

if [[ ! -x "${BINARY}" ]]; then
    echo "error: ${BINARY} not found; run the cross-build first" >&2
    exit 1
fi

# shellcheck disable=SC2086 # SSH_CMD may contain options
${SSH_CMD} "${PI_HOST}" "mkdir -p '${REMOTE_DIR}'"
rsync -a -e "${SSH_CMD}" "${BINARY}" "${PI_HOST}:${REMOTE_DIR}/"
echo "Deployed ${BINARY} to ${PI_HOST}:${REMOTE_DIR}/"

if [[ "${1:-}" == "--run" ]]; then
    # shellcheck disable=SC2086 # SSH_CMD may contain options
    ${SSH_CMD} "${PI_HOST}" "cd '${REMOTE_DIR}' && ./pisense"
fi
