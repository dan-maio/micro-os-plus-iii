#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run-qemu.sh <build-test-dir> <qemu-binary> <machine-args...>
#
# Runs every *-qemu image in a build directory and reports PASS/FAIL from the
# RESULT line each test prints. Architecture-neutral: the caller supplies the
# QEMU binary and the machine flags, which are the only parts that differ
# between ports.
#
#   test/run-qemu.sh build/test "$(…)/qemu-system-aarch64" -M raspi3b -smp 4
#
# The per-test timeouts are the ones the predecessor repository's
# run_one_test.sh used; they are wall-clock budgets, not expected durations.
# -----------------------------------------------------------------------------
set -uo pipefail

BUILD_DIR="${1:?usage: run-qemu.sh <build-test-dir> <qemu> <machine-args...>}"
QEMU="${2:?usage: run-qemu.sh <build-test-dir> <qemu> <machine-args...>}"
shift 2
MACHINE=("$@")

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

LOGS="${BUILD_DIR}/.qemu-logs"; mkdir -p "$LOGS"
pass=0; fail=0; declare -a results=()

for img in "${BUILD_DIR}"/*-qemu.bin; do
  [[ -e "$img" ]] || { echo "no *-qemu.bin in ${BUILD_DIR}"; exit 2; }
  app="$(basename "$img" -qemu.bin)"
  tmo="$(timeout_for "$app")"
  log="${LOGS}/${app}.log"

  printf '%-24s ' "$app"
  timeout "$tmo" "$QEMU" "${MACHINE[@]}" -nographic -serial none \
      -semihosting-config enable=on,target=native -kernel "$img" \
      > "$log" 2>&1
  rc=$?

  if grep -q 'RESULT: PASS' "$log"; then
    echo "PASS"; pass=$((pass+1)); results+=("$app PASS")
  elif grep -q 'RESULT: FAIL' "$log"; then
    echo "FAIL  (see $log)"; fail=$((fail+1)); results+=("$app FAIL")
  elif [[ $rc -eq 124 ]]; then
    echo "TIMEOUT after ${tmo}s  (see $log)"; fail=$((fail+1)); results+=("$app TIMEOUT")
  else
    echo "NO RESULT (rc=$rc)  (see $log)"; fail=$((fail+1)); results+=("$app NO-RESULT")
  fi
done

echo
echo "qemu suite: ${pass} passed, ${fail} failed"
[[ $fail -eq 0 ]]
