# Migration status

**Updated:** 2026-09-20 · **Phase:** design approved, migration not started

This file is the cold-start entry point. Read it, then
`docs/specs/2026-09-20-micro-os-plus-iii-smp-unification-design.md` for the
full design and the measurements behind it.

---

## Where things stand

Nothing has been migrated yet. This repository contains the design and the
build hygiene rules, and nothing else. The old tree is untouched.

```
micro-os-plus-iii-smp/          <- you are here; origin wired, 2 commits, pushed
├── .gitignore
└── docs/
    ├── STATUS.md               <- this file
    ├── micro-os-plus-iii-project-unification.md    the original requirement
    └── specs/
        └── 2026-09-20-micro-os-plus-iii-smp-unification-design.md
```

| | |
|---|---|
| New working tree | `/home/dan/Downloads/luckfox_lyra/TMP7/micro-os-plus-iii-smp` |
| New remote | `/home/dan/Downloads/GIT/micro-os-plus-iii-smp.git` |
| Migration source (read-only) | `/home/dan/Downloads/luckfox_lyra/TMP7/micro-os-plus-iii-smp-old` |
| Old remote | `/home/dan/Downloads/GIT/micro-os-plus-iii-smp-old.git` |
| Commits | `cb4b3e1` docs · `0aa4924` .gitignore |

## Done

1. **Remotes reorganised.** `GIT/micro-os-plus-iii-smp.git` renamed to
   `…-smp-old.git` (77 MB, history intact). Both clones that referenced the old
   name were repointed: `TMP7/micro-os-plus-iii-smp-old` and
   `TMP7/backup/micro-os-plus-iii-smp`. A new empty bare repo took the original
   name and is this repository's `origin`.
2. **Old tree analysed and measured.** Every figure in the spec came from the
   tree, not estimation. Summary in the spec, Sections 3 and 4.
3. **Design spec written and committed.** Near-zero duplication (D7) is the
   governing constraint.
4. **`.gitignore` committed.** Verified with `git check-ignore` against all
   7,179 tracked files slated to migrate: none are excluded.

## Decisions — all resolved

Settled 2026-09-20. Spec Section 11 carries the table; nothing is open.

1. **Board naming** — confirmed as proposed.
2. **`stdcpp-pico2`** — migrates as a board, keeping its 7 applications.
3. **Duplicate-detection threshold** — 85%.
4. **"portable" terminology** — retired. Raised in review as ambiguous: the
   requirement document uses the word to mean *common to all platforms*, while
   the review note defined it as *specific to one platform*. The spec now uses
   **common** and **target-specific** only. See spec Section 1.1 before
   deciding which folder any file belongs in.

## Next step

Step 1 of the Section 8 sequence — **skeleton plus kernel**. It is mechanical
and independently verifiable, and is now unblocked:

- Create `cmake/toolchains/`, `cmake/uos-app.cmake`, top-level `CMakeLists.txt`.
- Copy `micro-os-plus-iii-smp-old/cortexm/micro-os-plus-iii/` (706 files, zero
  build litter) to `micro-os-plus-iii/`. Do **not** use the `cortex-a7/` copy —
  it carries 80 stray `.o`/`.d` files. The `pico2/` and `rpi/` copies are
  byte-identical alternatives.
- Gate: the kernel compiles standalone.

Then step 2, the proving slice: rpi-32b and rpi-64b end to end.

## Things a fresh session should not rediscover

- The four patched kernel copies are **byte-identical**. Verified by `diff -rq`.
  They collapse to one at zero risk.
- The kernel differs from pristine upstream in exactly **6 files**, all under
  `rtos/`. That is the entire SMP delta.
- **Upstream fork point**, preserved because the spec drops `BASE`:
  `micro-os-plus-iii` @ `c47f806b57f8b9b870ec7b89ded663dec354df96`
  (branch `xpack-development`), `micro-os-plus-iii-cortexm` @
  `687e975caa298519cb214d4b5a9774c48f784816`. The planned GitHub merge needs
  these as its base.
- A test app is only ~5 tracked files. The ~100 others per app directory are
  untracked `build/` and `output/` artifacts — every app currently recompiles
  the whole kernel privately.
- There are **214 tracked Makefiles**, not the 24 an early count suggested.
- QEMU support is real only for rpi-32b and rpi-64b, plus one
  `weactf411/spi-pipeline/run-qemu.sh`. The `qemu-cortex-m*` directories belong
  to upstream's own suite inside the kernel copies.
- Do **not** add a blanket `*.html` ignore rule. The kernel ships three doxygen
  templates as `.html`; they are upstream source. The `.gitignore` says so.
- `rtk` silently dropped the `-u` flag from `git push -u`. The push succeeded
  but tracking config was not written; it was set with
  `git branch --set-upstream-to`. Expect this on new branches.
