#!/usr/bin/env bash
# scripts/smp/run-loop.sh [FROM] [TO] — drive the new -> apply -> verify -> advance
# loop across a range of steps (default 1..30).
#
# Applying the chunk is the one manual action per step. Two modes:
#   interactive (default): pauses for you to edit, then continues on Enter.
#   auto (AUTO=1):         cherry-picks smp-step-NN from the smp history, if you
#                          tagged the fork's per-step commits that way.
source "$(dirname "$0")/common.sh"

FROM="$(step_label "${1:-1}")"
TO="$(step_label "${2:-30}")"
AUTO="${AUTO:-0}"

for n in $(seq "$((10#$FROM))" "$((10#$TO))"); do
  NN="$(step_label "$n")"
  echo
  echo "################################ STEP $NN ################################"

  bash "$(dirname "$0")/new-step.sh" "$NN"

  RECIPE="$(dirname "$0")/chunks/step${NN}.sh"
  if [ -f "$RECIPE" ]; then
    # A saved chunk recipe reproduces this step's cohesive chunk exactly
    # (whole-file copies + any strip/surgical edit). Preferred over prompting.
    cd "$K"
    ok "applying recipe chunks/step${NN}.sh"
    bash "$RECIPE" || die "chunk recipe step${NN} failed"
  elif [ "$AUTO" = "1" ]; then
    cd "$K"
    if git rev-parse --verify --quiet "smp-step-$NN" >/dev/null; then
      git cherry-pick -n "smp-step-$NN" || die "cherry-pick smp-step-$NN failed — resolve manually"
      ok "applied smp-step-$NN (staged)"
    else
      warn "no recipe and no smp-step-$NN tag; falling back to manual apply"
      read -rp "Apply step $NN edits (runbook §4-§7), then press Enter... "
    fi
  else
    echo "Apply the step $NN chunk. Review with:"
    echo "  scripts/smp/show-chunk.sh $NN <file>   (files listed in runbook §4-§7)"
    echo "  (or add scripts/smp/chunks/step${NN}.sh to make it reproducible)"
    read -rp "Applied? press Enter to verify (Ctrl-C to stop)... "
  fi

  if ! bash "$(dirname "$0")/verify-step.sh" "$NN"; then
    die "STEP $NN RED — fix, re-run: scripts/smp/verify-step.sh $NN"
  fi

  bash "$(dirname "$0")/advance-step.sh" "$NN" "runbook step $NN"
done

ok "loop complete: steps $FROM..$TO green"
