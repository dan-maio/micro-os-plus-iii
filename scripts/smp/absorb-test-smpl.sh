#!/usr/bin/env bash
# scripts/smp/absorb-test-smpl.sh — dissolve the smp branch's root `test_smpl/`
# into the kernel's `tests/smp-support/`, then ensure no root `test_smpl/`
# survives. Part of Step 27 (new test sources): `test_smpl/` is an smp-branch
# root directory that does NOT exist on xpack-development, so lifting it verbatim
# would plant a non-upstream top-level folder. Its contents are shared SMP test
# scaffolding, so they belong under `tests/`, next to `tests/sources` and
# `tests/platforms`.
#
# Reproducible and idempotent: every file is lifted fresh from `origin/smp`, the
# two target locations are wiped first, and the recipe fails loudly if an anchor
# it rewrites has moved or if any `test_smpl` reference survives.
#
#   kernel   test_smpl/{include,src,run-*.sh,no-power-cycle} -> tests/smp-support/
#   aarch32  test/boards/rpi-zero-2w/{qemu,hw}.sh  -> run via kernel tests/smp-support
#   aarch64  test/boards/rpi-zero-2w/{qemu,hw}.sh  -> run via kernel tests/smp-support
#
# LOCAL only; stages with `git add`, never commits or pushes.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/common.sh"                 # K, P, WORK, SMP_BRANCH
A32="${A32:-$WORK/micro-os-plus-iii-aarch32}"
A64="${A64:-$WORK/micro-os-plus-iii-aarch64}"
SMP="${SMP_BRANCH:-smp}"
DST="tests/smp-support"

say () { printf '\033[1;36m[absorb]\033[0m %s\n' "$*"; }
die () { printf '\033[1;31m[absorb] %s\033[0m\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------------------- #
# 1) Kernel: materialise test_smpl/ from origin/smp, relocate into smp-support.
# --------------------------------------------------------------------------- #
say "kernel: lifting test_smpl/ from origin/$SMP"
git -C "$K" rev-parse --verify -q "origin/$SMP:test_smpl" >/dev/null \
  || die "origin/$SMP has no test_smpl/ in the kernel"

# Clean slate for the two paths this script owns, then re-materialise.
git -C "$K" rm -r -q --cached --ignore-unmatch test_smpl "$DST" >/dev/null 2>&1 || true
rm -rf "$K/test_smpl" "$K/$DST"
git -C "$K" checkout "origin/$SMP" -- test_smpl

mkdir -p "$K/$DST/include" "$K/$DST/src" "$K/$DST/no-power-cycle"
git -C "$K" mv test_smpl/include/hw_result.hpp        "$DST/include/hw_result.hpp"
git -C "$K" mv test_smpl/src/board-contract.cpp       "$DST/src/board-contract.cpp"
git -C "$K" mv test_smpl/run-qemu.sh                   "$DST/run-qemu.sh"
git -C "$K" mv test_smpl/run-host.sh                   "$DST/run-host.sh"
git -C "$K" mv test_smpl/run-hw.sh                     "$DST/run-hw.sh"
git -C "$K" mv test_smpl/no-power-cycle/run-hw-simple.sh        "$DST/no-power-cycle/run-hw-simple.sh"
git -C "$K" mv test_smpl/no-power-cycle/openocd-rpi-zero-2w.cfg "$DST/no-power-cycle/openocd-rpi-zero-2w.cfg"
git -C "$K" mv test_smpl/no-power-cycle/openocd-olimex-rpi3.cfg "$DST/no-power-cycle/openocd-olimex-rpi3.cfg"
# The now-empty root directory must not survive.
rm -rf "$K/test_smpl"
[ -e "$K/test_smpl" ] && die "kernel: root test_smpl/ still present after move"

# Fix the self-referential usage examples inside the relocated files.
say "kernel: rewriting in-file path references"
python3 - "$HERE/chunks" "$K/$DST" <<'PY'
import sys; sys.path.insert(0, sys.argv[1] + "/..")
sys.path.insert(0, sys.argv[1])
from _edit import edit, replace_n
d = sys.argv[2]
edit(d + "/run-qemu.sh", lambda s: replace_n(s, "test_smpl/run-qemu.sh", "tests/smp-support/run-qemu.sh", "run-qemu usage", 2))
edit(d + "/run-host.sh", lambda s: replace_n(s, "test_smpl/run-host.sh", "tests/smp-support/run-host.sh", "run-host usage", 1))
edit(d + "/no-power-cycle/run-hw-simple.sh",
     lambda s: replace_n(s, "./test_smpl/run-hw-simple.sh", "./tests/smp-support/no-power-cycle/run-hw-simple.sh", "run-hw-simple usage", 1))
edit(d + "/no-power-cycle/openocd-rpi-zero-2w.cfg",
     lambda s: replace_n(s, "test_smpl/openocd-rpi-zero-2w.cfg", "tests/smp-support/no-power-cycle/openocd-rpi-zero-2w.cfg", "openocd rpi-zero usage", 2))
edit(d + "/no-power-cycle/openocd-olimex-rpi3.cfg",
     lambda s: replace_n(s, "test_smpl/no-power-cycle/openocd-olimex-rpi3.cfg", "tests/smp-support/no-power-cycle/openocd-olimex-rpi3.cfg", "openocd olimex usage", 2))
print("[absorb] kernel in-file references rewritten")
PY
git -C "$K" add "$DST"

# --------------------------------------------------------------------------- #
# 2) aarch32 / aarch64 ports: the board run-wrappers exec the shared runner.
#    On the smp branch they point at a standalone sibling
#    (micro-os-plus-iii-smp/test_smpl/run-*.sh); in the integrated workspace the
#    runner lives in the KERNEL (sibling micro-os-plus-iii/tests/smp-support).
# --------------------------------------------------------------------------- #
repoint_port () {               # repoint_port <repo-dir> <label>
  local R="$1" lbl="$2"
  local rel="test/boards/rpi-zero-2w"
  [ -d "$R/.git" ] || [ -f "$R/.git" ] || die "$lbl: not a git repo at $R"
  say "$lbl: lifting $rel/{qemu,hw}.sh from origin/$SMP and repointing"
  git -C "$R" checkout "origin/$SMP" -- "$rel/qemu.sh" "$rel/hw.sh"
  python3 - "$HERE/chunks" "$R/$rel" <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
from _edit import edit, replace_n, sub_re_n
d = sys.argv[2]
OLD_DIR = 'SMP_DIR="${UOS_SMP_DIR:-$(cd "$ROOT/.." && pwd)/micro-os-plus-iii-smp}"'
NEW_DIR = 'RUN_DIR="${UOS_SMP_SUPPORT_DIR:-$(cd "$ROOT/.." && pwd)/micro-os-plus-iii/tests/smp-support}"'
OLD_FB  = '[ -d "$SMP_DIR" ] || SMP_DIR="$SMP_DIR.git"'
NEW_FB  = '[ -d "$RUN_DIR" ] || RUN_DIR="$(cd "$ROOT/.." && pwd)/micro-os-plus-iii.git/tests/smp-support"'
for base, runner in (("qemu.sh", "run-qemu.sh"), ("hw.sh", "run-hw.sh")):
    p = d + "/" + base
    def fn(s, runner=runner):
        s = replace_n(s, OLD_DIR, NEW_DIR, base + " SMP_DIR", 1)
        s = replace_n(s, OLD_FB,  NEW_FB,  base + " fallback", 1)
        s = replace_n(s, '"$SMP_DIR/test_smpl/' + runner + '"',
                          '"$RUN_DIR/' + runner + '"', base + " exec", 1)
        # Comment references (vary slightly between the two ports): fold any
        # remaining sibling/root form to the kernel path, then forbid residue.
        s = s.replace("micro-os-plus-iii-smp/test_smpl/", "micro-os-plus-iii/tests/smp-support/")
        s = s.replace("test_smpl/", "tests/smp-support/")
        assert "test_smpl" not in s, base + ": test_smpl reference survived"
        assert "$SMP_DIR" not in s, base + ": $SMP_DIR reference survived"
        return s
    edit(p, fn)
print("[absorb] %s board wrappers repointed" % d)
PY
  git -C "$R" add "$rel/qemu.sh" "$rel/hw.sh"
}
repoint_port "$A32" "aarch32"
repoint_port "$A64" "aarch64"

# --------------------------------------------------------------------------- #
# 3) Fail-loud final gate.
# --------------------------------------------------------------------------- #
say "verifying no test_smpl references remain in code"
for p in "$K/$DST/include/hw_result.hpp" "$K/$DST/src/board-contract.cpp" \
         "$K/$DST/run-qemu.sh" "$K/$DST/run-host.sh" "$K/$DST/run-hw.sh" \
         "$K/$DST/no-power-cycle/run-hw-simple.sh" \
         "$K/$DST/no-power-cycle/openocd-rpi-zero-2w.cfg" \
         "$K/$DST/no-power-cycle/openocd-olimex-rpi3.cfg"; do
  [ -f "$p" ] || die "missing expected file: $p"
done
if grep -rqI 'test_smpl' "$K/$DST" "$A32/test/boards/rpi-zero-2w" "$A64/test/boards/rpi-zero-2w"; then
  grep -rnI 'test_smpl' "$K/$DST" "$A32/test/boards/rpi-zero-2w" "$A64/test/boards/rpi-zero-2w" >&2
  die "a test_smpl reference survived"
fi
say "done — test_smpl absorbed into $DST; root test_smpl/ removed; ports repointed"
