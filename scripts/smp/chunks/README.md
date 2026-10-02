# `scripts/smp/chunks/` — per-step chunk recipes

One file per step, `stepNN.sh`, recording **exactly** how that step's cohesive
chunk is lifted from `origin/smp` onto the current branch: which files are copied
wholesale, and — for multi-step files (see runbook §10.3) — which later-step
content is stripped or which single hunk is surgically inserted.

These are the reproducible record of the chunk decisions made during integration.
Each script:

- is run from the **kernel repo root** with the step branch already created
  (`new-step.sh NN` first), and `$K` = kernel path (or just run in-tree);
- applies **only** the chunk (no branch/verify/advance — the loop does those);
- is idempotent-ish (re-running re-checks-out the same files).

Usage inside the loop:

```sh
scripts/smp/new-step.sh NN
scripts/smp/chunks/stepNN.sh          # apply the recipe
FAST=1 scripts/smp/verify-step.sh NN
scripts/smp/advance-step.sh NN "<msg>"
```

`run-loop.sh` can call `chunks/stepNN.sh` in place of the manual-apply prompt
once a recipe exists (analogous to the `smp-step-NN` cherry-pick path).

## Recipe types

| Kind | How | Example |
|---|---|---|
| whole-file | `git checkout origin/smp -- <files>` | step03, step05, step06, step08 |
| copy + strip | checkout, then strip later-step hunks | step04 (destroying assert + SMP affinity) |
| surgical insert | keep baseline, insert one hunk | step07 (handler-mode errno) |
| mixed | small files surgical, rest whole | step01 (3 files whole + 1-line inline removal) |

## Text edits

Surgical strips/inserts go through `_edit.py`, a tiny shared helper the recipes
import from a `python3 - "$(dirname "$0")" <files> <<'PY'` heredoc (the multi-line
literals stay verbatim and unescaped). Its `replace_n` / `strip_n` / `sub_re_n`
each **assert the anchor is present the exact expected number of times**, so an
anchor that has moved errors loudly instead of silently no-op'ing — a silent
no-op could otherwise let a `-Werror` regression through or make the single-core
invariant pass by coincidence. Prefer the plain-string helpers; `sub_re_n` is
only for genuinely-regex matches (variable whitespace, non-greedy spans, repeats,
e.g. step04's two affinity blocks / step07's indentation-preserving insert).

## Verification note

Every recipe is followed by `FAST=1 verify-step.sh NN` (cortex-m4f + native
gcc14) and `check-pristine.sh`; a recipe is only "done" when that gate is green.
On top of `_edit.py`'s per-anchor assertions, the strip/insert recipes also print
a post-edit grep assertion (e.g. "destroying leaked: 0") before building, so a
bad edit is caught immediately.
