#!/usr/bin/env bash
# scripts/smp/check-env.sh — verify the toolchain the 72-test gate needs.
source "$(dirname "$0")/common.sh"

miss=0
need() {                              # need <cmd> [pretty-name]
  if command -v "$1" >/dev/null 2>&1; then
    ok "$(printf '%-22s %s' "${2:-$1}" "$(command -v "$1")")"
  else
    warn "MISSING: ${2:-$1}"; miss=$((miss+1))
  fi
}

log "core tooling"
need git; need xpm; need cmake; need ninja; need unifdef; need qemu-system-arm

log "GCC (need 11-14)"
for v in 11 12 13 14; do need "arm-none-eabi-gcc-$v" "gcc-$v (arm)" 2>/dev/null || need "gcc-$v"; done

log "Clang (need 16-19)"
for v in 16 17 18 19; do need "clang-$v"; done

log "docs rendering (either path)"
need typst || true
need python3 || true

if [ "$miss" -gt 0 ]; then
  die "$miss required tool(s) missing — install before running the gate"
fi

# Functional check: presence of xpm is not enough — `xpm link` must actually work
# (it breaks on some Node/xpm combos, e.g. Node 26 + xpm 0.23.2:
#  "TypeError: jsonPackage.isNpmPackage is not a function").
log "xpm link smoke test"
if [ -d "$P/.git" ]; then
  if out="$( cd "$P" && xpm link 2>&1 )"; then
    ok "xpm link works ($(node --version 2>/dev/null), xpm $(xpm --version 2>/dev/null))"
  else
    printf '%s\n' "$out" | sed 's/^/    /'
    die "xpm link FAILED — use a known-good Node (LTS) + xpm ('npm i -g xpm@latest'). See runbook §1.1."
  fi
else
  warn "posix-arch not cloned yet; run the smoke test after bootstrap: (cd \$P && xpm link)"
fi

ok "environment OK"
