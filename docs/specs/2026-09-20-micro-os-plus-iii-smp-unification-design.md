---
title: "µOS++ III SMP — Project Unification Design"
subtitle: "Migrating micro-os-plus-iii-smp-old to a unified, deduplicated micro-os-plus-iii-smp"
date: 2026-09-20
status: draft — awaiting review
---

# 1. Goal

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

# 2. Locked decisions

| # | Decision | Value |
|---|---|---|
| D1 | Scope | C/C++ only. The four Rust trees stay in the old repo. |
| D2 | Boards | All 11 C++ board trees migrate. |
| D3 | Kernel provenance | Use the already-patched kernel from this tree. No `setup.sh`, no `patches/`, no `BASE`. Upstream reconciliation happens later as a GitHub merge, resolving by hand what the patches encode today. |
| D4 | History | Fresh `git init`, patched tree only. No history carried forward. |
| D5 | Test layout | `test/<board>/{qemu,hwd}/` uniformly across all 11 boards. |
| D6 | Execution | Vertical slice: skeleton, then rpi-32b/64b end-to-end, then lyra-a7, then pico2 x5, then cortexm x3. |
| D7 | Duplication | Near zero. Common code lives once, in a folder, referenced everywhere. |

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
| `exception_handler.cpp` | 327 | 327 | **0** | `port/armv7-a/common/` |
| `handlers.cpp` | 234 | 247 | 13 | `port/armv7-a/common/` + `#ifdef` |
| `context_switch.cpp` | 92 | 102 | 16 | `port/armv7-a/common/` + `#ifdef` |
| `smp_secondary.cpp` | 16 | 28 | 12 | `port/armv7-a/common/` + `#ifdef` |
| `port_sys.cpp` | 47 | 49 | 36 | per-SoC |
| `timer_arm.cpp` | 25 | 66 | 55 | per-SoC |
| `smp.cpp` | 37 | 82 | 89 | per-SoC (IPI mechanism) |
| `mmu.cpp` | 144 | 142 | 108 | per-SoC |
| `startup.S` | 213 | 256 | 155 | per-SoC |

~650 lines are genuinely architecture-level and become one shared copy.

## 4.4 SoC code shared across ISAs — 2 copies to 1

`mailbox.cpp` is 201 lines with a 25-line delta between rpi-32b and rpi-64b —
the same BCM2837 silicon driven from two ISAs. Architecture-first filing would
split it across `armv7-a/` and `armv8-a/`. Under D7 it must not duplicate, so
`port/soc-common/<soc>/` exists for exactly this case.

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
D7 each logical test has exactly **one** source, in `test/common/<app>/`, and
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
application sources from `test/common/`. The variant is a build configuration,
not a copy of the code.

**5.2 "rpi-32b and rpi-64b as independent board trees."** Same reasoning:
95% identical sources. **Revised:** two board entries, one shared app source set.

D5's uniform `test/<board>/{qemu,hwd}/` tree is preserved in both cases. What
changes is that those directories hold *build manifests*, not *source copies*.

# 6. Target tree

```
micro-os-plus-iii-smp/
├── CMakeLists.txt                  top level; composes INTERFACE libraries only
├── cmake/
│   ├── toolchains/                 arm-none-eabi, aarch64-none-elf
│   └── uos-app.cmake               the shared app-declaration function
│                                   (replaces 214 Makefiles)
├── micro-os-plus-iii/              the kernel, once — 706 files, arch-independent
│
├── devices/                        portable device layer, once
│   ├── include/micro-os-plus/devices/
│   └── src/                        usb-dwc2, sd, flatfs, led, uart, spi
│
├── port/
│   ├── soc-common/
│   │   └── bcm2837/                mailbox.cpp — shared by both BCM2837 ISAs
│   ├── armv7-a/
│   │   ├── common/                 exception_handler, handlers, context_switch
│   │   ├── rk3506/    {src,include,device/{src,include}}
│   │   └── bcm2837/   {src,include,device/{src,include}}
│   ├── armv8-a/
│   │   └── bcm2837/   {src,include,device/{src,include}}
│   ├── armv7e-m/
│   │   └── stm32f4/   {src,include,device/{src,include}}
│   └── armv8-m/
│       └── rp2350/    {src,include,device/{src,include}}
│
└── test/
    ├── common/                     ONE source per logical test
    │   ├── smp_test0/  smp_test1/  ...  usb_test/  sd_test/  ...
    └── <board>/{qemu,hwd}/         11 boards; manifests, toolchain, linker, flash scripts
```

**Board to architecture to SoC:**

| board | arch | SoC |
|---|---|---|
| nucleof411, weactf411, weactf412 | armv7e-m | stm32f4 |
| pico2, pico2-std, pico2-sdk, pico2-sdk-min, stdcpp-pico2 | armv8-m | rp2350 |
| lyra-a7 | armv7-a | rk3506 |
| rpi-32b | armv7-a | bcm2837 |
| rpi-64b | armv8-a | bcm2837 |

ARMv6-M appears in the architecture list but has no board in the tree; it gets
no `port/` directory until one exists.

# 7. Component design

## 7.1 Kernel

`cortexm/micro-os-plus-iii/` copied verbatim to `micro-os-plus-iii/`. Its
existing `CMakeLists.txt:41` already defines `micro-os-plus-iii-interface` as a
source-only INTERFACE library aliased to `micro-os-plus::iii`, so it needs no
modification. Upstream's own `tests/` subtree is retained as shipped.

## 7.2 `port/`

Every existing port already implements upstream's port contract exactly:

```
src/rtos/os-core.cpp
include/cmsis-plus/rtos/port/{os-decls.h, os-c-decls.h, os-inlines.h}
```

All five ports obey it without exception, so `port/<arch>/<soc>/` supplies that
contract plus low-level bring-up (`startup.S`, `mmu`, `smp`, `timer`), while
`port/<arch>/common/` holds the shared ISA core and `port/soc-common/<soc>/`
holds code shared by one SoC across two ISAs.

**Divergence policy.** `#ifdef OS_ARCHITECTURE_FEATURE` is the exception, used
only for small deltas (the 13- and 16-line cases in Section 4.3). Anything
larger gets its own file under the SoC directory. `#ifdef` must never become
the mechanism by which two whole implementations share a file.

## 7.3 `devices/`

Holds cross-SoC-portable device code — the 2,966 verbatim-shared lines plus
LED/UART/SPI abstracted from the per-board `bsp/` directories. Register-level
SoC glue stays in `port/<arch>/<soc>/device/`. The boundary is the one the
code already drew: if it is identical across SoCs or ISAs, it belongs here.

## 7.4 `test/`

`test/common/<app>/` holds one source per logical test. `test/<board>/{qemu,hwd}/`
holds a short manifest naming which shared apps that board builds, its
toolchain file, linker script and flash/run scripts. Per-board source deltas,
where they genuinely exist, are expressed as `#ifdef` inside the shared source
or as a small board-specific supplementary file — never as a forked copy.

All 11 boards get both `qemu/` and `hwd/` per D5; 8 boards start with an empty
`qemu/`, which honestly marks where QEMU coverage is still missing.

## 7.5 CMake

The top level composes INTERFACE libraries, all source-only, no binaries:

- `micro-os-plus::iii` — the kernel
- `micro-os-plus::port-<arch>-<soc>` — one per SoC, pulling in `<arch>/common` and `soc-common` as needed
- `micro-os-plus::devices` — the portable device layer

Each application links the three and adds its own `main.cpp`. `uos-app.cmake`
provides the single function that declares an application, so a per-app
`CMakeLists.txt` is a few lines. All paths are relative to the repository root;
no absolute paths anywhere, including in scripts.

# 8. Migration sequence

Per D6, a vertical slice proves the architecture before it is replicated.

1. **Skeleton + kernel.** Tree, root `CMakeLists.txt`, `cmake/toolchains/`,
   `uos-app.cmake`, kernel in place. Gate: kernel compiles standalone.
2. **rpi-32b + rpi-64b, end to end.** The proving slice — it exercises
   `devices/` extraction, `port/<arch>/common` + `<soc>`, `port/soc-common/bcm2837`,
   the shared `test/common/` app sources across two ISAs, and the only real
   `qemu/` content. 12 shared app sources, 24 build targets.
   Gate: all 24 targets build; QEMU tests pass; hardware tests pass on the Pi.
3. **lyra-a7.** Validates `port/armv7-a/common/` against a second, unrelated
   SoC — the strongest test of the arch/SoC boundary. 13 apps.
   Gate: `exception_handler.cpp` is shared, unmodified, by both SoCs.
4. **pico2 x5.** 125 build targets over one shared app source set.
   Gate: no app source exists more than once.
5. **cortexm x3.** 4 apps. Gate: full tree builds.

Each step is a reviewable, buildable increment.

# 9. Verification gates

- **No duplicate sources.** A checked-in script reports any two tracked source
  files with identical or near-identical content above a threshold. Target: zero
  findings outside `micro-os-plus-iii/` (upstream's own tree is exempt).
- **No absolute paths.** Grep gate over all scripts and CMake files.
- **Build coverage.** Every board's manifest builds every app it claims.
- **QEMU.** rpi-32b and rpi-64b QEMU suites pass.
- **Hardware.** Per-board hardware tests pass where hardware is available.

# 10. Out of scope

- The four Rust trees (D1). They remain in the old repo.
- The upstream GitHub merge (D3). This migration produces the tree that merge
  will later be applied to.
- `micro-os-plus-iii/tests/` — upstream's own suite, carried as shipped.
- New functionality. This is a restructuring; behaviour must not change.

# 11. Open questions

1. **Board naming.** This spec uses `lyra-a7`, `rpi-32b`, `rpi-64b`,
   `nucleof411`, `weactf411`, `weactf412`, `pico2`, `pico2-std`, `pico2-sdk`,
   `pico2-sdk-min`, `stdcpp-pico2`. Confirm or replace.
2. **`stdcpp-pico2`.** It has only 7 apps and 8 tracked Makefiles, and is a
   `std`-C++ reference variant rather than an RTOS port. Confirm it migrates as
   a board rather than being dropped or parked.
3. **Near-identical threshold.** Section 9's duplicate-source gate needs a
   concrete similarity threshold. Proposed: flag any pair above 85% identical.
