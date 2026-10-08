#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run-host.sh <build-test-dir>
#
# Runs every *-host image in a build directory and reports PASS/FAIL from the
# RESULT line each test prints.
#
# The sibling of run-qemu.sh, and deliberately the same script with the
# emulator taken out: same timeout table, same log directory, same PASS/SKIP/
# FAIL/TIMEOUT/NO-RESULT verdicts, same summary line and same exit status. A
# native test IS the process, so there is no machine to describe and no image
# to load -- the build directory is the only argument.
#
#   test_smpl/run-host.sh build/test
#
# Env:
#   UOS_RUN_ONLY=<app>   run just that one test, and echo it to this terminal
#                        as well as to its log (the same rule run-qemu.sh uses)
# -----------------------------------------------------------------------------
set -uo pipefail

BUILD_DIR="${1:?usage: run-host.sh <build-test-dir>}"

timeout_for () {
  case "$1" in
    smp_test0|smp_test1|smp_test3|smp_test4) echo 150 ;;
    smp_test2)                               echo 300 ;;
    smp-mat-test)                            echo 900 ;;
    smp-mat-sdcard-test)                     echo 2000 ;;
    smp-num-test|smp-pipeline-test|smp-pro-cons-test) echo 1000 ;;
    sd_test)                                 echo 450 ;;
    *)                                       echo 300 ;;
  esac
}

# The tests that talk to an SD card get one: a file, which is what the host
# back-end (micro-os-plus-iii-devices/soc/native) presents as a card. One per
# test, under the log directory, so runs do not share a volume and a failed
# run can be examined afterwards. The back-end creates and grows the file
# itself, so there is nothing to pre-seed for these two; a test that wanted a
# populated volume would seed it here, as run-qemu.sh does for sd_test.
sd_image_for () {
  local app="$1"
  case "$app" in
    smp-num-test|smp-pipeline-test|smp-mat-sdcard-test|sd_test|flatfs-test)
      echo "${LOGS}/${app}.disk.img" ;;
    *)
      return 1 ;;
  esac
}

LOGS="${BUILD_DIR}/.host-logs"; mkdir -p "$LOGS"
pass=0; fail=0; skip=0; declare -a results=()

ONLY="${UOS_RUN_ONLY:-}"

for exe in "${BUILD_DIR}"/*-host; do
  [[ -x "$exe" ]] || { echo "no *-host executables in ${BUILD_DIR}"; exit 2; }
  app="$(basename "$exe" -host)"
  if [[ -n "$ONLY" && "$app" != "$ONLY" ]]; then
    continue
  fi
  tmo="$(timeout_for "$app")"
  log="${LOGS}/${app}.log"

  printf '%-24s ' "$app"

  env=()
  if sd="$(sd_image_for "$app")"; then
    env=(UOS_SD_IMAGE="$sd")
  fi

  if [[ -n "$ONLY" ]]; then
    echo
    # A pipeline, not `> >(tee ...)`: a process substitution runs
    # asynchronously, so a short test's RESULT line could still be on its way
    # to the log when it is read below (NO RESULT).
    timeout "$tmo" /usr/bin/env "${env[@]}" "$exe" 2>&1 | tee "$log"
    rc=${PIPESTATUS[0]}
  else
    timeout "$tmo" /usr/bin/env "${env[@]}" "$exe" > "$log" 2>&1
    rc=$?
  fi

  if grep -q 'RESULT: PASS' "$log"; then
    echo "PASS"; pass=$((pass+1)); results+=("$app PASS")
  elif grep -q 'RESULT: SKIP' "$log"; then
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
echo "host suite: ${pass} passed, ${skip} skipped, ${fail} failed"
if [[ -n "$ONLY" && $((pass + skip + fail)) -eq 0 ]]; then
  echo "ERROR: requested test '${ONLY}' was not found in ${BUILD_DIR}"
  exit 2
fi
if [[ $((pass + skip + fail)) -eq 0 ]]; then
  echo "ERROR: no tests were executed in ${BUILD_DIR}"
  exit 2
fi
[[ $fail -eq 0 ]]
