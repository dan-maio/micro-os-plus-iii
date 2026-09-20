# Migration status

**Updated:** 2026-09-20 · **Phase:** step 1 complete — skeleton and kernel in place

This file is the cold-start entry point. Read it, then
`docs/specs/2026-09-20-micro-os-plus-iii-smp-unification-design.md` for the
full design and the measurements behind it.

---

## Where things stand

**Step 1 of 5 is complete.** The kernel is vendored once and the build
skeleton is in place. The old tree is untouched and remains read-only.

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
5. **Step 1 — skeleton and kernel** (`2502d93`). Kernel vendored once from
   `cortexm/micro-os-plus-iii` (706 files, zero litter). Root `CMakeLists.txt`
   works standalone and as a submodule. Three toolchains share one preamble.
   `cmake/uos-app.cmake` replaces the 214 Makefiles and carries the `OS_NCPU`
   knob. Gate passed: all three toolchains configure; **61 of 61** declared
   kernel sources compile, enforced by `tools/verify-kernel-compiles.sh`.

## Decisions — all resolved

Revision 1 settled Q1-Q4; revision 2 settled Q5-Q9. Spec Section 11 has the
table. Nothing is open.

**Revision 2 changed the shape of the project** (`docs/new-modifications.md`):

1. **Architecture-specific, not target-specific.** Four ports — `cortexm`,
   `aarch32`, `aarch64`, `posix-arch`. A board is a build configuration, never
   a port folder.
2. **Multi-repo.** Main repo holds all common code; each architecture is its
   own Git repo holding only `src/` and `include/`, pinning the main repo as a
   **submodule**.
3. **`devices/` and `test/common/` stay in the main repo** — their consumers
   are now separate repos, and cross-repo copies drift with nothing to catch it.
4. **`cortexm` must be SMP** — largely already true: pico2/RP2350 is a working
   dual-core Cortex-M33 SMP port (124 SMP mentions vs 10 in the STM32 port).
   It becomes the architecture's core; STM32 boards run it at `OS_NCPU=1`.
5. **`posix-arch` must be SMP** — the only genuinely new implementation. One
   host thread per CPU; see spec Section 7.6.

## Next step

Step 2 of the Section 8 sequence — **`aarch32` + `aarch64` end to end**, the
proving slice. It migrates rpi-32b and rpi-64b and exercises every hard part at
once: the `devices/` extraction into this repo, two architecture repos
consuming it by submodule, shared `test/common/` sources across two ISAs, and
the only real QEMU coverage in the project. 12 shared app sources, 24 targets.

*Gate:* all 24 build; QEMU suites pass; hardware tests pass on the Pi; no
device or test source exists in more than one repo.

Superseded notes from step 1:

- Done in `2502d93`. Note the gate wording was corrected: the kernel can
  **never** compile standalone, because `os-decls.h:24` includes
  `<cmsis-plus/rtos/port/os-decls.h>`, which only an architecture repo
  supplies. Use `tools/verify-kernel-compiles.sh <port-include-dir>` instead.

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
- **The SMP port contract is small.** The whole kernel patch is 379 lines and
  asks a port for only: `OS_USE_SMP_SCHEDULER`, `OS_NCPU`, `port_cpu_id`,
  `port::scheduler::switch_stacks`, `port::stack::element_t`, plus a kernel
  lock and an IPI.
- **`cortexm` SMP is not from scratch.** pico2's `os-core.cpp` is already a
  complete dual-core Cortex-M33 SMP port.
- **`posix-arch` is pristine upstream v1.0.1**, untracked in the old workspace,
  with its own GitHub remote. Single host thread, `ucontext` coroutines,
  cooperative only — upstream's `NOTES.md` says so explicitly.
- **Three POSIX defects to fix when going multi-threaded:** `sigprocmask` is
  unspecified in a multithreaded process (use `pthread_sigmask`);
  `setitimer(ITIMER_REAL)` delivers to an arbitrary thread (use `timer_create`
  with `SIGEV_THREAD_ID`); and `errno`/`thread_local` are host-thread local, so
  uOS++ thread migration between CPUs corrupts them.
