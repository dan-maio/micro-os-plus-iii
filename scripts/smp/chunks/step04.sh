#!/usr/bin/env bash
# step04 — C wrapper: one-shot timer default, polymorphic mutex/semaphore delete,
# 64-bit CMSIS-v1 timeouts. Recipe kind: copy + STRIP later-step content.
#
# os-c-wrapper.cpp is touched by Steps 4, 9, 20. A whole-file copy also brings:
#   * Step 9  static_assert(os_thread_state_destroying...) — BREAKS the build
#             (that enum arrives in Step 9);
#   * Step 20 two `#if defined(OS_USE_SMP_SCHEDULER)` CMSIS-v1 affinity blocks.
# Strip all three so Step 4 carries only its own concern.
set -euo pipefail
F=src/rtos/os-c-wrapper.cpp
git checkout origin/smp -- "$F"

# Step 9: drop the destroying static_assert (exact, 1 match).
# Step 20: drop both OS_USE_SMP_SCHEDULER affinity blocks (regex, 2 matches).
python3 - "$(dirname "$0")" "$F" <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
from _edit import edit, strip_n, sub_re_n

static_assert = (
    "static_assert (os_thread_state_destroying == thread::state::destroying,\n"
    '               "adjust os_thread_state_destroying");\n')
affinity = (r'#if defined\(OS_USE_SMP_SCHEDULER\)\n(?:[^\n]*\n)*?\s*'
            r'(?:attr\.th_cpu_affinity = \(1u << 0\);|th->cpu_affinity \(1u << 0\);)'
            r'\n#endif\n\n')

def apply(s):
    s = strip_n(s, static_assert, "step04 destroying static_assert")
    s = sub_re_n(s, affinity, "", "step04 SMP affinity blocks", n=2)
    return s

edit(sys.argv[2], apply)
PY

# assert the strip worked (must all be 0)
n=$(grep -c "os_thread_state_destroying\|OS_USE_SMP_SCHEDULER\|cpu_affinity" "$F" || true)
[ "${n:-0}" -eq 0 ] || { echo "[step04] STRIP FAILED: $n later-step lines remain"; exit 1; }
echo "[step04] applied (os-c-wrapper.cpp, Step 9/20 content stripped)"
