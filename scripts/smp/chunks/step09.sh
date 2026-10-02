#!/usr/bin/env bash
# step09 — thread lifecycle: state::destroying (7), atomic join, detach, reaper.
# Recipe kind: SINGLE-CORE PROJECTION.
#
# These four files are deeply entangled with SMP (os-thread.cpp alone has ~37
# SMP hunks across a 300-line diff), so hand-stripping is infeasible. Instead we
# take the smp version of each and keep only its single-core projection with
# sc-project.py (strips `#if defined(OS_USE_SMP_SCHEDULER)` AND the
# `OS_INTEGER_RTOS_PORT_NCPU > 1` gate). For these files no Part-A step between
# 10 and 13 touches them, so the projection is exactly the <=Step-9 state
# (baseline + Steps 1/7/9 non-SMP changes).
set -euo pipefail
SC="$(dirname "$0")/../sc-project.py"

# os-thread.h/.cpp + os-idle.cpp: single-core projection is exact here (their only
# non-SMP Part-A changes are Steps 1/7/9, all <= 9).
for f in \
  include/cmsis-plus/rtos/os-thread.h \
  src/rtos/os-thread.cpp \
  src/rtos/os-idle.cpp
do
  git show "origin/smp:$f" | python3 "$SC" > "$f"
done

# os-c-decls.h: projection would ALSO pull Step 10's `void* clock` field into
# os_condvar_t (grows it to 16 while condition_variable stays 12 -> size assert
# fails). So keep baseline and insert ONLY the Step-9 destroying enumerator.
H=include/cmsis-plus/rtos/os-c-decls.h
python3 - "$(dirname "$0")" "$H" <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
from _edit import edit, replace_n

old = "    os_thread_state_initialising = 6\n  };"
new = ("    os_thread_state_initialising = 6,\n\n"
       "    /**\n"
       "     * @brief In process of being destroyed.\n"
       "     */\n"
       "    os_thread_state_destroying = 7\n"
       "  };")
edit(sys.argv[2], lambda s: replace_n(s, old, new, "step09 destroying enum"))
PY

# assert: destroying present, no SMP/NCPU leakage
grep -q 'os_thread_state_destroying' "$H" || { echo "[step09] destroying enum insert failed"; exit 1; }
grep -q 'void\* clock' "$H" && { echo "[step09] Step-10 clock leaked into os-c-decls.h"; exit 1; }
n=$(grep -rcE 'OS_USE_SMP_SCHEDULER|OS_INTEGER_RTOS_PORT_NCPU|_this_cpu|current_thread_\[|port_cpu_id|cpu_affinity' \
      include/cmsis-plus/rtos/os-c-decls.h include/cmsis-plus/rtos/os-thread.h \
      src/rtos/os-thread.cpp src/rtos/os-idle.cpp | awk -F: '{s+=$2} END{print s+0}')
[ "${n:-0}" -eq 0 ] || { echo "[step09] SMP LEAK: $n lines"; exit 1; }
echo "[step09] applied (single-core projection of 4 files)"
