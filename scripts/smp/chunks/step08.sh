#!/usr/bin/env bash
# step08 — mutex priority ceiling before ownership, max-waiter boost tracking,
# unlock recompute, owner cache across uncritical window.
# Recipe kind: whole-file (single-step, clean).
set -euo pipefail
git checkout origin/smp -- src/rtos/os-mutex.cpp
echo "[step08] applied (1 file whole)"
