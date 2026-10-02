#!/usr/bin/env bash
# scripts/smp/bootstrap.sh — run from an EMPTY workspace folder; clone all repos.
#
#   mkdir -p ~/smp-integration && cd ~/smp-integration
#   export WORK="$PWD"
#   bash /path/to/bootstrap.sh
#
# Each repo is cloned once from github.com/dan-maio. Both the single-core
# baseline (xpack-development) and the SMP source (smp) are branches of that same
# clone, so no second remote is needed.

set -euo pipefail

# Resolve config; if common.sh is beside this script, use it, else inline defaults.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SELF_DIR/common.sh" ]; then source "$SELF_DIR/common.sh"; else
  WORK="${WORK:-$PWD}"; GH_ORG="dan-maio"; GH_BASE="https://github.com/${GH_ORG}"
  BASE_BRANCH="xpack-development"; SMP_BRANCH="smp"
  ok(){ printf '[+] %s\n' "$*"; }
fi

clone_repo() {                       # clone_repo <name>
  local name="$1"
  local dir="$WORK/$name"
  if [ ! -d "$dir/.git" ]; then
    git clone "$GH_BASE/$name.git" "$dir"
  fi
  cd "$dir"
  git remote set-url origin "$GH_BASE/$name.git"
  git fetch --tags origin
  # Make both branches available as local tracking branches.
  git switch -C "$BASE_BRANCH" "origin/$BASE_BRANCH" 2>/dev/null || git switch "$BASE_BRANCH"
  git branch --track "$SMP_BRANCH" "origin/$SMP_BRANCH" 2>/dev/null || true
  ok "$name ready (branches: $BASE_BRANCH + $SMP_BRANCH)"
}

# Kernel + the two ports needed for Parts A/B. Part-C repos are cloned lazily
# at Step 24 (see runbook §10.5), or add them here if you prefer.
clone_repo micro-os-plus-iii
clone_repo micro-os-plus-iii-posix-arch
clone_repo micro-os-plus-iii-cortexm

# Ensure the dev tooling is present and executable in the kernel clone.
chmod +x "$WORK/micro-os-plus-iii/scripts/smp/"*.sh 2>/dev/null || true

# Install xpm dependencies for the test harness.
if command -v xpm >/dev/null 2>&1; then
  ( cd "$WORK/micro-os-plus-iii/tests" && xpm install )
  ok "xpm dependencies installed"
else
  printf '[!] xpm not found — install it, then run: (cd %s/tests && xpm install)\n' \
    "$WORK/micro-os-plus-iii"
fi

ok "bootstrap complete — WORK=$WORK"
echo "Next: export WORK=$WORK ; cd \$WORK/micro-os-plus-iii ; scripts/smp/new-step.sh 1"
