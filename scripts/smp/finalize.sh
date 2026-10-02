#!/usr/bin/env bash
# scripts/smp/finalize.sh — Step 30: reconcile every touched repo with the latest
# baseline, drop dev-only tooling and local port links, then run the acceptance
# gate. Fully LOCAL — it never pushes. Publishing is a manual decision you make
# afterwards, by hand.
#
#   FAST=1   run the FAST subset (cortex-m4f + native gcc14 + the SMP platforms)
#            instead of the full 72 + test-smp-all. The dry run uses this; a real
#            acceptance run leaves FAST unset and runs the whole ecosystem gate.
source "$(dirname "$0")/common.sh"

# Metadata that the pristine guard froze for the whole integration; at the final
# merge it must match the baseline exactly (restored only if something drifted).
FROZEN_PATHS=( .github README.md LICENSE )

# 1) Merge latest baseline into step/30 in EVERY repo the integration touched, so
#    the port repos reconcile too (not just the kernel).
for repo in "$K" "$P" "$C"; do
  [ -d "$repo/.git" ] || continue
  cd "$repo"
  git rev-parse --verify --quiet step/30 >/dev/null \
    || die "$(basename "$repo"): step/30 missing — run new-step.sh 30 first"
  git switch step/30 >/dev/null 2>&1
  git fetch origin "$BASE_BRANCH" >/dev/null 2>&1 || true
  log "$(basename "$repo"): merging $UPSTREAM into step/30"
  git merge --no-ff "$UPSTREAM" -m "merge: reconcile with latest $BASE_BRANCH" \
    || die "$(basename "$repo"): merge conflicts — resolve, commit, re-run"

  # 2) Restore any frozen metadata that drifted (normally a no-op: the pristine
  #    guard kept these identical all along, so this just proves it).
  for p in "${FROZEN_PATHS[@]}"; do
    if git cat-file -e "$UPSTREAM:$p" 2>/dev/null; then
      if ! git diff --quiet "$UPSTREAM" -- "$p" 2>/dev/null; then
        warn "$(basename "$repo"): restoring drifted $p from $BASE_BRANCH"
        git checkout "$UPSTREAM" -- "$p" && git add "$p"
      fi
    fi
  done
  git diff --cached --quiet || git commit -m "chore: restore frozen metadata from $BASE_BRANCH"

  # 3) Drop dev-only tooling and local port links. Only the dev-link SYMLINKS in
  #    tests/xpacks are removed — never the installed dependency contents (doing
  #    that would break the very gate we are about to run).
  [ -d scripts/smp ] && { rm -rf scripts/smp; log "$(basename "$repo"): removed scripts/smp"; }
  if [ -d tests/xpacks ]; then
    find tests/xpacks -maxdepth 3 -type l -print -delete 2>/dev/null | sed 's/^/  unlinked /' || true
  fi
done

# 4) Acceptance gate (kernel tests consume the ports).
cd "$K/tests"
if [ "${FAST:-0}" = "1" ]; then
  warn "[gate] FAST subset — cortex-m4f + native gcc14 + SMP platforms (NOT the full 72 + test-smp-all)"
  xpm run test-qemu-cortex-m4f-cmake
  xpm run test-native-cmake-gcc14
  xpm run test-2xcortex-m33-cmake
  xpm run test-native-smp
else
  log "[gate] full ecosystem: test-all (72) + test-smp-all"
  xpm run test-all
  xpm run test-smp-all
fi

ok "ecosystem green on local branch step/30 — integration complete"
echo
echo "Everything above is local. This tooling never pushes. When YOU decide to"
echo "publish, do it by hand, e.g.:  git -C \"$K\" push origin step/30"
