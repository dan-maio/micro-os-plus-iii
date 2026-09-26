#!/usr/bin/env bash
# Gate for migration step 1: every source that micro-os-plus::iii declares must
# compile.
#
# The kernel cannot compile alone -- os-decls.h includes
# <cmsis-plus/rtos/port/os-decls.h>, which an architecture repo supplies. So the
# gate compiles the kernel against a port's include directory, given as $1.
# A port whose board overlays one directory on another (cortexm's pico2:
# include-rp2350 before include) gives them as a ':'-separated list, searched
# in that order, the same order the board's build uses.
#
# A bare-metal port needs its own cross compiler (the host's cannot assemble
# its inline asm) and, for a port that refuses to guess them, the board facts
# a board would supply (aarch32: OS_NCPU, OS_SMP_IPI_SGI, PORT_GREETING and a
# -mcpu). They follow the compiler as extra flags. .c sources compile as C,
# .cpp as C++, as the real build does.
#
# --without <group> skips an optional group the port does not link (the
# group is the target_sources() block's library, e.g. `startup` for
# micro-os-plus-iii-startup-interface). Skipped sources are reported, never
# counted as compiled.
#
# Usage:  tools/verify-kernel-compiles.sh [--without <group>]...
#           <port-include-dir>[:<dir>...] [compiler [flags...]]
# All paths are relative to the repository root.
set -uo pipefail
cd "$(dirname "$0")/.."

USAGE="usage: $0 [--without <group>]... <port-include-dir>[:<dir>...] [compiler [flags...]]"
WITHOUT=()
while [ "${1:-}" = "--without" ]; do
  [ -n "${2:-}" ] || { echo "$USAGE" >&2; exit 2; }
  WITHOUT+=("$2"); shift 2
done
PORT_INC="${1:?$USAGE}"; shift
CXX="${1:-g++}"; [ $# -gt 0 ] && shift
EXTRA=("$@")
IFS=: read -ra PORT_DIRS <<< "$PORT_INC"
PORT_FLAGS=(); found=""
for d in "${PORT_DIRS[@]}"; do
  PORT_FLAGS+=("-I$d")
  [ -f "$d/cmsis-plus/rtos/port/os-decls.h" ] && found=1
done
[ -n "$found" ] || {
  echo "error: $PORT_INC does not look like a port (no cmsis-plus/rtos/port/os-decls.h)" >&2
  exit 2
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# The authoritative list is every target_sources() block -- the core target and
# each optional group -- minus commented lines. Each line: <group> <source>.
python3 - <<'PY' > "$TMP/srclist"
s = open("CMakeLists.txt").read()
seen = set()
for chunk in s.split("target_sources (")[1:]:
  blk = chunk.split(")", 1)[0]
  lib = blk.split()[0]
  group = lib[len("micro-os-plus-iii-"):-len("-interface")] or "core"
  for line in blk.splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    for tok in line.split():
        if tok.startswith("src/") and tok.endswith((".cpp", ".c")) and tok not in seen:
            seen.add(tok)
            print(group, tok)
PY

for g in "${WITHOUT[@]}"; do
  grep -q "^$g " "$TMP/srclist" || { echo "error: no group '$g' in CMakeLists.txt" >&2; exit 2; }
done

total=$(wc -l < "$TMP/srclist"); ok=0; skipped=0; failed=""
while read -r g f; do
  [ -z "$f" ] && continue
  for w in "${WITHOUT[@]}"; do
    [ "$g" = "$w" ] && { skipped=$((skipped+1)); continue 2; }
  done
  case "$f" in
    *.c) LANG=(-x c -std=c11) ;;
    *)   LANG=(-x c++ -std=c++17) ;;
  esac
  if "$CXX" "${EXTRA[@]}" -c -w \
       -Iinclude -Iinclude/cmsis-plus/legacy \
       "${PORT_FLAGS[@]}" -D_XOPEN_SOURCE=700L \
       "${LANG[@]}" "$f" -o "$TMP/o.o" 2>"$TMP/err"; then
    ok=$((ok+1))
  else
    # The compiler says `error:`, the assembler `Error:`.
    failed="$failed$f: $(grep -m1 -i 'error:' "$TMP/err" | sed 's/.*[eE]rror: //')"$'\n'
  fi
done < "$TMP/srclist"

echo "kernel sources declared: $total   compiled: $ok   skipped: $skipped${WITHOUT[*]:+ (without ${WITHOUT[*]})}"
if [ -n "$failed" ]; then
  printf 'FAIL\n%s' "$failed" >&2
  exit 1
fi
echo "PASS"
