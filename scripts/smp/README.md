# `scripts/smp/` — SMP integration helper tooling

Dev-only automation for executing the 30-step SMP → single-core integration.
See [`../../docs/smp-integration/Implementation-SMP-Integration.md`](../../docs/smp-integration/Implementation-SMP-Integration.md)
for the full runbook. **Removed at Step 30** by `finalize.sh`.

**Fully local.** No script here ever pushes, opens a PR, or writes to a remote —
they only `git clone`/`fetch` (read) and branch/commit/tag locally. Publishing is
a manual step you run by hand when you choose.

## Repo model

All repos live on `github.com/dan-maio`. The single-core baseline and the SMP
source are **two branches of the same repo** (one `origin` remote):

- `xpack-development` — single-core baseline (integrate INTO; `$UPSTREAM = origin/xpack-development`)
- `smp` — multi-core source of truth (lift chunks FROM)

## Scripts

| Script | Purpose |
|---|---|
| `common.sh` | Shared config (paths, branch refs, 12 configs, per-step repo map). Sourced by all. |
| `bootstrap.sh` | From an empty `$WORK` folder: clone the 3 repos, fetch both branches, `xpm install`. |
| `check-env.sh` | Verify toolchain (xpm, cmake, ninja, GCC 11–14, Clang 16–19, qemu, unifdef). |
| `new-step.sh NN` | Create `step/NN` branch(es) forked from `step/NN-1` (or baseline / port tag). |
| `show-chunk.sh NN <file…>` | Show `xpack-development..smp` diff for files, to lift the chunk. |
| `link-ports.sh` | Link local port working copies across all 24 configs (explicit loop). |
| `check-pristine.sh [NN]` | Refuse any modify/delete of the frozen test framework (`package.json`, `tests/**`, `.github/**`); library CMake may change only additively. Run by verify + advance. |
| `verify-step.sh NN` | Gate: pristine check + unifdef invariant (14–23) + link + `test-all` (72) + NCPU=2 smoke (23). `FAST=1` runs cortex-m4f (arm-none-eabi) + native gcc14 (12 runs) for quick kernel iteration — not acceptance. |
| `advance-step.sh NN [msg]` | Commit touched repos + tag `step-NN-green`. |
| `release-port.sh <dir> <ver> <notes>` | Step 24: bump + tag a port release. |
| `finalize.sh` | Step 30: merge baseline, drop tooling, run `test-all` + `test-smp-all`. |
| `run-loop.sh [FROM] [TO]` | Drive new→apply→verify→advance across a step range. `AUTO=1` cherry-picks `smp-step-NN`. |
| `sc-project.py` | Single-core projection (strips `#if defined(OS_USE_SMP_SCHEDULER)` + `NCPU>1`); dependency-free `unifdef` equivalent, used by entangled chunk recipes. |
| `chunks/stepNN.sh` | Per-step chunk recipe (exact files + strip/surgical edits); `run-loop.sh` applies it automatically. See `chunks/README.md`. |
| `migrate-devices.sh` | Part 0: fold `micro-os-plus-iii-devices` into the arch repos (history-preserving `git subtree`). Run once before Step 1. |
| `integrate-aarch-harness.sh` | Steps 25/26/28: make the AArch32/64 ports build+run their tests through the standard xPack chain (kernel sub-targets, port CMake, harness platforms, package.json configs). Lifts from `origin/smp`; fail-loud + idempotent. |
| `absorb-test-smpl.sh` | Step 27: dissolve the smp branch's root `test_smpl/` into the kernel's `tests/smp-support/` and delete the folder, then repoint the aarch32/64 board run-wrappers at it. Lifts from `origin/smp`; fail-loud and idempotent. |
| `full-verify.sh` | Mandatory gate: one GCC + one Clang (+ a cross config), full `xpm install`/`prepare`/`build`/`test` per config, PASS/FAIL matrix. |
| `newer-toolchains.sh` | Baseline-compat probe against the newest system GCC/Clang (chrono trait + clang `-Wno`/unwinder handling). |
| `build-aarch64-rpi.sh` / `build-aarch32-rpi.sh` | Reproduce the standalone `smp_test0..4` bring-up on QEMU `raspi3b` 4-core (`BOARD=rpi3b\|rpi-zero-2w`). The portable harness suites (mutex-stress, …) are NOT built here — they are wired by the smp branch's own `tests.cmake` + harness `platform-support.cpp` and run through the xPack harness. |

## Quick start

```sh
mkdir -p ~/smp-integration && cd ~/smp-integration && export WORK="$PWD"
bash /path/to/micro-os-plus-iii/scripts/smp/bootstrap.sh
cd "$WORK/micro-os-plus-iii"
scripts/smp/check-env.sh
scripts/smp/run-loop.sh 1 30        # interactive; or: AUTO=1 scripts/smp/run-loop.sh 1 30
```

Per-step manual loop:

```sh
scripts/smp/new-step.sh 7
scripts/smp/show-chunk.sh 7 src/rtos/internal/os-lists.cpp src/rtos/os-timer.cpp
# …apply the reviewed chunk…
scripts/smp/verify-step.sh 7
scripts/smp/advance-step.sh 7 "timer ISR re-entrancy"
```
