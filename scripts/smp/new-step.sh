#!/usr/bin/env bash
# scripts/smp/new-step.sh NN — create step/NN branches in every repo it touches.
#
# Base of step/NN, per repo (kernel, cortexm, posix-arch all have an
# xpack-development branch we integrate INTO):
#   - step/NN-1 if it already exists in that repo (chained, bisectable), else
#   - origin/xpack-development — that repo's integration baseline.
#
# NOTE: the port release *tags* (posix-arch v1.0.1 / cortexm v1.1.0) are NOT the
# integration base — each port's xpack-development HEAD is ahead of its last
# release tag, and that branch is what smp is integrated into. The tags are only
# read/created at Step 24 (release-port.sh cuts the new v1.1.0 / v1.2.0). The
# new architecture ports (aarch32/aarch64) are add-only in Part C and take no
# per-step branch here.
source "$(dirname "$0")/common.sh"

NN="$(step_label "${1:?usage: new-step.sh NN}")"

for repo in $(step_repos "$NN"); do
  cd "$repo"
  git fetch origin "$BASE_BRANCH" >/dev/null 2>&1 || true

  # Base step/NN on the MOST RECENT existing step branch below NN (not just
  # NN-1): Part B is collapsed into step/14, so steps 15-23 never exist and
  # step/24 must chain onto step/14, not fall back to the baseline (which would
  # silently drop all of Part B). Search downward, then baseline as last resort.
  base="$UPSTREAM"          # origin/xpack-development in every repo
  for (( m = 10#$NN - 1; m >= 1; m-- )); do
    cand="step/$(step_label "$m")"
    if git rev-parse --verify --quiet "$cand" >/dev/null; then
      base="$cand"; break
    fi
  done

  git switch -c "step/$NN" "$base" 2>/dev/null || git switch "step/$NN"
  ok "$(basename "$repo"): step/$NN  <-  $base"
done

echo
echo "Review the chunk to apply (files listed in runbook §4-§7). For example:"
echo "  scripts/smp/show-chunk.sh $NN <file> [file...]"
