#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run-qemu.sh <build-test-dir> <qemu-binary> <machine-args...>
#
# Runs every *-qemu image in a build directory and reports PASS/FAIL from the
# RESULT line each test prints. Architecture-neutral: the caller supplies the
# QEMU binary and the machine flags, which are the only parts that differ
# between ports.
#
#   test_smpl/run-qemu.sh build/test "$(…)/qemu-system-aarch64" -M raspi3b -smp 4
#
# The per-test timeouts are the ones the predecessor repository's
# run_one_test.sh used; they are wall-clock budgets, not expected durations.
# -----------------------------------------------------------------------------
set -uo pipefail

BUILD_DIR="${1:?usage: run-qemu.sh <build-test-dir> <qemu> <machine-args...>}"
QEMU="${2:?usage: run-qemu.sh <build-test-dir> <qemu> <machine-args...>}"
shift 2
MACHINE=("$@")

# Some ports cannot be handed straight to -kernel. The AArch32 BCM2837 build is
# one: QEMU's raspi3b machine starts its Cortex-A53 cores in AArch64, so the
# image is loaded at an address and a small shim drops to AArch32 and jumps
# there. Set both to use that path; leave them unset for a direct -kernel boot.
#
#   UOS_QEMU_SHIM=/path/to/shim8.img UOS_QEMU_LOAD_ADDR=0x10000 test_smpl/run-qemu.sh ...
SHIM="${UOS_QEMU_SHIM:-}"
LOAD_ADDR="${UOS_QEMU_LOAD_ADDR:-0x10000}"
if [[ -n "$SHIM" && ! -f "$SHIM" ]]; then
  echo "UOS_QEMU_SHIM is set but $SHIM does not exist" >&2
  exit 2
fi

timeout_for () {
  case "$1" in
    smp_test0|smp_test1|smp_test3|smp_test4) echo 150 ;;
    smp_test2)                               echo 300 ;;
    smp-mat-test)                            echo 900 ;;
    smp-mat-sdcard-test)                     echo 2000 ;;
    smp-num-test|smp-pipeline-test|smp-pro-cons-test) echo 1000 ;;
    sd_test)                                 echo 450 ;;
    usb_test)                                echo 200 ;;
    *)                                       echo 300 ;;
  esac
}

# Tests that talk to the SD card need a card to talk to. sd_test wants a
# seeded flatfs volume (its own flatfs_tool.py builds one); the others just
# need a large enough blank image to format. Kept out of git by .gitignore --
# a 4 GiB sparse file per test.
COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common"

sd_image_for () {
  local app="$1" img="${LOGS}/${app}.disk.img"
  case "$app" in
    sd_test)
      if [[ ! -f "$img" ]]; then
        python3 "${COMMON_DIR}/sd_test/flatfs_tool.py" make-seed "$img" >/dev/null \
          || { echo "could not seed $img" >&2; return 1; }
      fi
      ;;
    smp-mat-sdcard-test|smp-num-test|smp-pipeline-test)
      [[ -f "$img" ]] || truncate -s 4G "$img"
      ;;
    *)
      return 1
      ;;
  esac
  echo "$img"
}

LOGS="${BUILD_DIR}/.qemu-logs"; mkdir -p "$LOGS"
pass=0; fail=0; skip=0; declare -a results=()

for img in "${BUILD_DIR}"/*-qemu.bin; do
  [[ -e "$img" ]] || { echo "no *-qemu.bin in ${BUILD_DIR}"; exit 2; }
  app="$(basename "$img" -qemu.bin)"
  tmo="$(timeout_for "$app")"
  log="${LOGS}/${app}.log"

  printf '%-24s ' "$app"

  drive=()
  if sd="$(sd_image_for "$app")"; then
    drive=(-drive "file=${sd},if=sd,format=raw")
  fi

  if [[ -n "$SHIM" ]]; then
    boot=(-kernel "$SHIM" -device "loader,file=${img},addr=${LOAD_ADDR}")
  else
    boot=(-kernel "$img")
  fi

  timeout "$tmo" "$QEMU" "${MACHINE[@]}" -nographic -serial none \
      -semihosting-config enable=on,target=native "${drive[@]}" "${boot[@]}" \
      > "$log" 2>&1
  rc=$?

  if grep -q 'RESULT: PASS' "$log"; then
    echo "PASS"; pass=$((pass+1)); results+=("$app PASS")
  elif grep -q 'RESULT: SKIP' "$log"; then
    # A test can decide it has nothing to do here -- usb_test needs USB device
    # mode, which QEMU does not emulate. Not a failure; the predecessor suite
    # recorded these as SKIP too.
    echo "SKIP  ($(sed -n 's/.*RESULT: SKIP *//p' "$log" | head -1))"
    skip=$((skip+1)); results+=("$app SKIP")
  elif grep -q 'RESULT: FAIL' "$log"; then
    echo "FAIL  (see $log)"; fail=$((fail+1)); results+=("$app FAIL")
  elif [[ $rc -eq 124 ]]; then
    echo "TIMEOUT after ${tmo}s  (see $log)"; fail=$((fail+1)); results+=("$app TIMEOUT")
  else
    echo "NO RESULT (rc=$rc)  (see $log)"; fail=$((fail+1)); results+=("$app NO-RESULT")
  fi
done

echo
echo "qemu suite: ${pass} passed, ${skip} skipped, ${fail} failed"
[[ $fail -eq 0 ]]
