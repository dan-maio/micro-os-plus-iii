#!/usr/bin/env bash
# =============================================================================
# Simple runner for Raspberry Pi Zero 2 W hardware tests over OpenOCD
# Usage:
#   ./test_smpl/run-hw-simple.sh <path-to-elf> [entry-address]
# =============================================================================
set -euo pipefail

ELF="${1:?Usage: $0 <path-to-elf> [entry-address]}"
ENTRY="${2:-0x80000}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OPENOCD="${OPENOCD:-$(ls -d "$HOME"/.local/xPacks/@xpack-dev-tools/openocd/*/.content/bin/openocd 2>/dev/null | sort -V | tail -1)}"
[[ -n "$OPENOCD" && -x "$OPENOCD" ]] || OPENOCD="openocd"

exec "$OPENOCD" -f "$HERE/openocd-rpi-zero-2w.cfg" -c "run_app \"$ELF\" $ENTRY"
