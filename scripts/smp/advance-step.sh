#!/usr/bin/env bash
# scripts/smp/advance-step.sh NN ["message"] — commit each touched repo and tag
# the green point. Run ONLY after verify-step.sh NN exits 0.
source "$(dirname "$0")/common.sh"

NN="$(step_label "${1:?usage: advance-step.sh NN [message]}")"
MSG="${2:-step $NN}"

# Refuse to commit a step that touched the frozen test framework.
bash "$(dirname "$0")/check-pristine.sh" "$NN" \
  || die "not committing — fix the pristine violations above first"

for repo in $(step_repos "$NN"); do
  cd "$repo"
  git add -A
  if git diff --cached --quiet; then
    warn "$(basename "$repo"): nothing to commit"
  else
    git commit -m "smp-step($NN): $MSG"
  fi
  git tag -f "step-$NN-green" >/dev/null
  ok "$(basename "$repo"): committed + tagged step-$NN-green"
done

echo "Next: scripts/smp/new-step.sh $(( 10#$NN + 1 ))"
