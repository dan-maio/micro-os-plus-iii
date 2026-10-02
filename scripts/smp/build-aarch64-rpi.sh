#!/usr/bin/env bash
# scripts/smp/build-aarch64-rpi3b.sh [test...] — reproduce the aarch64-rpi3b SMP
# integration build+run that was proven in the dry run. Compiles the thin kernel
# + the aarch64 port + the A53 BSP + the BCM2837 SoC (dissolved out of devices)
# + the port-supplied free-store/syscalls, links with linker-rpi3b.ld, and runs
# each test on qemu-system-aarch64 -M raspi3b -smp 4 (4-core SMP), reporting
# PASS/FAIL. Defaults to smp_test0..4. LOCAL only; never pushes.
#
# Prereqs: xPack aarch64-none-elf-gcc 15.2 and qemu-arm in the store; the three
# repos checked out with the aarch64 integration applied (see STATUS.md) at
# branches that carry: kernel port/smp-common + tests/smp-support + thin core; aarch64
# port src/ + include/ + src/free-store.cpp + src/syscalls.c + soc/bcm2837 +
# test/boards/rpi-zero-2w (BSP) + test/rpi3b (tests).
set -euo pipefail
source "$(dirname "$0")/common.sh"          # K (kernel); aarch64 repo derived below
A="${A64:-$WORK/micro-os-plus-iii-aarch64}"
S="${XPACKS_STORE:-$HOME/.local/xPacks}"
GCCDIR="$S/@xpack-dev-tools/aarch64-none-elf-gcc/15.2.1-1.1.1/.content/bin"
QEMU="$(ls "$S"/@xpack-dev-tools/qemu-arm/*/.content/bin/qemu-system-aarch64 2>/dev/null | sort -V | tail -1)"
CXX="$GCCDIR/aarch64-none-elf-g++"; CC="$GCCDIR/aarch64-none-elf-gcc"
OBJCOPY="$GCCDIR/aarch64-none-elf-objcopy"
BSP="$A/test/boards/rpi-zero-2w"           # shared A53 BSP for both boards
# Board selection: both are BCM2837 / 4x A53 / QEMU raspi3b; they differ only in
# the linker script, the test directory and a couple of board defines.
BOARD="${BOARD:-rpi3b}"
case "$BOARD" in
  rpi3b)       LD="$BSP/linker-rpi3b.ld"; TESTDIR="test/rpi3b"
               BOARD_DEF=(-DBOARD_RPI3B '-DPORT_GREETING="uOS++ RPi3B (BCM2837, 4x Cortex-A53)"') ;;
  rpi-zero-2w) LD="$BSP/linker.ld";       TESTDIR="test/rpi-zero-2w"
               BOARD_DEF=(-DLED_PIN=29 '-DPORT_GREETING="uOS++ RPi Zero 2W (BCM2837, 4x Cortex-A53)"') ;;
  *) die "unknown BOARD '$BOARD' (use rpi3b or rpi-zero-2w)" ;;
esac
OUT="${OUT:-/tmp/a64-$BOARD}"; mkdir -p "$OUT/obj"

INC=(-I"$A/include" -I"$BSP/include" -I"$A/soc/bcm2837/include"
     -I"$K/include" -I"$K/include/cmsis-plus/legacy" -I"$K/port/smp-common"
     -I"$K/tests/smp-support/include" -I"$A/$TESTDIR/include")
DEF=(-DTRACE -DDEBUG -DSEMIHOST -DQEMU_BUILD -DOS_USE_OS_APP_CONFIG_H
     -DOS_USE_SMP_SCHEDULER=1 -DOS_NCPU=4 -DSOC_BCM2837
     -DSEMIHOST_TRAP_CHOSEN -DSEMIHOST_TRAP_HLT -DOS_SMP_IPI_SGI=0
     "${BOARD_DEF[@]}")
CXXF=(-mcpu=cortex-a53 -std=c++20 -fno-rtti -ffunction-sections -fdata-sections -O2 -c)
CF=(-mcpu=cortex-a53 -ffunction-sections -fdata-sections -O2 -c)

# Thin kernel core (same 37-file list as micro-os-plus::iii-core).
KSRC_CPP=(diag/trace libcpp/chrono libcpp/condition-variable libcpp/cxx
  libcpp/memory-resource libcpp/mutex libcpp/new libcpp/system-error libcpp/thread
  libc/stdlib/atexit libc/stdlib/malloc memory/block-pool memory/first-fit-top
  memory/lifo rtos/internal/os-flags rtos/internal/os-lists rtos/os-clocks
  rtos/os-condvar rtos/os-core rtos/os-c-wrapper rtos/os-evflags rtos/os-idle
  rtos/os-main rtos/os-memory rtos/os-mempool rtos/os-mqueue rtos/os-mutex
  rtos/os-semaphore rtos/os-thread rtos/os-timer startup/initialise-free-store
  utils/lists)
KSRC_C=(libc/_sbrk libc/stdlib/assert libc/stdlib/exit libc/stdlib/init-fini libc/stdlib/timegm)

compile () { # compile <cc> <flags-array-name> <src> <obj>
  local cc="$1"; shift; local -n _f="$1"; shift; local src="$1" obj="$2"
  "$cc" "${_f[@]}" "${INC[@]}" "${DEF[@]}" "$src" -o "$obj"
}

log "compiling thin kernel ($((${#KSRC_CPP[@]}+${#KSRC_C[@]})) files) + port + BSP + SoC"
for s in "${KSRC_CPP[@]}"; do compile "$CXX" CXXF "$K/src/$s.cpp" "$OUT/obj/k_${s//\//_}.o"; done
for s in "${KSRC_C[@]}";   do compile "$CC"  CF   "$K/src/$s.c"   "$OUT/obj/k_${s//\//_}.o"; done
for s in rtos/os-core context_switch exception_handler handlers smp_secondary free-store; do
  compile "$CXX" CXXF "$A/src/$s.cpp" "$OUT/obj/p_${s//\//_}.o"; done
compile "$CC" CF "$A/src/syscalls.c" "$OUT/obj/p_syscalls.o"
for s in mmu port_sys rtos/port_isr smp timer_arm; do
  compile "$CXX" CXXF "$BSP/src/$s.cpp" "$OUT/obj/b_${s//\//_}.o"; done
compile "$CC" CF "$BSP/src/startup.S" "$OUT/obj/b_startup.o"
compile "$CXX" CXXF "$A/soc/bcm2837/src/mailbox.cpp" "$OUT/obj/b_mailbox.o"
compile "$CXX" CXXF "$K/tests/smp-support/src/board-contract.cpp" "$OUT/obj/b_board-contract.o"
compile "$CXX" CXXF "$A/$TESTDIR/src/test-smp-boot.cpp" "$OUT/obj/b_test-smp-boot.o"
ok "common objects built"

BASE_OBJS=("$OUT"/obj/k_*.o "$OUT"/obj/p_*.o "$OUT"/obj/b_*.o)
tests=("$@"); [ ${#tests[@]} -eq 0 ] && tests=(smp_test0 smp_test1 smp_test2 smp_test3 smp_test4)
pass=0; fail=0
for t in "${tests[@]}"; do
  compile "$CXX" CXXF "$A/$TESTDIR/$t/main.cpp" "$OUT/obj/main_$t.o"
  "$CXX" -mcpu=cortex-a53 -T "$LD" -nostartfiles -Wl,--gc-sections \
    "${BASE_OBJS[@]}" "$OUT/obj/main_$t.o" -o "$OUT/$t.elf"
  "$OBJCOPY" -O binary "$OUT/$t.elf" "$OUT/$t.bin"
  res="$(timeout 40 "$QEMU" -M raspi3b -smp 4 -nographic -serial null \
         -semihosting-config enable=on,target=native -kernel "$OUT/$t.bin" 2>&1 \
         | grep -E 'RESULT:' | head -1 || true)"
  if printf '%s' "$res" | grep -q PASS; then ok "$t: ${res:-PASS}"; pass=$((pass+1))
  else warn "$t: ${res:-<no RESULT / timeout>}"; fail=$((fail+1)); fi
done
# NOTE: the portable harness suites (mutex-stress, rtos-apis, cmsis-os-validator)
# are NOT built here. They are wired by the smp branch's own
# test/rpi3b/tests.cmake + harness platform-support.cpp (strong main + startup
# hooks) and run through the xPack harness (xpm + CMake + run-qemu.sh). Those are
# injected from origin/smp during Step 27/28, not reconstructed by this script,
# which only reproduces the standalone smp_test0..4 bring-up.

echo; [ "$fail" -eq 0 ] && ok "aarch64-$BOARD: $pass/$((pass+fail)) smp tests PASS (QEMU raspi3b, 4-core SMP)" \
  || die "aarch64-$BOARD: $fail/$((pass+fail)) FAILED"
