#!/usr/bin/env bash
# Copies the Raspberry Pi system headers and libraries needed for cross-compilation
# (the "sysroot", see DEV #2 in docs/development.md) from the Pi to this host.
#
# Usage: scripts/sync-sysroot.sh
# Environment:
#   PI_HOST      SSH destination of the Pi      (default: pi@raspberrypi.local)
#   RPI_SYSROOT  Local sysroot directory        (default: $HOME/rpi-sysroot)
#   PI_SSH       SSH command used by rsync/ssh  (default: ssh)
set -euo pipefail

PI_HOST="${PI_HOST:-pi@raspberrypi.local}"
SYSROOT="${RPI_SYSROOT:-$HOME/rpi-sysroot}"
SSH_CMD="${PI_SSH:-ssh}"

echo "Detecting GCC version on ${PI_HOST}..."
# shellcheck disable=SC2086 # SSH_CMD may contain options
GCC_MAJOR="$(${SSH_CMD} "${PI_HOST}" 'gcc -dumpversion' | cut -d. -f1)"
echo "Target GCC (libstdc++) version: ${GCC_MAJOR}"

mkdir -p "${SYSROOT}"
echo "Syncing sysroot into ${SYSROOT}..."
rsync -a --relative --delete --info=stats1 -e "${SSH_CMD}" \
    "${PI_HOST}:/usr/include" \
    "${PI_HOST}:/usr/lib/arm-linux-gnueabihf" \
    "${PI_HOST}:/usr/lib/gcc/arm-linux-gnueabihf/${GCC_MAJOR}" \
    "${PI_HOST}:/usr/lib/ld-linux-armhf.so.3" \
    "${SYSROOT}/"

# Raspberry Pi OS uses a merged /usr layout (/lib -> usr/lib).
ln -sfn usr/lib "${SYSROOT}/lib"

# Absolute symlinks (e.g. libfoo.so -> /lib/arm-linux-gnueabihf/libfoo.so.1) would point
# into the host filesystem; rewrite them as relative links inside the sysroot.
echo "Fixing absolute symlinks..."
fixed=0
while IFS= read -r -d '' link; do
    target="$(readlink "${link}")"
    relative="$(realpath -m -s --relative-to="$(dirname "${link}")" "${SYSROOT}${target}")"
    ln -sfn "${relative}" "${link}"
    fixed=$((fixed + 1))
done < <(find "${SYSROOT}" -type l -lname '/*' -print0)
echo "Rewrote ${fixed} absolute symlink(s)."

echo "Sysroot ready: ${SYSROOT}"
