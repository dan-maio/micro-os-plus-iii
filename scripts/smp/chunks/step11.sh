#!/usr/bin/env bash
# step11 — std::thread functor lifetime & join synchronization.
# Recipe kind: whole-file (both single-step, clean).
# Note: thread-cpp.h lives under src/libcpp/, not include/.
set -euo pipefail
git checkout origin/smp -- \
  src/libcpp/thread-cpp.h \
  include/cmsis-plus/estd/thread_internal.h
echo "[step11] applied (2 files whole)"
