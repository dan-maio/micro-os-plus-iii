#!/usr/bin/env bash
# scripts/smp/show-chunk.sh NN file [file...] — show the smp-vs-baseline diff for
# the given kernel files, so you can lift the cohesive chunk for step NN.
#
# The single-core baseline and the SMP source are two branches of the same repo,
# so the diff is simply: origin/xpack-development .. smp  (limited to <file>s).
source "$(dirname "$0")/common.sh"

NN="$(step_label "${1:?usage: show-chunk.sh NN file [file...]}")"; shift
[ "$#" -ge 1 ] || die "give at least one file path"

cd "$K"
git fetch origin "$SMP_BRANCH" "$BASE_BRANCH" >/dev/null 2>&1 || true

for f in "$@"; do
  echo "======================================================================"
  echo " step $NN : $f    ($UPSTREAM .. origin/$SMP_BRANCH)"
  echo "======================================================================"
  git diff "$UPSTREAM" "origin/$SMP_BRANCH" -- "$f" || warn "no diff / missing: $f"
  echo
done
