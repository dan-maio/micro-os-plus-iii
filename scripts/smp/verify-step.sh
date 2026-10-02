#!/usr/bin/env bash
# scripts/smp/verify-step.sh NN — full acceptance gate for one step.
#
#   Stage 1 (steps 14-23): unifdef -UOS_USE_SMP_SCHEDULER single-core invariant.
#   Stage 2:               link local ports into all 24 configs.
#   Stage 3:               official 72-test suite (xpm run test-all, -Werror).
#   Stage 4 (step 23):     NCPU=2 host bring-up smoke build.
source "$(dirname "$0")/common.sh"

NN="$(step_label "${1:?usage: verify-step.sh NN}")"
n=$((10#$NN))

# ---- Stage 0: pristine test framework (all steps) ----
log "[0] pristine check — test framework must stay still"
bash "$(dirname "$0")/check-pristine.sh" "$NN"

# ---- Stage 1: single-core invariant (Part B, steps 14-23) ----
# A Part B step must add ONLY code gated by #if defined(OS_USE_SMP_SCHEDULER)
# (or the NCPU>1 gate): its single-core projection must be byte-identical to the
# PREVIOUS step's. We compare against step-(NN-1)-green, not the upstream
# baseline (which would flag all the Part A changes), and project with
# sc-project.py (dependency-free unifdef; no external unifdef needed).
if [ "$n" -ge 14 ] && [ "$n" -le 23 ]; then
  SCP="$(dirname "$0")/sc-project.py"
  PREV_TAG="step-$(step_label "$((n-1))")-green"
  log "[1/3] single-core invariant (sc-project: $PREV_TAG vs HEAD)"
  cd "$K"; bad=0
  git rev-parse --verify --quiet "$PREV_TAG" >/dev/null \
    || die "missing $PREV_TAG — cannot check the single-core invariant"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    git show "$PREV_TAG:$f" 2>/dev/null | python3 "$SCP" >/tmp/smp_o 2>/dev/null || : >/tmp/smp_o
    git show "HEAD:$f"      2>/dev/null | python3 "$SCP" >/tmp/smp_n 2>/dev/null || : >/tmp/smp_n
    if ! diff -B -u /tmp/smp_o /tmp/smp_n >/tmp/smp_d 2>&1; then   # -B: tolerate blank-line-only diffs
      warn "single-core divergence in $f:"; sed -n '1,40p' /tmp/smp_d; bad=$((bad+1))
    fi
  done < <(git diff --name-only "$PREV_TAG" HEAD -- include/ src/)
  [ "$bad" -eq 0 ] || die "$bad file(s) changed single-core output — edits leaked outside the #if guard"
  ok "zero single-core delta vs $PREV_TAG"
fi

# ---- Stage 2: link local ports (only those this step modifies) ----
log "[2/3] linking local development ports"
bash "$(dirname "$0")/link-ports.sh" "$NN"

# ---- Stage 3: the gate ----
cd "$K/tests"
if [ "${FAST:-0}" = "1" ]; then
  # Fast iteration for kernel/core work: one real TARGET (Cortex-M4F, arm-none-eabi
  # from ./xpacks, run under QEMU) + one HOST config (native gcc14). The Cortex-M
  # build is the representative bare-metal compile (newlib, not glibc — so host
  # libc quirks like glibc-2.44 timegm never arise); the native gcc pass adds the
  # host -Werror coverage the official gate also wants. All xPack-pinned; the
  # machine's own gcc/clang are NOT used (too new for µOS++). debug+release each
  # (4 builds / 12 runs). NOT an acceptance run.
  warn "[3/3] FAST mode — cortex-m4f (arm-none-eabi) + native gcc14 (no clang, no other targets; NOT the 72-run gate)"
  xpm run test-qemu-cortex-m4f-cmake
  xpm run test-native-cmake-gcc14
else
  log "[3/3] xpm run test-all (24 builds / 72 runs, -Werror)"
  xpm run test-all
fi

# ---- Stage 4: SMP smoke (step 23 only) ----
if [ "$n" -eq 23 ]; then
  log "[smoke] NCPU=2 host bring-up"
  cd "$K/tests"
  xpm run build --config native-cmake-gcc14-debug \
    -- -DOS_USE_SMP_SCHEDULER=1 -DOS_INTEGER_RTOS_PORT_NCPU=2 \
    || die "NCPU=2 smoke build failed"
  ok "NCPU=2 host bring-up builds"
fi

echo
if [ "${FAST:-0}" = "1" ]; then
  warn "STEP $NN passed FAST subset (cortex-m4f + native gcc14) — re-run without FAST for the 72-run gate before advancing"
else
  ok "STEP $NN PASSED (72/72)"
fi
