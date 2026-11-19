#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# hw.sh — same silicon as the Pi Zero 2 W, so the same script.
#
# This board differs from rpi-zero-2w by one linker script; it shares src/ and
# include/ with it, and has its own tests, and shares this runner too. Only the default
# build directory differs, because a separate BOARD gets a separate build.
# -----------------------------------------------------------------------------
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"   # the kernel (micro-os-plus-iii)
export BUILD="${BUILD:-$ROOT/tests/build/aarch32-rpi3b-cmake-gcc-debug/platform-bin/port-tests}"
exec "$HERE/../aarch32-rpi-zero-2w/hw.sh" "$@"
