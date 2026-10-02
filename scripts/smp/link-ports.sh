#!/usr/bin/env bash
# scripts/smp/link-ports.sh [NN] — dev-link ONLY the ports the step modifies.
#
# Kernel-only steps (most of Part A/B) need no local port linking: the tests
# build the local kernel directly and pull the released posix-arch/cortexm from
# each config's installed xpacks/. Dev-linking a port is needed only when the
# step changes that port (steps that include P and/or C in step_repos).
#
# Uses the explicit per-config loop, never `xpm run link-deps-all` (upstream's
# tests/package.json duplicates native-cmake-gcc13-debug and omits gcc14-debug).
source "$(dirname "$0")/common.sh"

NN="${1:-}"
repos="$( [ -n "$NN" ] && step_repos "$NN" || echo "$K $P $C $A32 $A64" )"

want_p=0; want_c=0; want_a32=0; want_a64=0
printf '%s\n' $repos | grep -qx "$P" && want_p=1
printf '%s\n' $repos | grep -qx "$C" && want_c=1
printf '%s\n' $repos | grep -qx "$A32" && want_a32=1
printf '%s\n' $repos | grep -qx "$A64" && want_a64=1

if [ "$want_p" -eq 0 ] && [ "$want_c" -eq 0 ] && [ "$want_a32" -eq 0 ] && [ "$want_a64" -eq 0 ]; then
  ok "kernel-only step — no local port linking needed (uses installed ports)"
  exit 0
fi

# Dev-link each modified port, installing its own deps first so the transitive
# chain resolves.
if [ "$want_p" -eq 1 ]; then ( cd "$P" && xpm install && xpm link ); ok "posix-arch dev-linked"; fi
if [ "$want_c" -eq 1 ]; then ( cd "$C" && xpm install && xpm link ); ok "cortexm dev-linked"; fi
if [ "$want_a32" -eq 1 ]; then ( cd "$A32" && xpm install && xpm link ); ok "aarch32 dev-linked"; fi
if [ "$want_a64" -eq 1 ]; then ( cd "$A64" && xpm install && xpm link ); ok "aarch64 dev-linked"; fi

log "binding local port(s) across configurations"
cd "$K/tests"
for c in "${CONFIGS[@]}"; do
  for t in debug release; do
    xpm run link-deps --config "${c}-${t}" >/dev/null 2>&1 \
      || warn "link-deps ${c}-${t} skipped"
  done
done
for aarch_cfg in aarch32-rpi-zero-2w-cmake-gcc-debug aarch32-rpi-zero-2w-cmake-gcc-release \
                 aarch32-rpi3b-cmake-gcc-debug aarch32-rpi3b-cmake-gcc-release \
                 aarch64-rpi-zero-2w-cmake-gcc-debug aarch64-rpi-zero-2w-cmake-gcc-release \
                 aarch64-rpi3b-cmake-gcc-debug aarch64-rpi3b-cmake-gcc-release; do
  xpm run link-deps --config "$aarch_cfg" >/dev/null 2>&1 || true
done
ok "local port(s) linked"
