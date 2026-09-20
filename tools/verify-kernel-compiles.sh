#!/usr/bin/env bash
# Gate for migration step 1: every source that micro-os-plus::iii declares must
# compile.
#
# The kernel cannot compile alone -- os-decls.h includes
# <cmsis-plus/rtos/port/os-decls.h>, which an architecture repo supplies. So the
# gate compiles the kernel against a port's include directory, given as $1.
#
# Usage:  tools/verify-kernel-compiles.sh <port-include-dir> [compiler]
# All paths are relative to the repository root.
set -uo pipefail
cd "$(dirname "$0")/.."

PORT_INC="${1:?usage: $0 <port-include-dir> [compiler]}"
CXX="${2:-g++}"
[ -f "$PORT_INC/cmsis-plus/rtos/port/os-decls.h" ] || {
  echo "error: $PORT_INC does not look like a port (no cmsis-plus/rtos/port/os-decls.h)" >&2
  exit 2
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# The authoritative list is the target_sources() block, minus commented lines.
python3 - <<'PY' > "$TMP/srclist"
s = open("micro-os-plus-iii/CMakeLists.txt").read()
blk = s.split("target_sources (", 1)[1].split(")", 1)[0]
for line in blk.splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    for tok in line.split():
        if tok.startswith("src/") and tok.endswith((".cpp", ".c")):
            print(tok)
PY

total=$(wc -l < "$TMP/srclist"); ok=0; failed=""
while read -r f; do
  [ -z "$f" ] && continue
  if "$CXX" -std=c++17 -c -w \
       -Imicro-os-plus-iii/include \
       -Imicro-os-plus-iii/include/cmsis-plus/legacy \
       -I"$PORT_INC" -D_XOPEN_SOURCE=700L \
       -x c++ "micro-os-plus-iii/$f" -o "$TMP/o.o" 2>"$TMP/err"; then
    ok=$((ok+1))
  else
    failed="$failed$f: $(grep -m1 'error:' "$TMP/err" | sed 's/.*error: //')"$'\n'
  fi
done < "$TMP/srclist"

echo "kernel sources declared: $total   compiled: $ok"
if [ -n "$failed" ]; then
  printf 'FAIL\n%s' "$failed" >&2
  exit 1
fi
echo "PASS"
