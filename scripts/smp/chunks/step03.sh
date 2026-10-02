#!/usr/bin/env bash
# step03 — C++17 aligned operator new/delete, static system_error category,
# chrono cycle-multiplication overflow. Recipe kind: whole-file (all single-step).
set -euo pipefail
git checkout origin/smp -- \
  src/libcpp/new.cpp \
  src/libcpp/system-error.cpp \
  src/libcpp/chrono.cpp

# system-error.cpp adds two Meyers singletons (the static error categories). Under
# the destination's clang -Weverything that is -Wexit-time-destructors; the whole
# codebase suppresses it for such singletons (os-clocks.cpp, os-memory.cpp, …).
# Extend the file's existing top-level clang block.
python3 - "$(dirname "$0")" src/libcpp/system-error.cpp <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
from _edit import edit, replace_n
a = '#pragma clang diagnostic ignored "-Wc++98-compat-bind-to-temporary-copy"\n'
edit(sys.argv[2], lambda s: replace_n(
    s, a, a + '#pragma clang diagnostic ignored "-Wexit-time-destructors"\n',
    "step03 system-error exit-time-destructors"))
PY
echo "[step03] applied (3 files whole + clang exit-time-destructors suppress)"
