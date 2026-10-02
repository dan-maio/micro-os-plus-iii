"""Fail-loud in-place text edits for the chunk recipes.

Every helper asserts the pristine anchor is present the exact number of times
expected, so a substitution whose anchor has moved errors LOUDLY instead of
silently no-op'ing. A silent no-op in an integration recipe is dangerous: it can
let a -Werror regression through, or make a single-core-invariant check pass by
coincidence. Prefer the plain-string helpers (replace_n / strip_n) — they need
no escaping and read like the source; reach for sub_re_n only when the match
genuinely needs a regex (variable whitespace, non-greedy spans, repeats).

Usage from a chunk script (so the literals stay multi-line and unescaped):

    python3 - "$(dirname "$0")" path/to/file.cpp <<'PY'
    import sys; sys.path.insert(0, sys.argv[1])
    from _edit import edit, replace_n
    edit(sys.argv[2], lambda s: replace_n(s, "old", "new", "label"))
    PY
"""
import re


def replace_n(s, old, new, label, n=1):
    c = s.count(old)
    assert c == n, f"{label}: expected {n} occurrence(s) of the anchor, found {c}"
    return s.replace(old, new)


def strip_n(s, old, label, n=1):
    return replace_n(s, old, "", label, n)


def sub_re_n(s, pattern, repl, label, n=1, flags=0):
    s2, c = re.subn(pattern, repl, s, flags=flags)
    assert c == n, f"{label}: expected {n} regex match(es), found {c}"
    return s2


def edit(path, fn):
    with open(path) as f:
        s = f.read()
    s = fn(s)
    with open(path, "w") as f:
        f.write(s)
