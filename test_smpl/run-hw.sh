#!/usr/bin/env bash
# run-hw.sh — run the `hwd` test builds on real silicon, through OpenOCD.
#
# The hardware counterpart of run-qemu.sh, and the single copy of what the
# predecessor repository kept as `hw.sh` + `hw-olimex.sh` in every test
# directory of every port (~200 near-identical lines, 48 files).
#
# PURE OpenOCD. No GDB, no reset, and NO serial redirection: the UART console
# is yours, in your own terminal (tio/picocom on /dev/ttyACM0). This script
# never opens the tty, so it cannot fight the terminal you have open on it.
# Everything OpenOCD and the board's semihosting write goes straight to this
# terminal as it happens; a copy is teed to a log only so the verdict can be
# matched.
#
# Deterministic restart without reset (the Pi has no SRST): halt all cores --
# so cores left running stale code cannot corrupt RAM during load_image --
# load the ELF, zero the __smp_spin launch slots, then resume every core at
# the kernel entry. startup.S does the rest: core 0 brings the system up,
# cores 1..N-1 park until the kernel releases them through __smp_spin + SEV.
#
# ONE TEST PER POWER CYCLE. Every run is a debug-in-RAM run: OpenOCD halts
# the cores and load_image's the ELF over whatever the previous test left in
# DRAM. Neither board offers a reset this script can drive -- the Pi has no
# SRST and its Cortex-A53 debug target has no reset method, and the Lyra's
# secondaries are released once, by clearing their CRU reset bits, which a
# second run cannot undo. Only a power cycle puts either board back into a
# known state. That is why this script refuses to run a suite: it takes
# exactly one test, and you reset the board before the next.
#
# Usage:
#   run-hw.sh <build-test-dir> <app> [run-seconds]
#   run-hw.sh <build-test-dir> list
#
# The architecture project supplies the ISA facts, the way run-qemu.sh takes
# the machine arguments from its caller -- this script stays ISA-neutral:
#
#   UOS_HW_CFG        OpenOCD probe/board config (required)
#   UOS_HW_CFG_INIT   1 = the config is declarative, so issue `-c init`
#                     0 = the config inits itself (default)
#   UOS_HW_NM         nm for the port's ELFs        (default: nm)
#   UOS_HW_READELF    readelf for the port's ELFs   (default: readelf)
#   UOS_HW_ENTRY      fallback entry if the ELF has none
#   UOS_HW_SPIN_WORDS 32-bit words in __smp_spin[]  (default: 2 * NCPU)
#   UOS_HW_RESUME     pc    = set PC, then resume             (AArch64)
#                     cpsr  = set CPSR, then resume at entry  (AArch32, Pi)
#                     entry = resume at entry, touching no register. The
#                             RK3506's miniloader hands core 0 over in SVC
#                             already, and this is what the board's own
#                             loader has always done.
#   UOS_HW_NCPU       cores the port schedules on  (default: 4)
#   UOS_HW_TARGET_FMT printf format for the OpenOCD target names, with the
#                     core index as the only conversion
#                     (default: bcm2837.cpu%d; the Lyra is rk3506.a7.%d)
#   UOS_HW_CORES      which core indices this script drives, space separated
#                     (default: all of them). A board whose secondaries are
#                     held in BootROM until the kernel releases them --
#                     declared `-defer-examine` in its OpenOCD config -- has
#                     no debug target to halt yet, so it lists only "0".
#   UOS_HW_PRELOAD    Tcl run after the halt and before load_image, on the
#                     first core listed. The RK3506 needs it: the miniloader
#                     leaves the MMU and caches ON, and load_image writing
#                     through them leaves DRAM holding something other than
#                     the image.
#   UOS_HW_ADAPTER_KHZ  override the JTAG clock after init. board/rpi3.cfg
#                     asks for 4000 kHz, which is more than jumper wires
#                     reliably carry -- especially while the board is drawing
#                     USB and SD current. A DAP that gives up mid-run reports
#                     "Invalid ACK (0) in DAP response" and then fails to
#                     re-examine every core; drop to 1000 and retry before
#                     suspecting the firmware.
#   OPENOCD           openocd binary (default: newest xPack, else PATH)
set -uo pipefail

BUILD_DIR="${1:?usage: run-hw.sh <build-test-dir> <app|list> [run-seconds]}"
WHICH="${2:-list}"
RUN_SECS_ARG="${3:-}"

CFG="${UOS_HW_CFG:?run-hw.sh: the architecture project must set UOS_HW_CFG}"
[[ -f "$CFG" ]] || { echo "run-hw.sh: no such OpenOCD config: $CFG" >&2; exit 2; }
CFG_INIT="${UOS_HW_CFG_INIT:-0}"
NM="${UOS_HW_NM:-nm}"
READELF="${UOS_HW_READELF:-readelf}"
NCPU="${UOS_HW_NCPU:-4}"
SPIN_WORDS="${UOS_HW_SPIN_WORDS:-$((NCPU * 2))}"
RESUME_MODE="${UOS_HW_RESUME:-pc}"
ADAPTER_KHZ="${UOS_HW_ADAPTER_KHZ:-}"
TARGET_FMT="${UOS_HW_TARGET_FMT:-bcm2837.cpu%d}"
CORES="${UOS_HW_CORES:-$(seq -s' ' 0 $((NCPU - 1)))}"
PRELOAD="${UOS_HW_PRELOAD:-}"

# The OpenOCD target name for a core index, and the first core in the list --
# the one the image is loaded through.
target_name () { printf "$TARGET_FMT" "$1"; }
FIRST_CORE="${CORES%% *}"
FIRST_TARGET="$(target_name "$FIRST_CORE")"

OPENOCD="${OPENOCD:-$(ls -d "$HOME"/.local/xPacks/@xpack-dev-tools/openocd/*/.content/bin/openocd 2>/dev/null | sort -V | tail -1)}"
[[ -n "$OPENOCD" && -x "$OPENOCD" ]] || OPENOCD="$(command -v openocd || echo openocd)"
SCRIPTS="$(cd "$(dirname "$OPENOCD")/.." 2>/dev/null && pwd)/openocd/scripts"
[[ -d "$SCRIPTS" ]] || SCRIPTS=""

# A hardware budget is NOT the test's own duration -- it is dominated by the
# semihosting traps, and those scale with how much the test prints, not with
# how long it thinks it runs. Measured: smp_test4 reaches its verdict at
# t=9597ms of target time, yet needs over 120s of wall clock, because its
# reporter emits ~9 lines a second and every `<<` is a separate SYS_WRITE0,
# each a debug halt/resume over JTAG at roughly 0.15s.
#
# So the chatty tests get generous budgets. Override with the third argument.
run_secs_for () {
  case "$1" in
    smp_test0|smp_test1|smp_test2|smp_test3)          echo 120 ;;  # measured
    smp_test4)                                        echo 300 ;;  # measured
    smp-mat-test|smp-mat-sdcard-test)                 echo 900 ;;
    smp-num-test|smp-pipeline-test|smp-pro-cons-test) echo 600 ;;
    sd_test)                                          echo 450 ;;
    usb_test)                                         echo 300 ;;
    *)                                                echo 300 ;;
  esac
}

say () { echo "[hw] $*"; }

LOGS="${BUILD_DIR}/.hw-logs"; mkdir -p "$LOGS"

if pgrep -x openocd >/dev/null 2>&1; then
  say "WARNING: an OpenOCD process is already running — the probe may be busy"
  say "         (LIBUSB_ERROR_BUSY). Kill it first: pkill -9 -f openocd"
fi

run_one () {
  local app="$1" elf="$2"
  local secs="${RUN_SECS_ARG:-$(run_secs_for "$app")}"
  local log="${LOGS}/${app}.log"
  local cfg="${LOGS}/${app}.cfg"
  rm -f "$log"

  # Kernel entry (_start) as the ELF records it.
  local entry
  entry="$("$READELF" -h "$elf" 2>/dev/null | awk '/Entry point/{print $NF}')"
  [[ -n "$entry" ]] || entry="${UOS_HW_ENTRY:-}"
  [[ -n "$entry" ]] || { say "$app: cannot determine the entry point"; return 1; }

  # __smp_spin launch slots, zeroed after the load so a secondary that reaches
  # its parking loop before core 0 clears .bss cannot jump to a stale entry.
  local spin zero="" base i
  spin="$("$NM" "$elf" 2>/dev/null | awk '$3 == "__smp_spin" {print $1; exit}')"
  if [[ -n "$spin" ]]; then
    base=$((16#$spin))
    for ((i = 0; i < SPIN_WORDS; ++i)); do
      zero+="mww 0x$(printf '%x' $((base + 4 * i))) 0"$'\n'
    done
  fi

  # The per-core resume. AArch64 keeps the exception level its cores were
  # halted in, which is what startup.S dispatches on, so setting the PC is the
  # whole of it. AArch32 has to force the mode through CPSR first.
  local resume
  case "$RESUME_MODE" in
    cpsr)
      resume="foreach core {$CORES} {
  targets [format {$TARGET_FMT} \$core]
  reg cpsr 0x600001da
  resume $entry
}" ;;
    entry)
      resume="foreach core {$CORES} {
  targets [format {$TARGET_FMT} \$core]
  resume $entry
}" ;;
    *)
      resume="foreach core {$CORES} {
  targets [format {$TARGET_FMT} \$core]
  reg pc $entry
  echo \"  start PC core \$core = [reg pc]\"
}
foreach core {$CORES} {
  targets [format {$TARGET_FMT} \$core]
  resume
}" ;;
  esac

  # Quote nothing but the expansions we want: \$core must reach Tcl literally.
  local speed=""
  if [[ -n "$ADAPTER_KHZ" ]]; then
    speed="echo \"--- stage: JTAG clock -> ${ADAPTER_KHZ} kHz ---\"
adapter speed ${ADAPTER_KHZ}"
  fi

  local spin_stage=""
  if [[ -n "$zero" ]]; then
    spin_stage="echo \"--- stage: zero __smp_spin at 0x${spin} (${SPIN_WORDS} words) ---\"
${zero}"
  fi
  local preload_stage=""
  if [[ -n "$PRELOAD" ]]; then
    preload_stage="echo \"--- stage: pre-load ---\"
targets ${FIRST_TARGET}
${PRELOAD}
"
  fi

  cat > "$cfg" <<EOF
${speed:+$speed
}echo "--- stage: halt cores $CORES ---"
foreach core {$CORES} { targets [format {$TARGET_FMT} \$core]; halt }
echo "--- stage: enable semihosting on cores $CORES ---"
# Per-target: a core whose semihosting is off stalls at a debug halt the first
# time it traps, so every core needs it, not just core 0.
foreach core {$CORES} { targets [format {$TARGET_FMT} \$core]; arm semihosting enable }
${preload_stage}echo "--- stage: load_image $elf ---"
targets ${FIRST_TARGET}
load_image $elf
${spin_stage}echo "--- stage: resume cores $CORES at $entry ---"
${resume}
EOF

  local args=(-s "$(dirname "$CFG")")
  [[ -n "$SCRIPTS" ]] && args+=(-s "$SCRIPTS")
  args+=(-f "$CFG")
  # A declarative config leaves init to us, so the halt/load/resume commands
  # run strictly post-init. A config that inits itself must not be told twice.
  [[ "$CFG_INIT" == "1" ]] && args+=(-c "init")
  args+=(-f "$cfg")

  # OpenOCD runs with its output on this terminal, so the board's semihosting
  # writes appear as they happen. The copy in $log exists only so the loop
  # below can see the test's verdict; nothing is hidden by it.
  say "--- $app (${secs}s max) ---"
  "$OPENOCD" "${args[@]}" > >(tee "$log") 2>&1 &
  local ocd=$!

  local rc=2 waited=0
  while ((waited < secs)); do
    if grep -q 'RESULT: PASS' "$log" 2>/dev/null; then rc=0; break; fi
    if grep -q 'RESULT: SKIP' "$log" 2>/dev/null; then rc=3; break; fi
    if grep -qE 'RESULT: FAIL|\[FAIL\]|FAIL:|FATAL:' "$log" 2>/dev/null; then rc=1; break; fi
    if ! kill -0 "$ocd" 2>/dev/null; then rc=4; break; fi
    if grep -qE 'Invalid ACK|Polling failed|Examination failed' "$log" 2>/dev/null; then
      rc=6; break
    fi
    if grep -qE '^Error: ' "$log" 2>/dev/null; then rc=5; break; fi
    sleep 1; waited=$((waited + 1))
  done

  kill "$ocd" 2>/dev/null; wait "$ocd" 2>/dev/null
  # Give the probe a moment to release the USB interface before the next test.
  sleep 1

  printf '\n%-24s ' "$app"
  case "$rc" in
    0) echo "PASS  (${waited}s)" ;;
    3) echo "SKIP  ($(sed -n 's/.*RESULT: SKIP *//p' "$log" | head -1))" ;;
    1) echo "FAIL" ;;
    4) echo "OPENOCD DIED" ;;
    5) echo "OPENOCD ERROR: $(grep -m1 '^Error: ' "$log")" ;;
    6) echo "DEBUG LINK LOST  (the DAP stopped answering, not a firmware fault)"
       echo "    retry with UOS_HW_ADAPTER_KHZ=1000, and check the board's supply" ;;
    *) echo "TIMEOUT after ${secs}s" ;;
  esac
  return "$rc"
}

shopt -s nullglob
available=("${BUILD_DIR}"/*-hwd)
shopt -u nullglob
((${#available[@]})) || { say "no *-hwd executables in ${BUILD_DIR}"; exit 2; }

if [[ "$WHICH" == "list" ]]; then
  echo "hardware tests built in ${BUILD_DIR}:"
  for elf in "${available[@]}"; do
    app="$(basename "$elf" -hwd)"
    printf '  %-22s %4ss\n' "$app" "$(run_secs_for "$app")"
  done
  echo
  echo "Run one, then power-cycle the board before the next."
  exit 0
fi

if [[ "$WHICH" == "all" ]]; then
  say "refusing to run a suite."
  say "Each test is loaded into RAM over whatever the previous one left there,"
  say "and neither board has a reset this script can drive. Run one test,"
  say "power-cycle the board, then run the next. '$0 $BUILD_DIR list' shows them."
  exit 2
fi

ELF="${BUILD_DIR}/${WHICH}-hwd"
[[ -x "$ELF" ]] || { say "no such build: $ELF   (try: $0 $BUILD_DIR list)"; exit 2; }

run_one "$WHICH" "$ELF"
rc=$?
echo
case "$rc" in
  0) say "$WHICH PASSED — power-cycle the board before the next test." ;;
  3) say "$WHICH SKIPPED — power-cycle the board before the next test." ;;
  *) say "$WHICH did not pass — power-cycle the board before retrying." ;;
esac
[[ $rc -eq 0 || $rc -eq 3 ]]
