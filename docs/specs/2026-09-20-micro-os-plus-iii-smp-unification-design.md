---
title: "µOS++ III SMP — Project Unification Design"
subtitle: "Migrating micro-os-plus-iii-smp-old to a unified, deduplicated micro-os-plus-iii-smp"
date: 2026-09-20
status: approved — revision 2, 2026-09-20 (architecture-specific ports, multi-repo)
---

# 1. Goal

> **Status 2026-10-06.** This is the original unification design; its decisions stand, except that the separate devices repository (and its `UOS_DEVICES_DIR`) was later dissolved into the ports. The migration from `xpack-development` to `smp`
> was then executed with the commit-only procedure of
> [`xpack-dev-smp.md`](../smp-integration/xpack-dev-smp.md) Part II: no `scripts/smp/`, no chunk recipes, one
> subject per commit, only added or modified files. The result is recorded in
> its Part III: 343 commits over `micro-os-plus-iii`, `-posix-arch`,
> `-cortexm`, `-aarch32` and `-aarch64`; `micro-os-plus-iii-devices` dissolved
> into the ports' `drivers/` and `soc/<chip>/` (no `UOS_DEVICES_DIR`); every
> commit built; the full xpm test run (native, QEMU Cortex-M, `test-smp-cmake`)
> green. Where this document disagrees with it (step or PR numbering, scripts,
> the devices repository, test counts), `xpack-dev-smp.md` applies.

> **Superseded on 2026-09-21 for the test layout.** This design put one copy of
> each test in `test_smpl/common/` and had every port build the same list. That
> is no longer how it works: every board owns its tests, in
> `boards/<id>/test/` of the architecture project, and `test_smpl/` keeps only
> the two runners. The reasoning and the current layout are in
> [`tests-in-aarch32-aarch64.md`](../tests-in-aarch32-aarch64.md). Everything
> else in this document — the three-tier fact model, the board contract, the
> repository split — still holds. D7, the sections on `test_smpl/common/` and
> Q7 below should be read as history.

Migrate the C/C++ content of `micro-os-plus-iii-smp-old` into a new,
unified `micro-os-plus-iii-smp` repository with a modern, compact layout:
one kernel, one device layer, one port tree organised by architecture, and
one test tree covering every board.

**Governing rule — near-zero duplication.** Wherever near-identical code
exists, the common part is written once into a dedicated folder and
referenced everywhere it is needed. Divergence is expressed as a delta
(a small `#ifdef`, or a separate file where the delta is large), never as
a second copy of the whole.

This rule outranks layout convenience. Where it conflicts with an earlier
structural decision, it wins, and Section 5 records each such case.

## 1.1 Terminology — "portable" is not used in this spec

The requirement document uses *portable* in two opposite senses: Section
"Architecture-Independent Code" asks for a folder holding code that is
"not portable-independent" (meaning code valid everywhere), while the
`devices` section asks for "the portable part of the device
implementations" (also meaning code valid everywhere). A review note on
this spec then defined the pair the other way round — *non-portable* as
"available on all platforms" and *portable* as "code specific to a
platform".

All three readings are defensible and they contradict each other, so the
words are retired. This spec uses exactly these terms:

| term | meaning | where it lives |
|---|---|---|
| **common** | valid on every architecture it is compiled for | the main repo: `micro-os-plus-iii/`, `devices/`, `test_smpl/common/` |
| **architecture-specific** | valid only for one architecture | an architecture repo: `<arch>/src/`, `<arch>/include/` |
| **SoC-specific** | valid only for one silicon family within an architecture | inside its architecture repo, behind `OS_ARCHITECTURE_FEATURE` or its own file |

The organising axis is the **architecture**, not the target board. A board
is a build configuration of an architecture, never a folder of its own in a
port. *Target-specific* is deliberately not used as a category, because it
invites per-board folders and that is how duplication returns.

The test of what is common is measurement, not intuition: if two copies are
identical or near-identical, the shared part is common by definition, and
Section 4 records the measurements.

# 2. Locked decisions

| # | Decision | Value |
|---|---|---|
| D1 | Scope | C/C++ only. The four Rust trees stay in the old repo. |
| D2 | Boards | All 11 C++ board trees migrate. |
| D3 | Kernel provenance | Use the already-patched kernel from this tree. No `setup.sh`, no `patches/`, no `BASE`. Upstream reconciliation happens later as a GitHub merge, resolving by hand what the patches encode today. |
| D4 | History | Fresh `git init`, patched tree only. No history carried forward. |
| D5 | Test layout | `test/<board>/{qemu,hwd}/` uniformly across all 11 boards. |
| D6 | Execution | Vertical slice: skeleton, then rpi-32b/64b end-to-end, then lyra-a7, then pico2 x5, then cortexm x3. |
| D13 | Devices separate | Drivers and SoC support are their own repository, not part of the kernel. Keeps the kernel merge-clean against upstream (D3) and lets each build take only what it needs. |
| D14 | Kernel is a core plus optional groups | `micro-os-plus::iii` is the 37 sources every port compiles, measured against the proven rpi builds. posix-io, drivers, the generic startup path, newlib-reent, semihosting and the three trace backends are separate opt-in targets. Exporting all 63 as one target is not merely wasteful: `posix-io/c-syscalls-posix.cpp` declares `read`/`write` returning `ssize_t` where newlib declares `int`, so linking it breaks any build that also includes `<unistd.h>`. |
| D15 | The SMP port declarations are shared, opt-in | `port/smp-common/cmsis-plus/rtos/port/os-decls.h` is the C++ half of the port contract (§7.2) and contains no machine instructions. All three ARM ports had it byte-identical but for one missing `volatile`. It is on no default include path: a port links `micro-os-plus::port-smp-decls` or writes its own, so the two can never be confused. |
| D16 | The test applications are ISA-neutral, and stay in the kernel repository | An application names no register and no instruction that is not portable across the ports that can run it. What it needs from a port it takes through the port's headers. This is what lets one copy serve every architecture project. |
| D7 | Duplication | Near zero. Common code lives once, in a folder, referenced everywhere. |
| D8 | Organising axis | **Architecture-specific, not target-specific.** Four ports: `cortexm`, `aarch32`, `aarch64`, `posix-arch`. A board is a build configuration, never a port folder. |
| D9 | Topology | **Six repositories.** `micro-os-plus-iii-smp` is the kernel plus shared tests. `micro-os-plus-iii-devices` holds drivers and SoC support, included by a build only when needed. Four architecture projects hold only `src/` and `include/`. All are independent; dependencies run one way, toward the kernel. |
| D10 | Linkage | Architecture projects are **independent repositories outside** the main repo. Each pins the main repo as a **Git submodule** and consumes it via `add_subdirectory`. The dependency is one-way: an architecture project uses the main repo, never the reverse, and the main repo contains no `arch/` folder. |
| D11 | `cortexm` SMP | `cortexm` must be SMP. pico2/RP2350 already is; its core becomes the architecture's SMP implementation and the STM32 boards run it at `OS_NCPU=1`. |
| D12 | `posix-arch` SMP | `posix-arch` must be SMP, modelled as **one host thread per CPU**. See Section 7.6. |

## 2.1 Remotes (already done)

- `GIT/micro-os-plus-iii-smp.git` was renamed to `GIT/micro-os-plus-iii-smp-old.git` (77 MB, `master` + `feat/rpi-usb-gadget`, history intact).
- Both clones that referenced the old name were repointed: `TMP7/micro-os-plus-iii-smp-old` and `TMP7/backup/micro-os-plus-iii-smp`.
- A new empty bare repo was created at `GIT/micro-os-plus-iii-smp.git` (`HEAD -> refs/heads/master`, 0 refs). It is the remote for this migration.
- Working tree for the new project: `TMP7/micro-os-plus-iii-smp`, sibling of `-old`.

# 3. Measured baseline

All figures below were measured from the tree, not estimated.

**Repository:** 7,723 tracked files, 13 top-level directories, organised by
architecture family (`cortexm/`, `cortex-a7/`, `pico2/`, `rpi/`), each family
a self-contained workspace carrying its own copy of everything.

**C/C++ board trees:** 11, holding 166 test applications.

| family | boards | apps |
|---|---|---:|
| cortexm | nucleof411, weactf411, weactf412 | 4 |
| cortex-a7 | lyra-a7 | 13 |
| pico2 | pico2, pico2-std, pico2-sdk, pico2-sdk-min, stdcpp-pico2 | 125 |
| rpi | rpi-32b, rpi-64b | 24 |

**Build files:** 214 tracked `Makefile`, 234 tracked `CMakeLists.txt`.
A test application is only ~5 tracked files (`main.cpp`, `Makefile`,
`.gitignore`, and 1-2 flash scripts); the ~100 other files per app directory
are untracked `build/` and `output/` artifacts. Every application currently
recompiles the entire kernel into its own private `build/` directory.

**QEMU coverage:** real support exists only for rpi-32b and rpi-64b, plus a
single `weactf411/spi-pipeline/run-qemu.sh`. The `qemu-cortex-m*` directories
found elsewhere belong to upstream's own test suite inside the kernel copies,
not to these ports.

**Absolute paths:** 32 occurrences across roughly 20 shell scripts
(`qemu.sh`, `import.sh`, `build-fixtures.sh`).
Absolure path ok only for openocd, and compiler tools

# 4. Duplication inventory

This is the work. Each row is measured, and each has a target.

## 4.1 Kernel — 5 copies to 1

The kernel exists five times: a pristine root copy plus four per-architecture
copies. The four patched copies are **byte-identical to one another**:

| pair | differences |
|---|---:|
| cortexm vs pico2 | 0 |
| cortexm vs rpi | 0 |
| cortexm vs cortex-a7 | 0 (excluding 80 stray `.o`/`.d` files) |

Each is upstream + the same two patches. The patched kernel differs from
pristine upstream in exactly **6 files**:

```
include/cmsis-plus/rtos/os-c-decls.h
include/cmsis-plus/rtos/os-decls.h
include/cmsis-plus/rtos/os-sched.h
include/cmsis-plus/rtos/os-thread.h
src/rtos/os-core.cpp
src/rtos/os-thread.cpp
```

**Source of truth:** `cortexm/micro-os-plus-iii/` — 706 files, zero build
litter. (`pico2/` and `rpi/` copies are byte-identical alternatives;
`cortex-a7/` is excluded for its stray object files.)

**Eliminated:** ~2,100 duplicate files.

**Provenance note.** D3 drops `BASE`, which currently records the fork point
(`micro-os-plus-iii` @ `c47f806b57f8b9b870ec7b89ded663dec354df96`, branch
`xpack-development`; `micro-os-plus-iii-cortexm` @ `687e975caa298519cb214d4b5a9774c48f784816`).
Those two hashes are the only record of what the planned GitHub merge should
diff against. This spec preserves them **in this document** so the information
survives even though the `BASE` file does not. No build machinery depends on them.

## 4.2 Device code — 2 copies to 1

Measured across rpi-32b (AArch32) and rpi-64b (AArch64) — same filenames,
two different ISAs:

| file | lines | diff lines | disposition |
|---|---:|---:|---|
| `usb_dwc2.cpp` | 1263 | **0** | `devices/` |
| `flatfs.cpp` | 904 | **0** | `devices/` |
| `sd.cpp` | 799 | 4 | `devices/` |

**2,966 lines duplicated verbatim across two ISAs.** This is the empirical
justification for a top-level `devices/` folder: the code already proved it
is ISA-independent.

## 4.3 Architecture port core — 2 copies to 1

The two ARMv7-A ports target unrelated silicon (Rockchip RK3506 with GIC and
Rockchip mailbox; Broadcom BCM2837 with spin-table and BCM local mailbox), yet
share a substantial ISA-level core:

| file | RK3506 | BCM2837 | diff | disposition |
|---|---:|---:|---:|---|
| `exception_handler.cpp` | 327 | 327 | **0** | `aarch32/src/` shared |
| `handlers.cpp` | 234 | 247 | 13 | `aarch32/src/` + `#ifdef` |
| `context_switch.cpp` | 92 | 102 | 16 | `aarch32/src/` + `#ifdef` |
| `smp_secondary.cpp` | 16 | 28 | 12 | `aarch32/src/` + `#ifdef` |
| `port_sys.cpp` | 47 | 49 | 36 | per-SoC, inside `aarch32` |
| `timer_arm.cpp` | 25 | 66 | 55 | per-SoC, inside `aarch32` |
| `smp.cpp` | 37 | 82 | 89 | per-SoC (IPI), inside `aarch32` |
| `mmu.cpp` | 144 | 142 | 108 | per-SoC, inside `aarch32` |
| `startup.S` | 213 | 256 | 155 | per-SoC, inside `aarch32` |

~650 lines are genuinely architecture-level and become one shared copy inside
the `aarch32` repo. Both SoCs it serves — RK3506 and BCM2837 — are ARMv7-A.

## 4.4 SoC code shared across ISAs — 2 copies to 1

`mailbox.cpp` is 201 lines with a 25-line delta between rpi-32b and rpi-64b —
the same BCM2837 silicon driven from two ISAs. Under D8/D9 those two ISAs are
two separate repositories, `aarch32` and `aarch64`, so this file is the one
case that fits neither cleanly: it is SoC code, not architecture code, and its
two consumers are different repos.

It is resolved like `devices/` (Section 7.4): the common ~88% moves to the main
repo as SoC support, and each architecture repo keeps only its own delta.
Duplicating it across two repos is not acceptable under D7, because repo copies
drift with nothing to detect it.

## 4.5 Test application sources — the largest win

**rpi, 32b vs 64b `main.cpp`:** 12 apps, **7,228 lines total, ~399 differing (~95% identical)**.

| app | lines | diff |
|---|---:|---:|
| `usb_test` | 1062 | **0** |
| `smp-pro-cons-test` | 757 | 9 |
| `smp_test0` | 94 | 2 |
| `smp-pipeline-test` | 875 | 17 |
| `smp-mat-test` | 1086 | 25 |
| `sd_test` | 538 | 41 |
| `smp-num-test` | 779 | 96 |
| `smp-mat-sdcard-test` | 1337 | 150 |

**pico2 variants, `main.cpp`:**

| comparison | apps | lines | diff | identity |
|---|---:|---:|---:|---:|
| pico2 vs pico2-std | 18 | 6,381 | 69 | **99%** |
| pico2 vs pico2-sdk | 15 | 5,268 | 512 | 91% |

These are the same tests built for different ISAs and runtime flavours. Under
D7 each logical test has exactly **one** source, in `test_smpl/common/<app>/`, and
every board that runs it references that source.

## 4.6 Build files — 214 Makefiles to one shared module

The 214 tracked Makefiles are near-pure boilerplate (~48 differing lines
between the 32b and 64b copy of the same app). They collapse into one shared
CMake module plus a short per-app declaration.

# 5. Where D7 overrides earlier decisions

Two decisions taken before the duplication was measured do not survive D7.
Both are recorded here explicitly rather than silently changed.

**5.1 "pico2 variants become boards."** Taken when the variants looked
genuinely divergent. Measurement shows pico2 vs pico2-std sources are 99%
identical. Keeping five independent board trees would carry ~6,300 lines of
near-identical source forward. **Revised:** the five variants remain five
entries under `test/` (so D5's uniform layout holds and each keeps its own
toolchain, linker script and flash scripts), but they share one set of
application sources from `test_smpl/common/`. The variant is a build configuration,
not a copy of the code.

**5.2 "rpi-32b and rpi-64b as independent board trees."** Same reasoning:
95% identical sources. **Revised:** two board entries, one shared app source set.

D5's uniform `test/<board>/{qemu,hwd}/` tree is preserved in both cases. What
changes is that those directories hold *build manifests*, not *source copies*.

# 6. Target tree

```
micro-os-plus-iii-smp/              MAIN REPO — the common code, at the root
├── CMakeLists.txt                  exports micro-os-plus::iii (+ ::devices)
├── LICENSE-micro-os-plus-iii       upstream MIT licence, retained
├── cmake/
│   ├── toolchains/                 arm-none-eabi, aarch64-none-elf, native
│   │   └── uos-bare-metal-common.cmake
│   └── uos-app.cmake               the shared app-declaration helper
├── src/                            kernel sources        (73 files)
├── include/                        kernel headers        (81 files)
├── devices/                        common device layer
├── test/
│   ├── common/                     ONE source per logical test
│   └── <board>/{qemu,hwd}/         manifests, linker, flash scripts
├── tools/                          verification gates
└── docs/

  ... and, OUTSIDE it, four independent repositories:

micro-os-plus-iii-cortexm/          STM32F4 + RP2350
micro-os-plus-iii-aarch32/          RK3506 + BCM2837
micro-os-plus-iii-aarch64/          BCM2837
micro-os-plus-iii-posix-arch/       native host
└── each: CMakeLists.txt, src/, include/, and micro-os-plus-iii-smp as a
    submodule. They consume the main repo; nothing in the main repo refers
    to them.
```

The kernel is flattened to the repository root rather than nested, which also
aligns paths with upstream (whose root is likewise `src/` + `include/`), so the
GitHub merge planned in D3 lines up path-for-path. Upstream's own `tests/`
(456 files), `doxygen/`, `inspiration/`, `templates/`, `config/` and `scripts/`
are not carried: 552 of the original 706 files were upstream tooling rather
than kernel. The pristine copy remains in the old repository if any of it is
ever wanted back.

**Board to architecture (D8):**

| architecture repo | boards it serves | SoCs | SMP today |
|---|---|---|---|
| `cortexm` | nucleof411, weactf411, weactf412, pico2, pico2-std, pico2-sdk, pico2-sdk-min, stdcpp-pico2 | STM32F4 (ARMv7E-M), RP2350 (ARMv8-M) | RP2350 yes, STM32 no |
| `aarch32` | lyra-a7, rpi-32b | RK3506, BCM2837 (AArch32) | yes |
| `aarch64` | rpi-64b | BCM2837 (AArch64) | yes |
| `posix-arch` | native host | — | **no — to be built** |

`cortexm` spans two Cortex-M sub-architectures and `aarch32` spans two unrelated
SoCs. Both differentiate **inside** the architecture repo, per Section 7.3 —
never by adding per-board folders.

# 7. Component design

## 7.1 Kernel

`cortexm/micro-os-plus-iii/` copied verbatim to `micro-os-plus-iii/`. Its
existing `CMakeLists.txt:41` already defines `micro-os-plus-iii-interface` as a
source-only INTERFACE library aliased to `micro-os-plus::iii`, so it needs no
modification. Upstream's own `tests/` subtree is retained as shipped.

## 7.2 The SMP port contract

The kernel SMP patch is 379 lines, and everything it asks of a port is small:

```
OS_USE_SMP_SCHEDULER             compile-time switch
OS_NCPU                          number of CPUs
port_cpu_id                      "which CPU am I?"
port::scheduler::switch_stacks
port::stack::element_t
```

plus a kernel lock and an inter-processor interrupt, which pico2 supplies as
`smp_klock_t`, `SMP_NO_OWNER` and `port_smp_ipi`. Every existing port already
implements upstream's base contract without exception:

```
src/rtos/os-core.cpp
include/cmsis-plus/rtos/port/{os-decls.h, os-c-decls.h, os-inlines.h}
```

An architecture repo is therefore exactly that contract plus low-level
bring-up, and nothing else.

Measured SMP maturity per port:

| port | os-core.cpp | SMP/CPU/IPI mentions | state |
|---|---:|---:|---|
| pico2 (RP2350) | 748 | 124 | SMP, complete |
| rpi-32b (BCM2837) | 575 | 95 | SMP, complete |
| rpi-64b (BCM2837) | 489 | — | SMP, complete |
| cortex-a7 (RK3506) | 486 | — | SMP, complete |
| cortexm (STM32F4) | 991 | 10 | uniprocessor |
| posix-arch | 552 | 0 | cooperative, single host thread |

## 7.3 Architecture repos

**`cortexm`** — spans ARMv7E-M (STM32F4, single core) and ARMv8-M (RP2350,
dual core). D11: pico2's SMP core is the architecture's implementation, and the
STM32 boards build it with `OS_NCPU=1`. This is a merge of two existing, tested
ports, not new SMP development.

**`aarch32`** — spans RK3506 (GIC + Rockchip mailbox) and BCM2837 (spin-table +
BCM local mailbox). Section 4.3 measured the shared ARMv7-A core at ~650 lines,
including `exception_handler.cpp` at 327 lines and **0 diff** across the two
unrelated SoCs. The divergent parts (`mmu` 108, `smp` 89, `startup.S` 155 diff
lines) are SoC-specific and live behind `OS_ARCHITECTURE_FEATURE` or in their
own files within this repo.

**`aarch64`** — BCM2837 in AArch64. Its device code is identical to
`aarch32`'s and therefore lives in the main repo, not here (Section 4.2).

**`posix-arch`** — native host. Section 7.6.

**Divergence policy.** `#ifdef OS_ARCHITECTURE_FEATURE` is the exception, for
small deltas only. Anything larger gets its own file inside the architecture
repo. `#ifdef` must never become the mechanism by which two whole
implementations share a file, and a per-board folder is never the answer.

## 7.4 `devices/`

Lives in the **main repo** (D9), because its largest consumers — `aarch32` and
`aarch64` — are now separate repositories, and duplicating code across repos is
strictly worse than across folders: the copies version independently and no
diff can catch the drift.

Holds device code common across architectures — the 2,966 verbatim-shared
lines measured in Section 4.2 plus LED/UART/SPI abstracted from the per-board
`bsp/` directories. Register-level SoC glue stays inside its architecture repo.
The boundary is the one the code already drew: if it is identical across SoCs
or ISAs, it belongs here.

## 7.5 `test/`

Lives in the **main repo**, for the same reason as `devices/`: the rpi test
sources are 95% identical across two ISAs that are now two repositories.

`test_smpl/common/<app>/` holds one source per logical test. `test/<board>/{qemu,hwd}/`
holds a short manifest naming which shared apps that board builds, its
toolchain file, linker script and flash/run scripts. Per-board source deltas,
where they genuinely exist, are expressed as `#ifdef` inside the shared source
or as a small board-specific supplementary file — never as a forked copy.

All 11 boards get both `qemu/` and `hwd/` per D5; 8 boards start with an empty
`qemu/`, which honestly marks where QEMU coverage is still missing.

## 7.6 `posix-arch` — SMP on the native host

The vendored `micro-os-plus-iii-posix-arch` is pristine upstream v1.0.1, 19
files, its own GitHub remote. It is **not** SMP, and upstream's `NOTES.md`
says so directly: *"the scheduler runs in cooperative mode only; thread
pre-emption might be possible, but was considered not worth the effort."*

**Current implementation** — one host thread; µOS++ threads are `ucontext`
coroutines switched with `getcontext`/`makecontext`/`swapcontext`; the tick is
`setitimer(ITIMER_REAL)` raising `SIGALRM`; "interrupt disable" is
`sigprocmask` on the clock signal.

**Target model (D12) — one host thread per CPU.** `OS_NCPU` host threads are
created at startup, each running the scheduler loop and each *being* a CPU.
µOS++ threads remain `ucontext` contexts switched **within** a CPU, so the
existing, working context-switch code is preserved.

| concern | mechanism |
|---|---|
| `port_cpu_id` | `thread_local` CPU index, set when the host thread is created |
| kernel lock | `pthread_mutex` or an atomic spinlock, matching `smp_klock_t` |
| IPI | `pthread_kill(tid, SIGUSR1)` to the target CPU's host thread |
| per-CPU tick | `timer_create` with `SIGEV_THREAD_ID` |
| interrupt disable | `pthread_sigmask` — per-thread mask *is* per-CPU masking |
| thread switch | unchanged `ucontext` |

**Three defects the move to multiple host threads exposes.** These are not
optional polish; the port is incorrect without them.

1. **`sigprocmask` must become `pthread_sigmask`.** In a multithreaded process
   the behaviour of `sigprocmask` is unspecified. The replacement is also a
   conceptual win: a per-thread signal mask is exactly per-CPU interrupt
   masking, so the abstraction gets *better*, not more complex.
2. **`setitimer(ITIMER_REAL)` must become `timer_create` + `SIGEV_THREAD_ID`.**
   `ITIMER_REAL` delivers `SIGALRM` to an arbitrary thread of the process, so
   with N CPUs the tick would land on whichever host thread happened to be
   chosen. Per-CPU timers mirror real per-core timers.
3. **Native TLS and thread migration.** `errno` and any `thread_local` are
   *host-thread* local. A µOS++ thread that migrates between CPUs would observe
   a different `errno` and different `thread_local` storage. Either µOS++
   threads are pinned to a CPU, or no port or application state may use native
   TLS. This must be decided before the scheduler allows migration, not after.

**Rejected alternative.** One host thread per *µOS++ thread*, with `OS_NCPU`
run-tokens limiting concurrency, would give true preemption and better
debugger and sanitizer behaviour. It was rejected because it discards the
working `ucontext` machinery and does not express the intended model, in which
a host thread is a CPU.

## 7.7 CMake and submodule linkage

The **main repo** exports INTERFACE libraries, all source-only, no binaries:

- `micro-os-plus::iii` — the kernel
- `micro-os-plus::devices` — the common device layer

Each **architecture repo** pins the main repo as a Git submodule (D10), adds it
with `add_subdirectory`, and exports one further INTERFACE library:

- `micro-os-plus::port-<arch>` — the architecture port

Each application links the three and adds its own `main.cpp`. `uos-app.cmake`
provides the single function that declares an application, so a per-app
`CMakeLists.txt` is a few lines. All paths are relative to the repository root;
no absolute paths anywhere, including in scripts.

# 8. Migration sequence

Per D6 a vertical slice proves the architecture before it is replicated. The
multi-repo topology (D9) adds one rule: **the main repo must be complete enough
to be a submodule before any architecture repo is created.**

1. **Main repo skeleton + kernel.** `cmake/toolchains/`, `uos-app.cmake`, root
   `CMakeLists.txt`, and `cortexm/micro-os-plus-iii/` (706 files, zero build
   litter) copied to `micro-os-plus-iii/`.

   *Gate:* revision 1 of this spec said "the kernel compiles standalone". That
   is impossible and the wording was wrong: `os-decls.h:24` includes
   `<cmsis-plus/rtos/port/os-decls.h>`, which only an architecture repo
   supplies, so the kernel never compiles without a port. The real gate is
   that all three toolchains configure, and that **every source
   `micro-os-plus::iii` declares compiles when a port's headers are present**.
   `tools/verify-kernel-compiles.sh <port-include-dir>` enforces it, using the
   pristine `posix-arch` headers as the witness because they need no
   cross-compiler. Result at the time of writing: 61 of 61.

2. **`aarch32` + `aarch64`, end to end — the proving slice.** Migrates rpi-32b
   and rpi-64b, which exercises every hard part at once: the `devices/`
   extraction into the main repo, two architecture repos consuming it by
   submodule, the shared `test_smpl/common/` sources across two ISAs, and the only
   real QEMU coverage in the project. 12 shared app sources, 24 build targets.
   *Gate:* all 24 targets build; QEMU suites pass; hardware tests pass on the Pi;
   no device or test source exists in more than one repo.

3. **`aarch32` gains RK3506.** Adds lyra-a7 to the existing `aarch32` repo —
   the strongest test of the architecture boundary, since RK3506 and BCM2837
   share ~650 measured lines but diverge sharply on `mmu`, `smp` and
   `startup.S`. 13 apps.
   *Gate:* `exception_handler.cpp` is shared unmodified by both SoCs.

4. **`cortexm`.** Merges pico2's SMP core with the STM32 boards (D11). pico2's
   5 variants contribute 125 build targets over one shared app source set; the
   3 STM32 boards build the same port at `OS_NCPU=1`, which is what makes
   `cortexm` SMP. 129 apps.
   *Gate:* no app source exists more than once; STM32 boards still pass at
   `OS_NCPU=1`; pico2 still passes at `OS_NCPU=2`.

   > **Superseded in part — see [`cortexm-port.md`](../cortexm-port.md).** The
   > gate stands. The *shape* did not survive measurement: pico2's SMP core is
   > not portable Cortex-M SMP, because its kernel lock, IPI and CPU index are
   > RP2350 SIO registers. That makes them board code in this layout, so
   > `cortexm` gained SMP by a board arriving rather than by merging two
   > scheduler files — and the two cores are deliberately still separate,
   > selected per board, because the STM32 boards are hardware-proven on
   > upstream's. The "5 variants" are also fewer than five: `pico2-sdk-min`
   > has byte-identical port files to `pico2-sdk`, and the four trees differ
   > only in how the kernel lock is provided (SIO spinlock / Peterson in
   > software / Pico SDK). Their applications are one set copied four times,
   > 99.0–99.5% identical.

5. **`posix-arch`.** The only genuinely new implementation (D12, Section 7.6):
   host threads as CPUs, plus the three correctness fixes.
   *Gate:* the existing upstream tests pass at `OS_NCPU=1`; the SMP object
   tests pass at `OS_NCPU>1`; no use of `sigprocmask` or `setitimer` remains.

Steps 1-4 are migrations of already-tested code and must preserve behaviour
exactly. Step 5 is new development and is deliberately last, so it builds on a
port contract that four working architectures have already validated.

# 9. Verification gates

- **No duplicate sources, across repos.** A checked-in script reports any two
  tracked source files with identical or near-identical content above 85%,
  scanning the main repo **and every architecture repo together**. Target: zero
  findings outside `micro-os-plus-iii/` (upstream's own tree is exempt). Running
  it over one repo at a time would miss precisely the duplication D9 makes
  possible.
- **No absolute paths.** Grep gate over all scripts and CMake files.
- **Build coverage.** Every board's manifest builds every app it claims.
- **QEMU.** rpi-32b and rpi-64b QEMU suites pass.
- **Hardware.** Per-board hardware tests pass where hardware is available.

# 10. Out of scope

- The four Rust trees (D1). They remain in the old repo.
- The upstream GitHub merge (D3). This migration produces the tree that merge
  will later be applied to.
- `micro-os-plus-iii/tests/` — upstream's own suite, carried as shipped.
- New functionality, with two stated exceptions: `cortexm` gains SMP by
  adopting pico2's already-tested core (D11), and `posix-arch` gains SMP as new
  work (D12). Everything else is restructuring and behaviour must not change.
- The Rust trees remain out of scope (D1), including the Rust posix/host port.

# 11. Resolved decisions

Settled in review on 2026-09-20. Nothing in this spec is now open.

| # | Question | Resolution |
|---|---|---|
| Q1 | Board naming | **Confirmed as proposed.** `lyra-a7`, `rpi-32b`, `rpi-64b`, `nucleof411`, `weactf411`, `weactf412`, `pico2`, `pico2-std`, `pico2-sdk`, `pico2-sdk-min`, `stdcpp-pico2`. |
| Q2 | `stdcpp-pico2` | **Migrates as a board.** Not parked, not dropped, despite being a `std`-C++ reference variant rather than an RTOS port. It keeps its 7 applications and its entry under `test/`. |
| Q3 | Near-identical threshold | **85% accepted.** The Section 9 duplicate-source gate flags any two tracked sources above 85% identical. |
| Q4 | "portable" terminology | **Word retired.** Raised in review as ambiguous; see Section 1.1. |
| Q5 | Organising axis | **Architecture, not target.** Four ports: `cortexm`, `aarch32`, `aarch64`, `posix-arch` (D8). *Target-specific* is retired as a category for the same reason as *portable*: it invites per-board folders. |
| Q6 | Shared device code across `aarch32`/`aarch64` | **Main repo `devices/`.** 2,966 lines measured at 0-diff; duplicating across repos would let them drift unnoticed. |
| Q7 | Where migrated tests live | **Main repo `test_smpl/common/`.** rpi sources are 95% identical across the two ISAs. |
| Q8 | Architecture-repo linkage | **Git submodule** of the main repo, consumed via `add_subdirectory` (D10). |
| Q9 | `posix-arch` CPU model | **One host thread per CPU**, `ucontext` within a CPU (D12, Section 7.6). |

**Revision 2 (2026-09-20)** folded in the architecture-specific reorganisation
and the multi-repo topology. Q1-Q4 were settled against revision 1; Q5-Q9
against revision 2. Sections 6, 7 and 8 were rewritten; the measurements in
Sections 3 and 4 are unchanged and still hold.

The implementation plan is no longer gated. Section 8 step 1 — main repo
skeleton plus kernel — is the next action.
