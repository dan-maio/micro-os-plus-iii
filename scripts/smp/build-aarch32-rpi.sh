#!/usr/bin/env bash
# scripts/smp/build-aarch32-rpi.sh [test...] — build+run the aarch32 (ARMv7-A)
# SMP integration on QEMU raspi3b, 4-core. BOARD=rpi3b|rpi-zero-2w.
#
# Mirrors build-aarch64-rpi.sh, with the AArch32 differences:
#   * arm-none-eabi toolchain, ARMv7-A flags (-marm -mcpu=cortex-a53 neon-fp-armv8)
#   * ARMv7-A IS __ARM_EABI__, so the KERNEL's own free-store + _sbrk apply — the
#     port supplies NEITHER (unlike aarch64).
#   * QEMU raspi3b starts its A53s in AArch64, so the image is reached through a
#     tiny AArch64 -> AArch32 shim8.img (built here) + -device loader at 0x10000.
# LOCAL only; never pushes.
set -euo pipefail
source "$(dirname "$0")/common.sh"          # K (kernel)
A="${A32:-$WORK/micro-os-plus-iii-aarch32}"
S="${XPACKS_STORE:-$HOME/.local/xPacks}"
ARM="$S/@xpack-dev-tools/arm-none-eabi-gcc/15.2.1-1.1.1/.content/bin"
A64="$S/@xpack-dev-tools/aarch64-none-elf-gcc/15.2.1-1.1.1/.content/bin"
QEMU="$(ls "$S"/@xpack-dev-tools/qemu-arm/*/.content/bin/qemu-system-aarch64 2>/dev/null | sort -V | tail -1)"
CXX="$ARM/arm-none-eabi-g++"; CC="$ARM/arm-none-eabi-gcc"; OBJCOPY="$ARM/arm-none-eabi-objcopy"
BSP="$A/test/boards/rpi-zero-2w"
SHIMDIR="$BSP/qemu-raspi3-shim"

BOARD="${BOARD:-rpi3b}"
case "$BOARD" in
  rpi3b)       LD="$BSP/linker-rpi3b.ld"; TESTDIR="test/rpi3b"
               BOARD_DEF=(-DBOARD_RPI3B '-DPORT_GREETING="uOS++ RPi3B AArch32 SMP"') ;;
  rpi-zero-2w) LD="$BSP/linker.ld";       TESTDIR="test/rpi-zero-2w"
               BOARD_DEF=(-DLED_PIN=29 '-DPORT_GREETING="uOS++ RPi Zero 2W AArch32 SMP"') ;;
  *) die "unknown BOARD '$BOARD'" ;;
esac
OUT="${OUT:-/tmp/a32-$BOARD}"; mkdir -p "$OUT/obj"

INC=(-I"$A/include" -I"$BSP/include" -I"$A/soc/bcm2837/include"
     -I"$K/include" -I"$K/include/cmsis-plus/legacy" -I"$K/port/smp-common"
     -I"$K/tests/smp-support/include" -I"$A/$TESTDIR/include")
DEF=(-DTRACE -DDEBUG -DSEMIHOST -DQEMU_BUILD -DOS_USE_OS_APP_CONFIG_H
     -DOS_USE_SMP_SCHEDULER=1 -DOS_NCPU=4 -DSOC_BCM2837
     -DSEMIHOST_TRAP_CHOSEN -DSEMIHOST_TRAP_HLT -DOS_SMP_IPI_SGI=0 "${BOARD_DEF[@]}")
CXXF=(-marm -mcpu=cortex-a53 -mfloat-abi=hard -mfpu=neon-fp-armv8 -std=c++20 -fno-rtti
      -ffunction-sections -fdata-sections -O2 -c)
CF=(-marm -mcpu=cortex-a53 -mfloat-abi=hard -mfpu=neon-fp-armv8 -ffunction-sections -fdata-sections -O2 -c)

# Thin kernel (same 37-file set; on EABI the free-store + _sbrk ARE emitted).
KSRC_CPP=(diag/trace libcpp/chrono libcpp/condition-variable libcpp/cxx
  libcpp/memory-resource libcpp/mutex libcpp/new libcpp/system-error libcpp/thread
  libc/stdlib/atexit libc/stdlib/malloc memory/block-pool memory/first-fit-top
  memory/lifo rtos/internal/os-flags rtos/internal/os-lists rtos/os-clocks
  rtos/os-condvar rtos/os-core rtos/os-c-wrapper rtos/os-evflags rtos/os-idle
  rtos/os-main rtos/os-memory rtos/os-mempool rtos/os-mqueue rtos/os-mutex
  rtos/os-semaphore rtos/os-thread rtos/os-timer startup/initialise-free-store
  utils/lists)
KSRC_C=(libc/_sbrk libc/stdlib/assert libc/stdlib/exit libc/stdlib/init-fini libc/stdlib/timegm)

compile () { local cc="$1"; shift; local -n _f="$1"; shift
  "$cc" "${_f[@]}" "${INC[@]}" "${DEF[@]}" "$1" -o "$2"; }

log "building AArch32->AArch64 shim8.img"
"$A64/aarch64-none-elf-gcc" -nostdlib -Wl,-T,"$SHIMDIR/shim.ld" "$SHIMDIR/shim.S" -o "$OUT/shim.elf"
"$A64/aarch64-none-elf-objcopy" -O binary "$OUT/shim.elf" "$OUT/shim8.img"

log "compiling thin kernel + aarch32 port + BSP + SoC"
for s in "${KSRC_CPP[@]}"; do compile "$CXX" CXXF "$K/src/$s.cpp" "$OUT/obj/k_${s//\//_}.o"; done
for s in "${KSRC_C[@]}";   do compile "$CC"  CF   "$K/src/$s.c"   "$OUT/obj/k_${s//\//_}.o"; done
for s in rtos/os-core context_switch exception_handler handlers smp_secondary semihosting-exit; do
  compile "$CXX" CXXF "$A/src/$s.cpp" "$OUT/obj/p_${s//\//_}.o"; done
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
  "$CXX" -marm -mcpu=cortex-a53 -mfloat-abi=hard -mfpu=neon-fp-armv8 -T "$LD" \
    -nostartfiles -Wl,--gc-sections "${BASE_OBJS[@]}" "$OUT/obj/main_$t.o" -o "$OUT/$t.elf"
  "$OBJCOPY" -O binary "$OUT/$t.elf" "$OUT/$t.bin"
  res="$(timeout 40 "$QEMU" -M raspi3b -smp 4 -nographic -serial null \
         -semihosting-config enable=on,target=native \
         -kernel "$OUT/shim8.img" -device "loader,file=$OUT/$t.bin,addr=0x10000" 2>&1 \
         | grep -E 'RESULT:' | head -1 || true)"
  if printf '%s' "$res" | grep -q PASS; then ok "$t: ${res:-PASS}"; pass=$((pass+1))
  else warn "$t: ${res:-<no RESULT / timeout>}"; fail=$((fail+1)); fi
done
# NOTE: the portable harness suites are NOT built here — see build-aarch64-rpi.sh.
# They are wired by the smp branch's tests.cmake + harness platform-support.cpp and
# run through the xPack harness; injected from origin/smp, not reconstructed here.

echo; [ "$fail" -eq 0 ] && ok "aarch32-$BOARD: $pass/$((pass+fail)) smp tests PASS (QEMU raspi3b shim, 4-core SMP)" \
  || die "aarch32-$BOARD: $fail/$((pass+fail)) FAILED"
