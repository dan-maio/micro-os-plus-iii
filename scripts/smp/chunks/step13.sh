#!/usr/bin/env bash
# step13 — high-resolution clock port synchronization. FIRST CROSS-REPO step:
#   kernel   src/rtos/os-clocks.cpp            — call port::clock_highres::has_hardware_counter()
#   cortexm  .../port/os-inlines.h             — has_hardware_counter()->false, hardware_counter()->0,
#                                                 cycles_since_tick() ICSR PENDSTSET fix
#   posix-arch .../port/os-inlines.h           — has_hardware_counter()->true, hardware_counter() CLOCK_MONOTONIC
#
# Recipe kinds: kernel whole-file; cortexm single-core projection (its os-inlines.h
# has SMP port-lock #if blocks); posix-arch SURGICAL insert (its os-inlines.h mixes
# Steps 14/15/17 per-CPU content that is NOT #if-gated, so neither whole-copy nor
# projection is safe — lift only the clock_highres block).
set -euo pipefail
SC="$(dirname "$0")/../sc-project.py"
source "$(dirname "$0")/../common.sh"     # K, P, C
F=include/cmsis-plus/rtos/port/os-inlines.h

# --- kernel: declares clock_highres::has_hardware_counter/hardware_counter
#     (os-decls.h) AND calls them (os-clocks.cpp). Both must travel together, or
#     the port's out-of-line definitions have no matching declaration.
git -C "$K" checkout origin/smp -- \
  include/cmsis-plus/rtos/os-decls.h \
  src/rtos/os-clocks.cpp

# --- cortexm: single-core projection (strips SMP port-lock blocks) ---
git -C "$C" show origin/smp:"$F" | python3 "$SC" > "$C/$F"

# --- posix-arch: insert only the clock_highres block into the baseline file ---
python3 - "$P/$F" <<'PY'
import sys
path = sys.argv[1]
block = '''      inline constexpr bool __attribute__ ((always_inline))
      clock_highres::has_hardware_counter (void) noexcept
      {
        return true;
      }

      inline uint64_t __attribute__ ((always_inline))
      clock_highres::hardware_counter (void) noexcept
      {
        timespec tp;   // NB: no 'struct' — baseline gate has -Werror=redundant-tags
        ::clock_gettime (CLOCK_MONOTONIC, &tp);
        return static_cast<uint64_t> (tp.tv_sec) * 1000000ULL
               + static_cast<uint64_t> (tp.tv_nsec) / 1000ULL;
      }

'''
s = open(path).read()
anchor = "    } /* namespace port */"
assert anchor in s, "posix-arch os-inlines.h: namespace port anchor not found"
s = s.replace(anchor, block + anchor, 1)
open(path, 'w').write(s)
print("[step13] posix-arch clock_highres inserted")
PY

# asserts
grep -q 'has_hardware_counter' "$C/$F" || { echo "[step13] cortexm highres missing"; exit 1; }
grep -qE 'OS_USE_SMP_SCHEDULER|_smp_' "$C/$F" && { echo "[step13] cortexm SMP leak"; exit 1; }
grep -q 'CLOCK_MONOTONIC' "$P/$F" || { echo "[step13] posix-arch highres missing"; exit 1; }
grep -qE '_this_cpu|port_cpu_id|_in_isr' "$P/$F" && { echo "[step13] posix-arch SMP leak"; exit 1; }
echo "[step13] applied (kernel whole + cortexm projection + posix-arch surgical)"
