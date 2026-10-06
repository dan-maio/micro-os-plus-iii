# Unification of the Micro-OS-Plus-III SMP Projects : Migration of Micro-OS-Plus-III rtos to a modern and compact format like Micro-OS-Plus-III single CPU  from ilg github

> **Status 2026-10-06.** This note describes the repository unification that preceded the migration. The migration from `xpack-development` to `smp`
> was then executed with the commit-only procedure of
> [`xpack-dev-smp.md`](xpack-dev-smp.md) Part II: no `scripts/smp/`, no chunk recipes, one
> subject per commit, only added or modified files. The result is recorded in
> its Part III: 343 commits over `micro-os-plus-iii`, `-posix-arch`,
> `-cortexm`, `-aarch32` and `-aarch64`; `micro-os-plus-iii-devices` dissolved
> into the ports' `drivers/` and `soc/<chip>/` (no `UOS_DEVICES_DIR`); every
> commit built; the full xpm test run (native, QEMU Cortex-M, `test-smp-cmake`)
> green. Where this document disagrees with it (step or PR numbering, scripts,
> the devices repository, test counts), `xpack-dev-smp.md` applies.

## Current Architectures

The currently supported architectures are:

- ARMv6-M
- ARMv7E-M
- ARMv8-M
- ARMv7-A
- ARMv8-A
- ....

## Project Structure

### Architecture-Independent Code

A single folder should contain all code that is **not portable-independent** in Micro-OS-Plus-III SMP, as it currently exists in the Micro-OS-Plus-III GitHub repository.

Files that are generally architecture-independent but require minor architecture-specific modifications should use:

```c
#ifdef OS_ARCHITECTURE
```

If an architecture has specific implementation features, for example the Cortex-M33 Pico 2 SIO mechanism used for locking/synchronization, use:

```c
#ifdef OS_ARCHITECTURE_FEATURE
```

### `devices`

A `devices` subfolder should contain the portable part of the device implementations, including:

- LED
- UART
- SPI
- SD card
- USB
- .....

### `port`

A `port` folder should contain all architecture-specific files that need to be ported or generated.

There should be one subfolder for each architecture. Each architecture folder should contain:

- `src`
- `include`
- `device`

The `device` folder contains the architecture-specific device implementations:

- `src`
- `include`

### `test`

A `test` folder should contain subfolders for each test board (ex: nuclef411, weactf411 . pico2, rpi3b,...)

Each board should have:

- `qemu` — QEMU-based tests
- `hwd` — hardware-based tests

## Migration and Build Requirements

The code must be migrated from **`micro-os-plus-iii-smp-old`** (the patched version) to **`micro-os-plus-smp-new`**.Obs. **`micro-os-plus-iii-smp-old`** is **`micro-os-plus-iii-smp`** patched version, re-named for this "migration", so the new folder can be named **`micro-os-plus-iii-smp`** 

All builds must use **CMake**, with Micro-OS-Plus-III provided as an **INTERFACE library**.

`micro-os-plus-iii-smp` must be included in the other builds/links as an **INTERFACE library**, directly from the source tree ( no binnaries).

All scripts (`build`, `load`, `run`, etc.) must use paths **relative to the repository root folder**. No absolute/full paths should be used.

Analyze, and start implemenetaion put questions, if needed 

---

## Status and Completion (2026-09-29)

The project unification has been achieved:
- `micro-os-plus-iii-smp` was rebased on top of `micro-os-plus/micro-os-plus-iii` on branch `smp`.
- All architecture ports are unified as sibling repositories under `micro-os-plus/`:
  - `micro-os-plus-iii` (unified kernel + test matrix)
  - `micro-os-plus-iii-cortexm`
  - `micro-os-plus-iii-aarch32`
  - `micro-os-plus-iii-aarch64`
  - `micro-os-plus-iii-devices`
  - `micro-os-plus-iii-posix-arch`
- Sibling discovery in CMake supports both canonical names and `.git`-suffixed names.
- The original xPack test system is restored in `package.json` with 35+ configurations.
- All tests are migrated, built via CMake as INTERFACE libraries with relative paths, and verified on QEMU and hardware probes.
