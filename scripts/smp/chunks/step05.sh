#!/usr/bin/env bash
# step05 — POSIX I/O thread-safety: fd-manager mutexing, free-list locking,
# block-device size fix. Recipe kind: whole-file (all single-step, clean).
set -euo pipefail
git checkout origin/smp -- \
  src/posix-io/file-descriptors-manager.cpp \
  include/cmsis-plus/posix-io/file-system.h \
  include/cmsis-plus/posix-io/net-stack.h \
  src/posix-io/block-device.cpp

# fd-manager.cpp's new bounds-checked descriptor-array accesses are
# -Wunsafe-buffer-usage under the destination's clang -Weverything; the file
# already suppresses it in three local blocks, and it is suppressed codebase-wide
# (io.cpp, os-thread.cpp, …). Make it file-level so the new accessors are covered.
python3 - "$(dirname "$0")" src/posix-io/file-descriptors-manager.cpp <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
from _edit import edit, replace_n
a = '#if defined(__clang__)\n#pragma clang diagnostic ignored "-Wc++98-compat"\n#endif\n'
edit(sys.argv[2], lambda s: replace_n(
    s, a,
    '#if defined(__clang__)\n#pragma clang diagnostic ignored "-Wc++98-compat"\n'
    '#pragma clang diagnostic ignored "-Wunsafe-buffer-usage"\n#endif\n',
    "step05 fd-manager unsafe-buffer-usage"))
PY
echo "[step05] applied (4 files whole + clang unsafe-buffer-usage suppress)"
