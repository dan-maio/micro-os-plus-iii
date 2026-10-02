#!/usr/bin/env bash
# step02 — memory: align_size overflow, usable size, calloc/realloc, block-pool.
# Recipe kind: whole-file copies + one diagnostic-pragma wrap.
#
# The full cohesive chunk is SEVEN files: the header declaration
# (first-fit-top.h), the base-class definition (os-memory.cpp) AND the override
# (first-fit-top.cpp) must all land together, or you get an undefined-reference
# link error on memory_resource::do_usable_size.
set -euo pipefail

git checkout origin/smp -- \
  include/cmsis-plus/rtos/os-memory.h \
  include/cmsis-plus/memory/first-fit-top.h \
  src/rtos/os-memory.cpp \
  src/memory/first-fit-top.cpp \
  src/memory/lifo.cpp \
  src/memory/block-pool.cpp \
  src/libc/stdlib/malloc.cpp

# smp's first_fit_top::do_usable_size is NOT wrapped for the allocator's pointer
# arithmetic; the baseline harness compiles clang with -Weverything and ARM gcc
# with -Wcast-align (both -Werror). Wrap it for BOTH, as the plan's Step 2 says.
F=src/memory/first-fit-top.cpp
python3 - "$(dirname "$0")" "$F" <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
from _edit import edit, replace_n

sig = ("    std::size_t\n"
       "    first_fit_top::do_usable_size (void* addr) const noexcept\n")
push = ('#pragma GCC diagnostic push\n'
        '#pragma GCC diagnostic ignored "-Wcast-align"\n'
        '#if defined(__clang__)\n'
        '#pragma clang diagnostic ignored "-Wunsafe-buffer-usage"\n'
        '#endif\n')
end = "          - static_cast<char*> (addr));\n    }"

def apply(s):
    s = replace_n(s, sig, push + sig, "step02 pragma push")
    s = replace_n(s, end, end + "\n#pragma GCC diagnostic pop", "step02 pragma pop")
    return s

edit(sys.argv[2], apply)
PY

echo "[step02] applied (7 files + do_usable_size cast-align/unsafe-buffer wrap)"
