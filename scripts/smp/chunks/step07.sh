#!/usr/bin/env bash
# step07 — timer callback outside critical section, periodic catch-up re-arm,
# handler-mode errno scratch. Recipe kind: whole-file + SURGICAL insert.
#
# os-thread.h is multi-step (1,9,14,20). Its Step-7 change is a single hunk (the
# handler-mode errno scratch); its other hunks are `destroying = 7` (Step 9 —
# would trip -Werror=switch-enum here) and SMP affinity (Step 20). So KEEP the
# baseline os-thread.h and insert only the errno hunk.
set -euo pipefail

git checkout origin/smp -- src/rtos/internal/os-lists.cpp src/rtos/os-timer.cpp

H=include/cmsis-plus/rtos/os-thread.h
# Surgical: insert the handler-mode errno scratch guard immediately before the
# existing `return &this_thread::thread ().errno_;`, reusing its own indentation.
python3 - "$(dirname "$0")" "$H" <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
from _edit import edit, sub_re_n

guard = (
    "\n        // A timer callback runs inside the tick ISR and a libc call there\n"
    "        // (e.g. printf) still touches errno; thread() asserts in handler mode,\n"
    "        // so hand back a scratch int instead of the current thread's.\n"
    "        if (interrupts::in_handler_mode ())\n"
    "          {\n"
    "            static int isr_errno;\n"
    "            return &isr_errno;\n"
    "          }")

def apply(s):
    # \1 is the original whitespace before the return; keep it verbatim.
    return sub_re_n(
        s,
        r'(\n\s*)return &this_thread::thread \(\)\.errno_;',
        guard + r'\1return &this_thread::thread ().errno_;',
        "step07 handler-mode errno")

edit(sys.argv[2], apply)
PY

# assert: errno hunk present, no Step 9/20 leakage
grep -q isr_errno "$H" || { echo "[step07] errno insert FAILED"; exit 1; }
n=$(grep -c 'destroying = 7\|th_cpu_affinity' "$H" || true)
[ "${n:-0}" -eq 0 ] || { echo "[step07] LEAK: $n later-step lines in os-thread.h"; exit 1; }
echo "[step07] applied (2 files whole + os-thread.h surgical errno insert)"
