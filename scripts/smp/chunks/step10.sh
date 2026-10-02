#!/usr/bin/env bash
# step10 — condition variable atomicity: rewritten wait()/timed_wait(), a clock
# member, and the CONDVAR suspend-cause instrumentation constant.
# Recipe kind: whole-file + one surgical uncomment.
#
# os-condvar.cpp/.h and instrumentation.h are clean single-step files. os-c-decls.h
# is multi-step (9,10,16): Step 9's destroying enum is already present and Step 16's
# SMP klock must stay out, so we ONLY uncomment os_condvar_t's `void* clock` field
# here (the size counterpart of os-condvar.h's `clock* clock_`).
set -euo pipefail

git checkout origin/smp -- \
  src/rtos/os-condvar.cpp \
  include/cmsis-plus/rtos/os-condvar.h \
  include/cmsis-plus/diag/instrumentation.h

# os-c-decls.h: uncomment the (unique) placeholder clock field in os_condvar_t.
python3 - "$(dirname "$0")" include/cmsis-plus/rtos/os-c-decls.h <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
from _edit import edit, replace_n
edit(sys.argv[2], lambda s: replace_n(
    s, "    // void* clock;", "    void* clock;", "step10 os_condvar_t clock"))
PY

grep -q '^    void\* clock;' include/cmsis-plus/rtos/os-c-decls.h || true
n=$(grep -c '// void\* clock;' include/cmsis-plus/rtos/os-c-decls.h || true)
[ "${n:-0}" -eq 0 ] || { echo "[step10] clock uncomment failed"; exit 1; }
echo "[step10] applied (3 files whole + os_condvar_t clock uncomment)"
