#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# hw.sh — same silicon as the Pi Zero 2 W, so the same script.
#
# This board differs from the Zero 2 W by one linker script; it shares the
# Zero 2 W platform's src/ and include/, has its own tests, and shares its
# runner too. Only the default
# build directory differs, because a separate BOARD gets a separate build.
# -----------------------------------------------------------------------------
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"   # the kernel (micro-os-plus-iii)
export BUILD="${BUILD:-$ROOT/tests/build/aarch64-rpi3b-cmake-gcc-debug/platform-bin/port-tests}"
exec "$HERE/../aarch64-rpi-zero-2w/hw.sh" "$@"
