#!/usr/bin/env bash
# step12 — message queue reschedule triggers (preemption on posix-arch after
# send/receive wakes a higher-priority thread). Recipe kind: whole-file.
set -euo pipefail
git checkout origin/smp -- src/rtos/os-mqueue.cpp
echo "[step12] applied (1 file whole)"
