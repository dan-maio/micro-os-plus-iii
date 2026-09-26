#!/usr/bin/env python3
"""verify-no-duplicate-sources.py - the Section 9 duplicate-source gate.

    tools/verify-no-duplicate-sources.py [-w DIR] [-t 0.85] [--json OUT] [-v]

Reports any two TRACKED source files, anywhere in the workspace, whose content
is identical or near-identical above a threshold (85% by default).

WHY IT SCANS EVERY REPOSITORY TOGETHER.  D9 put the architecture projects in
separate repositories, which is what makes cross-repo duplication possible in
the first place: two ports can grow the same file and neither repository's own
history shows it.  Running a duplicate check one repository at a time would
miss precisely the duplication the layout permits, so this script collects the
tracked files of every sibling repository into one pool and compares across it.

WHAT COUNTS AS A SOURCE FILE.  C and C++ (.c .cc .cpp .cxx .h .hh .hpp .hxx)
and assembly (.s .S).  Not CMake, not shell, not Markdown -- the gate is about
application and port code.

HOW SIMILARITY IS MEASURED.  Files are reduced to their significant lines:
comments and blank lines removed, leading and trailing whitespace stripped.
Two files are then compared with difflib.SequenceMatcher over those lines, and
the ratio is what the threshold applies to.  Reducing first is deliberate --
two copies of one file that differ only in a header comment are the same file
for this gate's purposes, and a diff tool that says otherwise is the reason
this script exists rather than a `diff -q` loop.

Exact duplicates are found first by SHA-256 and never reach the expensive
path.  Near-duplicates are prefiltered by size and by a line-set Jaccard index
before difflib is called, because the pool is thousands of files and the
comparison is quadratic.

THREE OUTCOMES, not two.  A flat pass/fail would be useless here, because this
workspace duplicates some code on purpose and the gate must not pretend
otherwise:

  EXEMPT    never compared at all -- vendored third-party code and upstream's
            own test suite.  Declared in EXEMPT, with a reason each.

  EXPECTED  compared, reported, counted, but does not fail the gate.  One
            rule so far: the same test file carried by two boards.  Every
            board owns its tests -- that is the layout, deliberately, so that
            changing a test reaches exactly one board -- and the copies are
            therefore the design rather than a defect.  The spec's Section 9
            was written before that decision and says "target: zero
            findings"; this is where the two are reconciled, in the open.

  SIBLING   compared, reported, counted, does not fail -- and named
            individually, in SIBLINGS below, with a reason each.  These are
            not copies of one another: they are two files that resemble each
            other because they do similar jobs, which a text-similarity
            threshold cannot tell apart from a copy.  A C driver and its C++
            sibling.  A polled driver and the interrupt-driven variant a test
            exists to exercise.  Two solver tests whose constants and memory
            strategy differ because the silicon made them differ.

            A SIBLING entry is NOT a blanket pardon.  It is rejected, and the
            gate fails, if the two files ever become IDENTICAL: at that point
            somebody really has copied one onto the other, which is the thing
            this gate is for.  It is also rejected if the pair stops matching
            at all, so that stale entries are noticed rather than accumulating.

  FINDING   everything else.  These fail the gate.

Exit status: 0 if there is no unexplained duplication, 1 otherwise, 2 on a
usage error.  Prints the expected duplication either way, so that it stays
visible and can be argued with.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from difflib import SequenceMatcher
from itertools import combinations

SOURCE_SUFFIXES = {
    ".c", ".cc", ".cpp", ".cxx",
    ".h", ".hh", ".hpp", ".hxx",
    ".s", ".S",
}

# Repositories to scan: every sibling of the kernel matching this prefix.
REPO_PREFIX = "micro-os-plus-iii"

# Repositories never scanned, with the reason.
SKIP_REPOS = {
    "micro-os-plus-iii-smp-old":
        "the read-only migration source; it is the thing being replaced",
    "backup":
        "not a project repository",
}

# Paths, relative to a repository root, whose duplication is intended.
# Each entry is (repo-or-None, path prefix, reason).  repo None means any.
EXEMPT = [
    (None, "tests/",
     "upstream's own test suite, carried as shipped (spec Section 10)"),
    (None, "xpacks/",
     "vendored third-party sources"),
    (None, "test/boards/pico2/usb/tinyusb/",
     "vendored TinyUSB core"),
    ("micro-os-plus-iii-devices", "soc/rp2350/include/cmsis/",
     "ARM's own CMSIS core headers, vendored per SoC"),
    ("micro-os-plus-iii-devices", "soc/stm32f4xx/include/cmsis/",
     "ARM's own CMSIS core headers, vendored per SoC"),
]


def board_neutral(rel):
    """A test path with its board component removed, or None if not a test.

    test/boards/<board>/rest  ->  ("boards", rest)
    test/<board>/rest         ->  ("tests",  rest)

    Two paths that reduce to the same pair are the same file carried by two
    different boards, which is what the layout asks for.
    """
    parts = rel.split("/")
    if len(parts) < 3 or parts[0] != "test":
        return None
    if parts[1] == "boards":
        if len(parts) < 4:
            return None
        return ("boards", "/".join(parts[3:]))
    return ("tests", "/".join(parts[2:]))


# Pairs that look alike because they do similar jobs. Order within a pair does
# not matter. Each entry: (path_a, path_b, reason).
#
# Adding to this list is a claim, and the claim is checkable: the gate rejects
# an entry whose two files have become identical. If you are tempted to add a
# pair because removing the duplication is awkward, that is a FINDING, not a
# SIBLING -- leave it failing and say why in docs/STATUS.md instead.
SIBLINGS = [
    ("micro-os-plus-iii-devices/fatfs/ff.c",
     "micro-os-plus-iii-aarch32/test/boards/luckfox-lyra/fatfs-cpp/ff.cpp",
     "the same FatFs, C and C++: one is upstream's ff.c compiled as C, the "
     "other the C++ translation the Lyra's C++ disk glue needs"),

    ("micro-os-plus-iii-devices/soc/rk3506/include/sdmmc.hpp",
     "micro-os-plus-iii-aarch32/test/luckfox-lyra/smp_test_int4/sd/sdmmc.hpp",
     "polled driver vs the interrupt-driven variant smp_test_int4 exists to "
     "exercise; merging them would delete the thing under test"),
    ("micro-os-plus-iii-devices/soc/rk3506/src/sdmmc.cpp",
     "micro-os-plus-iii-aarch32/test/luckfox-lyra/smp_test_int4/sd/sdmmc.cpp",
     "as above, the implementation half"),

    ("micro-os-plus-iii-cortexm/test/pico2-rp2350b-psram/smp-test-nested-clock/main.cpp",
     "micro-os-plus-iii-cortexm/test/pico2-rp2350b-psram/smp-test-nested-clock_200/main.cpp",
     "different N and B, and one working matrix vs two: N=500 aliased onto "
     "low memory on 2 MB of PSRAM and corrupted the heap, and the comments "
     "record that measurement"),
    ("micro-os-plus-iii-cortexm/test/pico2-rp2350b-psram/smp-test-nested-clock/main.cpp",
     "micro-os-plus-iii-cortexm/test/pico2-rp2350b-psram/smp-test-nested-clock_250/main.cpp",
     "as above"),
    ("micro-os-plus-iii-cortexm/test/pico2-rp2350b-psram/smp-test-nested-clock_200/main.cpp",
     "micro-os-plus-iii-cortexm/test/pico2-rp2350b-psram/smp-test-nested-clock_250/main.cpp",
     "as above"),

    ("micro-os-plus-iii-cortexm/test/pico2-pizero/sc-test-ko/main.cpp",
     "micro-os-plus-iii-cortexm/test/pico2-pizero/smp-test-ko/main.cpp",
     "the same kernel-object suite run single-core and SMP; sc-test-ko is the "
     "only test on this silicon exercising the kernel's non-SMP branch"),

    ("micro-os-plus-iii-cortexm/include-m33/cmsis-plus/rtos/port/os-decls.h",
     "micro-os-plus-iii-cortexm/include/cmsis-plus/rtos/port/os-decls.h",
     "two lock contracts: the generic M33's kernel lock is an LDREX/STREX word "
     "with a saved PRIMASK per core; include/'s, which the RP2350 shares, is "
     "owner/depth only, the exclusion being PRIMASK or SIO spinlock 0"),
    ("micro-os-plus-iii-cortexm/include-m33/cmsis-plus/rtos/port/os-c-decls.h",
     "micro-os-plus-iii-cortexm/include-rp2350/cmsis-plus/rtos/port/os-c-decls.h",
     "as above, the C half"),

    ("micro-os-plus-iii-cortexm/test/boards/pico2/include/bsp/uart.hpp",
     "micro-os-plus-iii-cortexm/test/boards/pico2/qemu/include/bsp/uart.hpp",
     "one console API, two back-ends: the PL011 on silicon, semihosting on "
     "QEMU's generic machine, so the tests compile unchanged for both"),

    ("micro-os-plus-iii-cortexm/test/pico2-pizero/psram-mat-test-250/main.cpp",
     "micro-os-plus-iii-cortexm/test/pico2-pizero/smp-mat-test/main.cpp",
     "the solver with its matrices in PSRAM: N=300/B=50 against 120/30, the "
     "arrays in .psram, and the app bringing the PSRAM up itself at 250 MHz"),
    ("micro-os-plus-iii-cortexm/test/pico2-pizero/psram-mat-test-250/main.cpp",
     "micro-os-plus-iii-cortexm/test/pico2/smp-mat-test/main.cpp",
     "as above, against the Pico 2's all-SRAM solver"),
    ("micro-os-plus-iii-cortexm/test/pico2-pizero/psram-mat-test-250/main.cpp",
     "micro-os-plus-iii-cortexm/test/pico2-rp2350b-psram/smp-mat-test/main.cpp",
     "the same N=300 PSRAM solver on another board: PSRAM chip-select GPIO47 "
     "against GPIO0, and here the app brings the PSRAM up itself "
     "(PICO2_PSRAM_COPY) at 250 MHz"),
    ("micro-os-plus-iii-cortexm/test/pico2-pizero/psram-mat-test-250/main.cpp",
     "micro-os-plus-iii-aarch32/test/luckfox-lyra/smp-mat-test/main.cpp",
     "the same solver on another silicon: three A7 cores and DRAM against two "
     "M33 cores and PSRAM"),
    ("micro-os-plus-iii-cortexm/test/pico2-pizero/psram-mat-test-250/main.cpp",
     "micro-os-plus-iii-posix-arch/test/native/smp-mat-test/main.cpp",
     "the same solver on the host port, host threads for cores"),

    ("micro-os-plus-iii-cortexm/test/boards/pico2/usb/hid/tusb_config.h",
     "micro-os-plus-iii-cortexm/test/boards/pico2/usb/cdc/tusb_config.h",
     "TinyUSB is configured per device class; 26 lines, and the class lines "
     "are the point of the file"),
]


def normalize_repo_name(name: str) -> str:
    """Normalize a repository folder name to its canonical identifier.
    Strips trailing '.git', resolves symlinks, and extracts the folder name.
    """
    if not name:
        return ""
    base = os.path.basename(os.path.realpath(name) if os.path.islink(name) else name)
    if base.endswith(".git"):
        base = base[:-4]
    return base


def normalize_sibling_path(p: str) -> str:
    """Normalize a path so the repo component matches canonical repo names."""
    parts = p.split("/", 1)
    if len(parts) == 2:
        return f"{normalize_repo_name(parts[0])}/{parts[1]}"
    return p


def sibling_reason(full_a, full_b, ratio):
    """A named pair that resembles itself for a stated reason.

    Refused when the two have become identical -- that is a real copy, and
    exactly what this gate is for."""
    norm_pair = {normalize_sibling_path(full_a), normalize_sibling_path(full_b)}
    for a, b, reason in SIBLINGS:
        if norm_pair == {normalize_sibling_path(a), normalize_sibling_path(b)}:
            if ratio >= 1.0:
                return None
            return reason
    return None


def expected_reason(rel_a, rel_b):
    """Duplication this layout asks for. Reported, but not a failure."""
    na, nb = board_neutral(rel_a), board_neutral(rel_b)
    if na is not None and na == nb:
        return "the same test file carried by two boards; every board owns its tests"
    # test/<board>/<test>/host/<file>: a PC program shipped with its test, so
    # each test's host/ folder builds on its own (smp_test_int3 and
    # smp_test_int4 both forward the keyboard).
    pa, pb = rel_a.split("/"), rel_b.split("/")
    if (len(pa) == 5 and len(pb) == 5 and pa[0] == pb[0] == "test"
            and pa[3] == pb[3] == "host" and pa[4] == pb[4]):
        return "a host tool shipped with each test that uses it"
    return None


def run(cmd, cwd):
    return subprocess.run(cmd, cwd=cwd, check=True, capture_output=True,
                          text=True).stdout


def tracked_sources(repo_path):
    """Every tracked source file in one repository, as repo-relative paths."""
    try:
        out = run(["git", "ls-files", "-z"], repo_path)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    files = [p for p in out.split("\0") if p]
    return [p for p in files if os.path.splitext(p)[1] in SOURCE_SUFFIXES]


def exempt_reason(repo, rel):
    repo_norm = normalize_repo_name(repo) if repo else None
    for want_repo, prefix, reason in EXEMPT:
        if want_repo is not None and normalize_repo_name(want_repo) != repo_norm:
            continue
        if rel.startswith(prefix):
            return reason
    return None


_BLOCK = re.compile(r"/\*.*?\*/", re.S)
_LINE = re.compile(r"//[^\n]*")


def significant_lines(text):
    """The file reduced to what the gate compares: code, without decoration."""
    text = _BLOCK.sub("", text)
    text = _LINE.sub("", text)
    out = []
    for line in text.splitlines():
        line = line.strip()
        if line:
            out.append(line)
    return out


def load(path):
    try:
        with open(path, "rb") as f:
            raw = f.read()
    except OSError:
        return None
    return raw.decode("utf-8", errors="replace")


def similarity(a_lines, b_lines):
    return SequenceMatcher(None, a_lines, b_lines, autojunk=False).ratio()


def main():
    ap = argparse.ArgumentParser(
        description="Section 9 duplicate-source gate.")
    ap.add_argument("-w", "--workspace", default=None,
                    help="directory holding the repositories "
                         "(default: the parent of this script's repository)")
    ap.add_argument("-t", "--threshold", type=float, default=0.85,
                    help="report pairs at or above this ratio (default 0.85)")
    ap.add_argument("--json", default=None, help="also write findings here")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    if not 0.0 < args.threshold <= 1.0:
        print("threshold must be in (0, 1]", file=sys.stderr)
        return 2

    here = os.path.dirname(os.path.abspath(__file__))
    workspace = args.workspace or os.path.dirname(os.path.dirname(here))
    workspace = os.path.abspath(workspace)

    repos = sorted(
        d for d in os.listdir(workspace)
        if d.startswith(REPO_PREFIX)
        and normalize_repo_name(d) not in SKIP_REPOS
        and os.path.isdir(os.path.join(workspace, d, ".git"))
    )
    if not repos:
        print(f"no repositories found under {workspace}", file=sys.stderr)
        return 2

    # --- collect -----------------------------------------------------------
    # A repository is named without the `.git` a working copy's directory may
    # carry (the harness requires micro-os-plus-iii-<port>.git), so that
    # EXEMPT, SIBLINGS and the report name it the same way in any workspace.
    entries = []          # (repo, rel, abs, lines, sha)
    exempted = 0
    for d in repos:
        root = os.path.join(workspace, d)
        repo = normalize_repo_name(d)
        for rel in tracked_sources(root):
            if exempt_reason(repo, rel) is not None:
                exempted += 1
                continue
            ap_ = os.path.join(root, rel)
            text = load(ap_)
            if text is None:
                continue
            lines = significant_lines(text)
            if len(lines) < 20:
                # Too small to say anything useful: a 12-line header that
                # matches another 12-line header is not duplication, it is
                # two short files.
                continue
            sha = hashlib.sha256("\n".join(lines).encode()).hexdigest()
            entries.append((repo, rel, ap_, lines, sha))

    print(f"workspace : {workspace}")
    print(f"repos     : {len(repos)}  ({', '.join(repos)})")
    print(f"sources   : {len(entries)} compared, {exempted} exempt, "
          f"threshold {args.threshold:.2f}")

    findings = []

    # --- exact duplicates --------------------------------------------------
    by_sha = {}
    for e in entries:
        by_sha.setdefault(e[4], []).append(e)

    unique = []
    for sha, group in by_sha.items():
        for a, b in combinations(group, 2):
            findings.append({
                "ratio": 1.0,
                "a": f"{a[0]}/{a[1]}",
                "b": f"{b[0]}/{b[1]}",
                "lines": len(a[3]),
                "kind": "identical",
                "expected": expected_reason(a[1], b[1]),
                # An identical pair is never a sibling: sibling_reason()
                # refuses ratio >= 1.0, so a named pair that someone has
                # copied onto the other lands here and fails, as it should.
                "sibling": None,
            })
        unique.append(group[0])      # one representative per exact-dup group

    # --- near duplicates ---------------------------------------------------
    # Prefilter on size, then on a line-set Jaccard index, before difflib.
    sets = {id(e): set(e[3]) for e in unique}
    order = sorted(unique, key=lambda e: len(e[3]))

    compared = 0
    for i, a in enumerate(order):
        na = len(a[3])
        sa = sets[id(a)]
        for b in order[i + 1:]:
            nb = len(b[3])
            if nb > na / args.threshold:
                break                 # sorted by size: nothing further can pass
            sb = sets[id(b)]
            inter = len(sa & sb)
            if inter == 0:
                continue
            jac = inter / len(sa | sb)
            if jac < args.threshold * 0.7:
                continue
            compared += 1
            r = similarity(a[3], b[3])
            if r >= args.threshold:
                findings.append({
                    "ratio": round(r, 4),
                    "a": f"{a[0]}/{a[1]}",
                    "b": f"{b[0]}/{b[1]}",
                    "lines": min(na, nb),
                    "kind": "near-identical",
                    "expected": expected_reason(a[1], b[1]),
                    "sibling": sibling_reason(f"{a[0]}/{a[1]}",
                                              f"{b[0]}/{b[1]}", r),
                })

    if args.verbose:
        print(f"difflib   : {compared} candidate pairs compared")

    findings.sort(key=lambda f: (-f["ratio"], f["a"], f["b"]))

    # --- report ------------------------------------------------------------
    if args.json:
        with open(args.json, "w") as f:
            json.dump(findings, f, indent=2)

    expected = [f for f in findings if f["expected"]]
    siblings = [f for f in findings if not f["expected"] and f.get("sibling")]
    unexplained = [f for f in findings
                   if not f["expected"] and not f.get("sibling")]

    print(f"expected  : {len(expected)} pair(s) -- "
          "the same test carried by two boards")
    print(f"siblings  : {len(siblings)} pair(s) -- "
          "named in SIBLINGS, alike because they do similar jobs")

    # Named, so that a claim nobody can see is not a claim.
    for f in siblings:
        print(f"  {f['ratio']:.3f}  {f['lines']:5d}  {f['a']}")
        print(f"                 {f['b']}")
        print(f"                 -- {f['sibling']}")

    failed = False

    if unexplained:
        across = sum(1 for f in unexplained
                     if f["a"].split("/")[0] != f["b"].split("/")[0])
        print(f"\n{len(unexplained)} unexplained pair(s): "
              f"{across} across repositories, "
              f"{len(unexplained) - across} within one")
        print()
        for f in unexplained:
            note = ""
            # A named pair that has become identical arrives here rather than
            # in `siblings`, because sibling_reason() refuses ratio >= 1.0.
            # Say so, or the message reads as a mystery.
            if any(frozenset((f["a"], f["b"])) == frozenset((a, b))
                   for a, b, _ in SIBLINGS):
                note = ("  <-- named in SIBLINGS, but these two are now "
                        "IDENTICAL: that is a copy, not a resemblance")
            print(f"  {f['ratio']:.3f}  {f['lines']:5d}  {f['a']}")
            print(f"                 {f['b']}{note}")
        failed = True

    # A SIBLINGS entry matching nothing at all is stale: the files were
    # merged, moved or renamed, and the justification has become fiction.
    # An entry whose pair went identical is reported above instead, so it is
    # not counted as stale here.
    seen = {frozenset((f["a"], f["b"])) for f in siblings}
    seen |= {frozenset((f["a"], f["b"])) for f in unexplained}
    stale = [(a, b) for a, b, _ in SIBLINGS if frozenset((a, b)) not in seen]
    if stale:
        print(f"\n{len(stale)} stale SIBLINGS entry/entries -- "
              "these no longer match any compared pair:")
        for a, b in stale:
            print(f"  {a}\n  {b}")
        failed = True

    if failed:
        print("\nFAIL: unexplained duplicate sources")
        return 1

    print("\nPASS: no unexplained duplicate sources")
    return 0


if __name__ == "__main__":
    sys.exit(main())
