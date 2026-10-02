#!/usr/bin/env bash
# step06 — ARMv8-M mainline guards + SecureFault_Handler, semihosting fstat fix,
# weak os_board_console_mirror hook. Recipe kind: whole-file (all single-step).
# (All three files are portable kernel code — arm/, startup/, semihosting/.)
set -euo pipefail
git checkout origin/smp -- \
  include/cmsis-plus/arm/semihosting.h \
  src/startup/exception-handlers.c \
  src/semihosting/c-syscalls-semihosting.cpp
echo "[step06] applied (3 files whole)"
