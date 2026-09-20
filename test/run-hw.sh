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
# The verdict is read from the semihosted console, which OpenOCD prints into
# its own log.
#
# Deterministic restart without reset (the Pi has no SRST): halt all cores --
# so cores left running stale code cannot corrupt RAM during load_image --
# load the ELF, zero the __smp_spin launch slots, then resume every core at
# the kernel entry. startup.S does the rest: core 0 brings the system up,
# cores 1..N-1 park until the kernel releases them through __smp_spin + SEV.
#
# Usage:
#   run-hw.sh <build-test-dir> <app|all> [run-seconds]
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
#   UOS_HW_RESUME     pc   = set PC, then resume            (AArch64)
#                     cpsr = set CPSR, then resume at entry (AArch32)
#   UOS_HW_NCPU       cores to drive                (default: 4)
#   OPENOCD           openocd binary (default: newest xPack, else PATH)
set -uo pipefail

BUILD_DIR="${1:?usage: run-hw.sh <build-test-dir> <app|all> [run-seconds]}"
WHICH="${2:-all}"
RUN_SECS_ARG="${3:-}"

CFG="${UOS_HW_CFG:?run-hw.sh: the architecture project must set UOS_HW_CFG}"
[[ -f "$CFG" ]] || { echo "run-hw.sh: no such OpenOCD config: $CFG" >&2; exit 2; }
CFG_INIT="${UOS_HW_CFG_INIT:-0}"
NM="${UOS_HW_NM:-nm}"
READELF="${UOS_HW_READELF:-readelf}"
NCPU="${UOS_HW_NCPU:-4}"
SPIN_WORDS="${UOS_HW_SPIN_WORDS:-$((NCPU * 2))}"
RESUME_MODE="${UOS_HW_RESUME:-pc}"

OPENOCD="${OPENOCD:-$(ls -d "$HOME"/.local/xPacks/@xpack-dev-tools/openocd/*/.content/bin/openocd 2>/dev/null | sort -V | tail -1)}"
[[ -n "$OPENOCD" && -x "$OPENOCD" ]] || OPENOCD="$(command -v openocd || echo openocd)"
SCRIPTS="$(cd "$(dirname "$OPENOCD")/.." 2>/dev/null && pwd)/openocd/scripts"
[[ -d "$SCRIPTS" ]] || SCRIPTS=""

# Hardware runs at silicon speed, so these are far shorter than the QEMU
# timeouts in run-qemu.sh; they are the predecessor scripts' durations.
run_secs_for () {
  case "$1" in
    smp-mat-test|smp-mat-sdcard-test)                 echo 300 ;;
    sd_test|smp-num-test|smp-pipeline-test)           echo 240 ;;
    *)                                                echo 120 ;;
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
  if [[ "$RESUME_MODE" == "cpsr" ]]; then
    resume="foreach core {$(seq -s' ' 0 $((NCPU - 1)))} {
  targets bcm2837.cpu\$core
  reg cpsr 0x600001da
  resume $entry
}"
  else
    resume="foreach core {$(seq -s' ' 0 $((NCPU - 1)))} {
  targets bcm2837.cpu\$core
  reg pc $entry
  echo \"  start PC core \$core = [reg pc]\"
}
foreach core {$(seq -s' ' 0 $((NCPU - 1)))} {
  targets bcm2837.cpu\$core
  resume
}"
  fi

  # Quote nothing but the expansions we want: \$core must reach Tcl literally.
  cat > "$cfg" <<EOF
echo "--- stage: halt all cores ---"
foreach core {$(seq -s' ' 0 $((NCPU - 1)))} { targets bcm2837.cpu\$core; halt }
echo "--- stage: enable semihosting on all cores ---"
# Per-target: a core whose semihosting is off stalls at a debug halt the first
# time it traps, so every core needs it, not just core 0.
foreach core {$(seq -s' ' 0 $((NCPU - 1)))} { targets bcm2837.cpu\$core; arm semihosting enable }
echo "--- stage: load_image $elf ---"
targets bcm2837.cpu0
load_image $elf
echo "--- stage: zero __smp_spin at 0x${spin:-<absent>} (${SPIN_WORDS} words) ---"
${zero}echo "--- stage: resume all cores at $entry ---"
${resume}
EOF

  local args=(-s "$(dirname "$CFG")")
  [[ -n "$SCRIPTS" ]] && args+=(-s "$SCRIPTS")
  args+=(-f "$CFG")
  # A declarative config leaves init to us, so the halt/load/resume commands
  # run strictly post-init. A config that inits itself must not be told twice.
  [[ "$CFG_INIT" == "1" ]] && args+=(-c "init")
  args+=(-f "$cfg")

  printf '%-24s ' "$app"
  "$OPENOCD" "${args[@]}" > "$log" 2>&1 &
  local ocd=$!

  local rc=2 waited=0
  while ((waited < secs)); do
    if grep -q 'RESULT: PASS' "$log" 2>/dev/null; then rc=0; break; fi
    if grep -q 'RESULT: SKIP' "$log" 2>/dev/null; then rc=3; break; fi
    if grep -qE 'RESULT: FAIL|\[FAIL\]|FAIL:|FATAL:' "$log" 2>/dev/null; then rc=1; break; fi
    if ! kill -0 "$ocd" 2>/dev/null; then rc=4; break; fi
    if grep -qE '^Error: ' "$log" 2>/dev/null; then rc=5; break; fi
    sleep 1; waited=$((waited + 1))
  done

  kill "$ocd" 2>/dev/null; wait "$ocd" 2>/dev/null
  # Give the probe a moment to release the USB interface before the next test.
  sleep 1

  case "$rc" in
    0) echo "PASS  (${waited}s)" ;;
    3) echo "SKIP  ($(sed -n 's/.*RESULT: SKIP *//p' "$log" | head -1))" ;;
    1) echo "FAIL  (see $log)" ;;
    4) echo "OPENOCD DIED  (see $log)" ;;
    5) echo "OPENOCD ERROR: $(grep -m1 '^Error: ' "$log")" ;;
    *) echo "TIMEOUT after ${secs}s  (see $log)" ;;
  esac
  return "$rc"
}

pass=0; fail=0; skip=0
if [[ "$WHICH" == "all" ]]; then
  shopt -s nullglob
  elfs=("${BUILD_DIR}"/*-hwd)
  shopt -u nullglob
  ((${#elfs[@]})) || { say "no *-hwd executables in ${BUILD_DIR}"; exit 2; }
else
  elfs=("${BUILD_DIR}/${WHICH}-hwd")
  [[ -x "${elfs[0]}" ]] || { say "no such build: ${elfs[0]}"; exit 2; }
fi

for elf in "${elfs[@]}"; do
  [[ -x "$elf" ]] || continue
  app="$(basename "$elf" -hwd)"
  run_one "$app" "$elf"
  case $? in
    0) pass=$((pass + 1)) ;;
    3) skip=$((skip + 1)) ;;
    *) fail=$((fail + 1)) ;;
  esac
done

echo
echo "hardware suite: ${pass} passed, ${skip} skipped, ${fail} failed"
[[ $fail -eq 0 ]]
