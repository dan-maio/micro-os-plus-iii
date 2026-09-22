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


def expected_reason(rel_a, rel_b):
    """Duplication this layout asks for. Reported, but not a failure."""
    na, nb = board_neutral(rel_a), board_neutral(rel_b)
    if na is not None and na == nb:
        return "the same test file carried by two boards; every board owns its tests"
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
    for want_repo, prefix, reason in EXEMPT:
        if want_repo is not None and want_repo != repo:
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
        and d not in SKIP_REPOS
        and os.path.isdir(os.path.join(workspace, d, ".git"))
    )
    if not repos:
        print(f"no repositories found under {workspace}", file=sys.stderr)
        return 2

    # --- collect -----------------------------------------------------------
    entries = []          # (repo, rel, abs, lines, sha)
    exempted = 0
    for repo in repos:
        root = os.path.join(workspace, repo)
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
                })

    if args.verbose:
        print(f"difflib   : {compared} candidate pairs compared")

    findings.sort(key=lambda f: (-f["ratio"], f["a"], f["b"]))

    # --- report ------------------------------------------------------------
    if args.json:
        with open(args.json, "w") as f:
            json.dump(findings, f, indent=2)

    expected = [f for f in findings if f["expected"]]
    unexplained = [f for f in findings if not f["expected"]]

    print(f"expected  : {len(expected)} pair(s) -- "
          "the same test carried by two boards")

    if not unexplained:
        print("\nPASS: no unexplained duplicate sources")
        return 0

    across = sum(1 for f in unexplained
                 if f["a"].split("/")[0] != f["b"].split("/")[0])
    print(f"\n{len(unexplained)} unexplained pair(s): "
          f"{across} across repositories, {len(unexplained) - across} within one")
    print()
    for f in unexplained:
        print(f"  {f['ratio']:.3f}  {f['lines']:5d}  {f['a']}")
        print(f"                 {f['b']}")

    print("\nFAIL: unexplained duplicate sources")
    return 1


if __name__ == "__main__":
    sys.exit(main())
