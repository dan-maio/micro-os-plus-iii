#!/usr/bin/env bash
# step01 — ISO C conformance, list iterators, exported suspend.
# Recipe kind: mixed (whole-file copies + one surgical edit).
#
# NOTE on timegm.c: the smp change to src/libc/stdlib/timegm.c guards the
# prototype behind `#if !defined(__GLIBC__)`, which REGRESSES glibc >= 2.44
# (the native build's host libc): the prototype is dropped while <time.h> hides
# timegm under strict flags -> -Werror=missing-prototypes. The baseline already
# declares it unconditionally and compiles everywhere, so we KEEP BASELINE
# timegm.c and do NOT apply the smp hunk. (newlib/ARM unaffected either way.)
set -euo pipefail

# whole-file (single-step, clean):
git checkout origin/smp -- \
  include/cmsis-plus/posix/dirent.h \
  include/cmsis-plus/utils/lists.h

# surgical: remove only 'inline' from this_thread::suspend so the C wrapper
# resolves the exported symbol (os-thread.cpp is multi-step; take just this).
python3 - "$(dirname "$0")" src/rtos/os-thread.cpp <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
from _edit import edit, replace_n
edit(sys.argv[2], lambda s: replace_n(
    s, "inline void\n      suspend (void)", "void\n      suspend (void)",
    "step01 suspend un-inline"))
PY

echo "[step01] applied (timegm.c intentionally left at baseline)"
