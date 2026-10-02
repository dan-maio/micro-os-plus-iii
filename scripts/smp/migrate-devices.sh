#!/usr/bin/env bash
# scripts/smp/migrate-devices.sh — Part 0: dissolve micro-os-plus-iii-devices
# into the architecture repos, preserving git history via `git subtree split`.
#
# Upstream xpack-development has no `devices` repo; the SMP branch added it as a
# 7th component. Rather than force a new cross-repo dependency upstream, its two
# kinds of content are folded into the repos that already own them:
#   * arch-neutral drivers (include/ src/ fatfs/) -> each consuming arch repo's drivers/
#   * per-SoC silicon (soc/<soc>/)               -> the one arch repo that owns it
# CMake target names (micro-os-plus::devices, ::soc-bcm2837, …) are preserved by
# ALIASes in the destination, so no consumer changes.
#
# Idempotent-ish: re-running skips a destination that already exists.
# LOCAL ONLY — never pushes.
source "$(dirname "$0")/common.sh"

DEV="$WORK/micro-os-plus-iii-devices"
A32="$WORK/micro-os-plus-iii-aarch32"
A64="$WORK/micro-os-plus-iii-aarch64"
[ -d "$DEV/.git" ] || die "missing $DEV — clone it first"

# split <subdir> -> prints a branch name in $DEV holding that subdir's history.
split() {
  local sub="$1" br="split/${1//\//_}"
  git -C "$DEV" rev-parse --verify --quiet "$br" >/dev/null \
    || git -C "$DEV" subtree split -P "$sub" -b "$br" >/dev/null
  echo "$br"
}

# graft <dest-repo> <subdir> <dest-prefix>
graft() {
  local repo="$1" sub="$2" prefix="$3"
  [ -d "$repo/.git" ] || { warn "skip: $repo not cloned"; return; }
  if [ -e "$repo/$prefix" ]; then warn "$(basename "$repo")/$prefix exists — skip"; return; fi
  local br; br="$(split "$sub")"
  git -C "$repo" subtree add -P "$prefix" "$DEV" "$br" \
    -m "migrate(devices): $sub -> $prefix (history preserved)"
  ok "$(basename "$repo"): $sub -> $prefix"
}

log "arch-neutral drivers -> aarch32, aarch64, posix-arch (drivers/)"
for r in "$A32" "$A64" "$P"; do
  graft "$r" include drivers/include
  graft "$r" src     drivers/src
  graft "$r" fatfs   drivers/fatfs
done

log "per-SoC silicon -> owning arch repo (soc/<soc>/)"
graft "$A32" soc/bcm2837  soc/bcm2837      # RPi3B / Zero 2W (32-bit)
graft "$A64" soc/bcm2837  soc/bcm2837      # RPi3B / Zero 2W (64-bit)
graft "$A32" soc/rk3506   soc/rk3506       # Luckfox Lyra (Cortex-A7)
graft "$P"   soc/native   soc/native       # host image-file SD backend
graft "$C"   soc/rp2350   soc/rp2350       # Pico 2 (headers + system init)
graft "$C"   soc/stm32f4xx soc/stm32f4xx   # STM32F4 boards

# Remove the temporary split/* scaffolding branches from the devices repo. They
# were only carriers for `subtree add`; the history now lives in the arch repos.
# (Pass KEEP_SPLITS=1 to keep them, which makes a re-run instant.)
if [ "${KEEP_SPLITS:-0}" != "1" ]; then
  log "removing temporary split/* branches from $(basename "$DEV")"
  while read -r br; do
    [ -n "$br" ] && git -C "$DEV" branch -D "$br" >/dev/null && echo "    deleted $br"
  done < <(git -C "$DEV" for-each-ref --format='%(refname:short)' 'refs/heads/split/*')
  ok "split branches cleaned"
fi

echo
ok "devices migration complete. Next: add the per-repo CMake shims (runbook Part 0)."
echo "   Verify each arch build still finds micro-os-plus::devices / ::soc-* targets."
