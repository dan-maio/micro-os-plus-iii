<style>
/* Optimization for PDF rendering: ensure every major section and PR starts cleanly */
.pr-block {
    page-break-before: always;
}
pre {
    padding: 7px 10px !important;
    margin-bottom: 8px !important;
    margin-top: 4px !important;
    page-break-inside: auto !important;
}
pre code {
    font-size: 6.8pt !important;
    line-height: 1.28 !important;
}
table {
    font-size: 7.5pt !important;
}
th, td {
    padding: 4px 6px !important;
}
</style>

# Rebuilding the SMP Branch from `xpack-development`

## Comprehensive Architectural Analysis, Step-by-Step Implementation Runbook & GitHub Pull Request Blueprint

---

## 1. Executive Summary & The GitHub PR Paradigm

### 1.1 The Genesis & Pitfalls of Monolithic SMP Development
When the multi-core Symmetric Multiprocessing (`smp`) branch was originally developed for µOS++ IIIe, it was implemented as a monolithic, sweeping conversion on top of `xpack-development`. In that initial push, hundreds of disparate changes were introduced simultaneously across multiple git repositories:
1. **Unrelated Single-Core Defect Fixes** (POSIX `dirent.h` ISO C empty struct, double-list iterator semantics, newlib syscall types, memory allocator usable size, steady clock duration 64-bit overflow) were interleaved with multi-core scheduler commits.
2. **Architectural Restructuring** (dissolution of `micro-os-plus-iii-devices`, migrating SoC headers into architecture ports) was commingled with thread management state machines.
3. **Silicon Extensions** (ARM Cortex-M33, Raspberry Pi RP2350, AArch32, and AArch64 ports) were added in large batches alongside test harness modifications.

While the resulting `smp` branch in `~/Work2/micro-os-plus/` achieved full multi-core functionality and passing tests, its commit history is **difficult to review, bisect, cherry-pick, or upstream via standard GitHub Pull Requests**. Upstream maintainers cannot easily audit a 10,000-line diff spanning 7 repositories to verify that uniprocessor behavior remains pristine.

### 1.2 The New Paradigm: Small, Focused, Logically Related Commits
This document establishes the **New SMP Development Procedure**. Under this methodology, the `smp` branch is rebuilt from scratch, starting directly from clean upstream `origin/xpack-development` branches across all repositories.

Every step in this rebuilt history adheres strictly to the **GitHub Pull Request paradigm**:
- **Single-Subject Focus:** Every commit addresses exactly **one** issue, defect, feature, or architectural refactoring. Unrelated changes are never commingled.
- **Independent Reviewability:** Each commit contains its own clear rationale, problem description, failure mode averted, and unified diff that can be reviewed in isolation.
- **Bi-directional Propagation:** Commits developed on the new `smp` branch can be cleanly cherry-picked or opened as isolated Pull Requests targeting `xpack-development`.
- **Test Framework Discipline:** Every commit compiles cleanly and passes the rigorous µOS++ test framework gate (72/72 baseline uniprocessor tests, followed by multi-core suites as capabilities land).

```text
+---------------------------------------------------------------------------------------------------+
|                        THE NEW REBUILD & PROPAGATION PARADIGM                                     |
+---------------------------------------------------------------------------------------------------+
|                                                                                                   |
|  UPSTREAM REPOS (xpack-development) <--------------------+                                        |
|         |                                                |  Clean Cherry-Picks &                  |
|         | git clone & checkout                           |  Focused GitHub PRs                    |
|         v                                                |  (PR #1 .. PR #32)                     |
|  REBUILD WORKSPACE ($WORK)                               |                                        |
|         |                                                |                                        |
|         +---> Phase 0: Dissolve `devices` subtree        |                                        |
|         |                                                |                                        |
|         +---> Phase 1: 22 Single-Core Bugfixes & Hardening (PR #1..#22) --------------------------+
|         |              Gate: 72/72 Uniprocessor tests 100% GREEN                                  |
|         |                                                                                         |
|         +---> Phase 2: Common SMP Scheduler & Host native-smp (PR #23) ---------------------------+
|         |              Gate: unifdef zero-diff + 72/72 baseline + native-smp (3/3)                |
|         |                                                                                         |
|         +---> Phase 3: Semantic Releases & Modern Silicon Ports (PR #24..#27) --------------------+
|         |              Gate: Cortex-M33 (MPS2 AN521 2-core) + RP2350 clean                        |
|         |                                                                                         |
|         +---> Phase 4: Multi-Core FPU Stress & 4-Core Platforms (PR #28..#29) --------------------+
|         |              Gate: fp-switch + test-smp-all (Native, M33, AArch32/64)                   |
|         |                                                                                         |
|         +---> Phase 5: Documentation Suite & Hardware Wiring (PR #30..#32) -----------------------+
|                        Final Parity: 100% Identical to ~/Work2/micro-os-plus/                     |
|                                                                                                   |
+---------------------------------------------------------------------------------------------------+
```

> **Procedure update (Part II, §11–§18):** The rebuild is carried out **only with git commits**. No bash or Python scripts are used: no `scripts/smp/`, no chunk recipes, no stashes and no `git checkout golden -- <files>` lifts. Each commit only modifies or adds files, covers one subject (one fix, one feature, one test, one board, one document), and becomes one GitHub pull request. §11–§18 are the authoritative per-repository commit lists for `micro-os-plus-iii`, `cortexm`, `posix-arch`, `aarch32` and `aarch64`, including the retirement of `devices`. Where §3, §9 and §10 disagree with them, §11–§18 apply.

> **Execution record (Part III, §20–§22):** Part II was executed on 2026-10-06. §20 summarizes every step from `xpack-development` (single CPU) to `smp` (SMP) across all repositories. §21 records the deviations from the plan, the builds, the parity check and the final test results. §22 lists every commit of every repository (kernel, posix-arch, cortexm, aarch32, aarch64, devices) as a pull request: number, head and base branch, SHA, category, stage/theme and subject, plus the cross-repository merge order.

### 1.3 Target Architecture: The Five Clean Repositories & Dissolution of `devices`
In the original architecture, device-specific drivers and SoC registers were segregated into a separate `micro-os-plus-iii-devices` repository. This model introduced unnecessary cross-repository coupling and circular dependencies during multi-core bringup.

In the new architecture-specific model, `micro-os-plus-iii-devices` is **dissolved**. Its SoC and driver contents are permanently folded into their owning architecture repositories:

```text
micro-os-plus-iii/                  (Kernel, portable POSIX I/O, core test framework)
micro-os-plus-iii-cortexm/          (ARMv7-M & ARMv8-M Cortex-M architectures + STM32 / RP2350 SoCs)
micro-os-plus-iii-aarch32/          (ARMv7-A 32-bit architecture + BCM2837 / Raspberry Pi SoCs)
micro-os-plus-iii-aarch64/          (ARMv8-A 64-bit architecture + BCM2837 / Raspberry Pi SoCs)
micro-os-plus-iii-posix-arch/       (Host POSIX architecture + native uniprocessor & native-smp ports)
```

Compatibility shims (`micro-os-plus::devices` CMake ALIAS targets) ensure that existing external projects referencing the legacy target continue to configure and link without modification.

**Crucial Architecture Decision:** Following the dissolution of its contents into the respective architecture repositories, the `micro-os-plus-iii-devices` Git repository and folder are **permanently deleted and eliminated** from the active workspace. The final ecosystem consists strictly of the five primary architecture and kernel repositories.

---

<div class="pr-block"></div>

## 2. Repository Architecture & Workspace Bootstrap Procedure

### 2.1 Workspace Directory Layout
Rebuilding the SMP branch cleanly requires an isolated workspace folder (`$WORK`), distinct from the reference workspace in `~/Work2/micro-os-plus/`.

```bash
# Recommended workspace setup
export WORK="/home/dan/Work2/micro-os-plus-rebuild"
mkdir -p "$WORK" && cd "$WORK"
```

The workspace contains the five primary active repositories, plus the legacy `devices` repository used strictly during Phase 0:

| Directory | Repository Name | Initial Branch | Role in Rebuild |
|---|---|---|---|
| `$WORK/micro-os-plus-iii` | `micro-os-plus-iii` | `xpack-development` | Kernel, schedulers, POSIX I/O, test suites |
| `$WORK/micro-os-plus-iii-cortexm` | `micro-os-plus-iii-cortexm` | `xpack-development` | Cortex-M0/M3/M4/M7 baseline + M33/RP2350 SMP |
| `$WORK/micro-os-plus-iii-posix-arch` | `micro-os-plus-iii-posix-arch` | `xpack-development` | Host POSIX uniprocessor + dual-core `native-smp` |
| `$WORK/micro-os-plus-iii-aarch32` | `micro-os-plus-iii-aarch32` | `xpack-development` | ARMv7-A 32-bit Cortex-A multi-core port |
| `$WORK/micro-os-plus-iii-aarch64` | `micro-os-plus-iii-aarch64` | `xpack-development` | ARMv8-A 64-bit Cortex-A multi-core port |
| `$WORK/micro-os-plus-iii-devices` | `micro-os-plus-iii-devices` | `smp` / `master` | Temporary source for Phase 0 subtree migration (permanently deleted after dissolution) |

### 2.2 Cloning Repositories & Branch Topology
All repositories are cloned from their canonical remotes. The clean baseline is checked out, and a dedicated rebuild branch (named `smp-rebuild` or `smp`) is created:

```bash
cd "$WORK"

# 1. Clone the core repositories
git clone https://github.com/micro-os-plus/micro-os-plus-iii.git
git clone https://github.com/micro-os-plus/micro-os-plus-iii-cortexm.git
git clone https://github.com/micro-os-plus/micro-os-plus-iii-posix-arch.git
git clone https://github.com/micro-os-plus/micro-os-plus-iii-aarch32.git
git clone https://github.com/micro-os-plus/micro-os-plus-iii-aarch64.git
git clone https://github.com/micro-os-plus/micro-os-plus-iii-devices.git

# 2. Add local reference remotes pointing to golden source in ~/Work2/micro-os-plus/
for repo in micro-os-plus-iii micro-os-plus-iii-cortexm micro-os-plus-iii-posix-arch \
            micro-os-plus-iii-aarch32 micro-os-plus-iii-aarch64; do
  cd "$WORK/$repo"
  git remote add golden "/home/dan/Work2/micro-os-plus/$repo"
  git fetch golden
  git checkout -b smp origin/xpack-development
done
```

### 2.3 Toolchain Verification (`check-env.sh`)
Before applying changes, verify that the environment has all required native and cross-compilers, debuggers, QEMU emulators, and build utilities:

```bash
cd "$WORK/micro-os-plus-iii"
# Execute environment checker
bash scripts/smp/check-env.sh
```

Required toolchain components:
- **Build Tools:** CMake $\ge 3.20$, Ninja $\ge 1.10$, xPacks Package Manager (`xpm`) $\ge 0.14$.
- **Host Compilers:** GCC 11, 12, 13, or 14; Clang 16, 17, 18, or 19.
- **Cross Toolchains:** `arm-none-eabi-gcc` $\ge 12.3$, `aarch64-none-elf-gcc` $\ge 12.3$.
- **Emulators:** `qemu-system-arm` $\ge 7.0$ (supporting `mps2-an521`, `raspi3b`), `qemu-system-aarch64` $\ge 7.0$.
- **Utilities:** `unifdef` (for single-core projection verification), Python 3 with `pypdf`, `weasyprint`, and `markdown`.

### 2.4 Development Linking Protocol (`xpm link`)
In the µOS++ development workflow, repositories locate each other via `xpm link`. This ensures that local edits in architecture ports are immediately picked up when compiling kernel test suites:

```bash
# Register port development links
cd "$WORK/micro-os-plus-iii-posix-arch" && xpm install && xpm link
cd "$WORK/micro-os-plus-iii-cortexm" && xpm install && xpm link
cd "$WORK/micro-os-plus-iii-aarch32" && xpm install && xpm link
cd "$WORK/micro-os-plus-iii-aarch64" && xpm install && xpm link

# Link into the kernel test harness
cd "$WORK/micro-os-plus-iii"
xpm link @micro-os-plus/cortexm
xpm link @micro-os-plus/posix-arch
```

### 2.5 The Test Framework Paradigm of `micro-os-plus-iii`
The test paradigm in µOS++ IIIe is strictly structured:
1. **The 72-Test Baseline Matrix:** Comprises 24 distinct build configurations (combining native Linux GCC/Clang with Cortex-M0, M3, M4, M7 cross-compilations) each executing three standardized suites:
   - `rtos-apis-test`: Comprehensive functional validation of all POSIX and RTOS primitives.
   - `mutex-stress-test`: High-contention lock/unlock concurrency verification.
   - `cmsis-os-validator-test`: ARM official CMSIS-RTOS validation suite (60/60 test cases).
   - **Baseline Invariant:** At *every commit* in Phase 1, `xpm run test-all` must produce 72/72 PASS (100% green).
2. **The Multi-Core SMP Test Matrix (`test-smp-all`):**
   - `test-native-smp`: Real dual-core host execution using pthreads-as-cores and signal-based IPIs.
   - `test-2xcortex-m33-cmake`: Dual-core ARMv8-M execution on QEMU `mps2-an521`.
   - `test-aarch32-rpi3b`: 4-core ARMv7-A execution on QEMU `raspi3b`.
   - `test-aarch64-rpi3b`: 4-core ARMv8-A execution on QEMU `raspi3b`.
   - `fp-switch`: Floating-point register corruption stress test under aggressive preemption.

---

<div class="pr-block"></div>

## 3. Phase 0: Pre-Migration Subtree Dissolution of Legacy `devices`

### 3.1 Why the `devices` Repository Must Disappear
The legacy `micro-os-plus-iii-devices` repository isolated silicon device drivers (`soc/stm32f4xx`, `soc/rp2350`, `soc/bcm2837`) outside their corresponding CPU architecture repositories. This caused:
- Split architectural headers: Cortex-M33 register definitions lived in `cortexm`, but RP2350 SIO spinlocks lived in `devices`.
- Multi-repository synchronization locks: Modifying an interrupt controller required coordinated commits across two repositories before tests could build.
- Divergence from upstream xPack distribution packaging.

By folding device support directly into `cortexm`, `posix-arch`, `aarch32`, and `aarch64`, each architecture repository becomes a complete, self-contained hardware abstraction layer.

### 3.2 History-Preserving `git subtree` Extraction Protocol
Dissolution must **not** be performed via flat file copying; commit history must be 100% preserved. This is achieved using `git subtree add`:

```bash
cd "$WORK/micro-os-plus-iii-cortexm"

# Subtree add Cortex-M silicon devices from devices repo
git subtree add --prefix=devices "$WORK/micro-os-plus-iii-devices" master

# Restructure into standard architecture directories
mv devices/soc/stm32f4xx soc/stm32f4xx
mv devices/soc/rp2350 soc/rp2350
mv devices/drivers drivers
rm -rf devices

git add soc drivers
git commit -m "refactor(devices): fold Cortex-M SoC and drivers subtree into cortexm port"
```

The identical procedure is executed for `posix-arch` (folding `soc/native`), `aarch32` (folding `soc/bcm2837`), and `aarch64`.

### 3.3 CMake Target Realignment & Removal of `UOS_DEVICES_DIR`
Prior to dissolution, both `posix-arch` and `cortexm` expected an external sibling `micro-os-plus-iii-devices` directory and contained the following legacy boilerplate in their root `CMakeLists.txt`:

```cmake
set (UOS_DEVICES_DIR "${_uos_siblings}/micro-os-plus-iii-devices"
     CACHE PATH "µOS++ III devices working copy")

foreach (_dep_var IN ITEMS UOS_SMP_DIR UOS_DEVICES_DIR)
  ...
  if (NOT EXISTS "${${_dep_var}}/CMakeLists.txt")
    message (FATAL_ERROR "Cannot find the ${_repo} repository at ${${_dep_var}}...")
  endif ()
endforeach ()

add_subdirectory ("${UOS_DEVICES_DIR}" micro-os-plus-iii-devices)
```

If left unchanged after `micro-os-plus-iii-devices` is deleted, any subsequent CMake configure or test command fails immediately with:
```text
CMake Error at /tmp/micro-os-plus-iii-posix-arch/CMakeLists.txt:
  Cannot find the devices repository at /tmp/micro-os-plus-iii-devices.
```

#### Realignment in `micro-os-plus-iii-posix-arch/CMakeLists.txt`
1. Remove `UOS_DEVICES_DIR` and its validation loop from the dependency checks.
2. Define the local block device and filesystem targets directly using the absorbed `drivers/` and `soc/native/` files:

```cmake
# Dissolved devices support: hostfile block device and flatfs
if (NOT TARGET micro-os-plus::devices-hostfile)
  add_library (micro-os-plus-iii-devices-hostfile-interface INTERFACE)
  target_include_directories (
    micro-os-plus-iii-devices-hostfile-interface
    INTERFACE
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/include"
      "${CMAKE_CURRENT_SOURCE_DIR}/soc/native/include"
  )
  target_compile_definitions (
    micro-os-plus-iii-devices-hostfile-interface INTERFACE SD_BACKEND_HOSTFILE
  )
  target_sources (
    micro-os-plus-iii-devices-hostfile-interface
    INTERFACE
      "${CMAKE_CURRENT_SOURCE_DIR}/soc/native/src/sd_hostfile.cpp"
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/src/flatfs.cpp"
  )
  add_library (micro-os-plus::devices-hostfile ALIAS
               micro-os-plus-iii-devices-hostfile-interface)
endif ()

# Compatibility alias for full devices suite (FatFs + block device)
if (NOT TARGET micro-os-plus::devices)
  add_library (micro-os-plus-iii-devices-interface INTERFACE)
  target_include_directories (
    micro-os-plus-iii-devices-interface
    INTERFACE
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/include"
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/fatfs"
  )
  target_sources (
    micro-os-plus-iii-devices-interface
    INTERFACE
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/src/sd.cpp"
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/src/flatfs.cpp"
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/src/usb_dwc2.cpp"
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/fatfs/ff.c"
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/fatfs/diskio_sd.cpp"
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/fatfs/fatfs_hw.cpp"
  )
  add_library (micro-os-plus::devices ALIAS micro-os-plus-iii-devices-interface)
endif ()
```

#### Realignment in `micro-os-plus-iii-cortexm/CMakeLists.txt`
1. Remove `UOS_DEVICES_DIR` and its validation loop from the dependency checks.
2. Define the local STM32F4xx and RP2350 silicon support targets directly using the absorbed `soc/` files:

```cmake
# Dissolved SoC targets: STM32F4xx and RP2350
if (NOT TARGET micro-os-plus::soc-stm32f411xe)
  add_library (micro-os-plus-iii-soc-stm32f4xx-common-interface INTERFACE)
  target_include_directories (
    micro-os-plus-iii-soc-stm32f4xx-common-interface
    INTERFACE
      "${CMAKE_CURRENT_SOURCE_DIR}/soc/stm32f4xx/include"
      "${CMAKE_CURRENT_SOURCE_DIR}/soc/stm32f4xx/include/cmsis"
  )
  target_sources (
    micro-os-plus-iii-soc-stm32f4xx-common-interface
    INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/soc/stm32f4xx/src/system_stm32f4xx.c"
  )

  add_library (micro-os-plus-iii-soc-stm32f411xe-interface INTERFACE)
  target_link_libraries (
    micro-os-plus-iii-soc-stm32f411xe-interface
    INTERFACE micro-os-plus-iii-soc-stm32f4xx-common-interface
  )
  target_sources (
    micro-os-plus-iii-soc-stm32f411xe-interface
    INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/soc/stm32f4xx/src/vectors_stm32f411xe.c"
  )
  add_library (micro-os-plus::soc-stm32f411xe
               ALIAS micro-os-plus-iii-soc-stm32f411xe-interface)

  add_library (micro-os-plus-iii-soc-stm32f412rx-interface INTERFACE)
  target_link_libraries (
    micro-os-plus-iii-soc-stm32f412rx-interface
    INTERFACE micro-os-plus-iii-soc-stm32f4xx-common-interface
  )
  target_sources (
    micro-os-plus-iii-soc-stm32f412rx-interface
    INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/soc/stm32f4xx/src/vectors_stm32f412rx.c"
  )
  add_library (micro-os-plus::soc-stm32f412rx
               ALIAS micro-os-plus-iii-soc-stm32f412rx-interface)
endif ()

if (NOT TARGET micro-os-plus::soc-rp2350)
  add_library (micro-os-plus-iii-soc-rp2350-interface INTERFACE)
  target_include_directories (
    micro-os-plus-iii-soc-rp2350-interface
    INTERFACE
      "${CMAKE_CURRENT_SOURCE_DIR}/soc/rp2350/include"
      "${CMAKE_CURRENT_SOURCE_DIR}/soc/rp2350/include/cmsis"
  )
  target_sources (
    micro-os-plus-iii-soc-rp2350-interface
    INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/soc/rp2350/src/system_rp2350.c"
  )
  add_library (micro-os-plus::soc-rp2350
               ALIAS micro-os-plus-iii-soc-rp2350-interface)
endif ()
```

#### Realignment in `aarch32` and `aarch64`
Both `micro-os-plus-iii-aarch32/CMakeLists.txt` and `micro-os-plus-iii-aarch64/CMakeLists.txt` compile the dissolved `soc/bcm2837` sources locally into `micro-os-plus::aarch32` and `micro-os-plus::aarch64` interface targets, with zero external dependency on `devices`.

Furthermore, following the dissolution of `micro-os-plus-iii-devices`, tests exercising the SD host (`sd_test`, `smp-mat-sdcard-test`), USB controller (`usb_test`), and file systems require the `micro-os-plus::devices` target. Both AArch32 and AArch64 declare this target locally from their absorbed `drivers/` and `soc/` trees:

```cmake
# Dissolved devices support: SD host, USB, and FatFs stack
if (NOT TARGET micro-os-plus::devices)
  add_library (micro-os-plus-iii-devices-interface INTERFACE)
  target_include_directories (
    micro-os-plus-iii-devices-interface
    INTERFACE
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/include"
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/fatfs"
  )
  target_sources (
    micro-os-plus-iii-devices-interface
    INTERFACE
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/src/sd.cpp"
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/src/flatfs.cpp"
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/src/usb_dwc2.cpp"
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/fatfs/ff.c"
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/fatfs/diskio_sd.cpp"
      "${CMAKE_CURRENT_SOURCE_DIR}/drivers/fatfs/fatfs_hw.cpp"
  )
  add_library (micro-os-plus::devices ALIAS micro-os-plus-iii-devices-interface)
endif ()
```

#### Duplicate Port Target Prevention in Platform Harness
In the µOS++ test framework (`tests/cmake/tests-main.cmake`), the architecture port under test is added directly via `add_subdirectory ("${UOS_<PORT>_DIR}" "port-bin")`. Therefore:
- The architecture port (`micro-os-plus-iii-aarch32` or `micro-os-plus-iii-aarch64`) must **never** be listed in `dependencies-folders.cmake` (`xpack_dependencies_folders`).
- Listing the port in `dependencies-folders.cmake` causes CMake policy `CMP0002` violations (`add_library cannot create target ... because another target with the same name already exists`).
- Platforms list only test suite directories and portable xPacks (`mutex-stress`, `rtos-apis`, `arm-cmsis-rtos-validator`, `chan-fatfs`) in `dependencies-folders.cmake`.

#### Shared Test Support Scaffolding Realignment (`test_smpl` $\rightarrow$ `tests/smp-support`)
When the shared test scaffolding was consolidated into `tests/smp-support/` (`hw_result.hpp` and `board-contract.cpp`):
- `micro-os-plus::test-support` in `micro-os-plus-iii/CMakeLists.txt` exposes `${CMAKE_CURRENT_SOURCE_DIR}/tests/smp-support/include` (with a fallback to `test_smpl/include`).
- A backwards-compatibility symlink `test_smpl -> tests/smp-support` is maintained in the root of `micro-os-plus-iii` so that legacy test runners (`run-hw.sh`, `run-host.sh`, `run-qemu.sh`) and scripts referencing `$SMP_DIR/test_smpl/` execute without error.

### 3.4 Phase 0 Verification Gate
```bash
# Verify all existing uniprocessor boards configure and build cleanly
cd "$WORK/micro-os-plus-iii"
xpm run test-all # Must remain 72/72 PASS
```

### 3.5 Permanent Deletion of the Legacy `devices` Repository and Working Directory
Once the subtree extraction into `cortexm`, `posix-arch`, `aarch32`, and `aarch64` is complete and verified, the `micro-os-plus-iii-devices` repository and working directory have fulfilled their transitional purpose.

The `micro-os-plus-iii-devices` Git clone/directory must be **permanently deleted from the active workspace**:

```bash
# Permanently delete the dissolved devices repository clone from the workspace
rm -rf "$WORK/micro-os-plus-iii-devices"
```

**Key Architectural Rules Post-Deletion:**
1. **Zero External Device Dependency:** No architecture repository or kernel build configuration may reference or depend on an external `micro-os-plus-iii-devices` directory.
2. **Self-Contained Ports:** Silicon drivers (`soc/*`) and neutral drivers (`drivers/*`) are compiled and maintained directly inside each architecture repository (`cortexm`, `posix-arch`, `aarch32`, `aarch64`).
3. **Retired Repository:** The standalone `micro-os-plus-iii-devices` repository is officially retired and archived; it is never propagated into future `xpack-development` or `smp` deployment cycles.

---

<div class="pr-block"></div>

## 4. Phase 1: Single-Core Defect Corrections & Hardening (PR #1 through PR #22)

Phase 1 isolates all bugfixes, standard conformance corrections, and allocator hardening that are **pure uniprocessor improvements**. Landing these 22 commits first guarantees that single-core µOS++ is completely defect-free before any multi-core scheduling logic is introduced.

### Summary Table of Phase 1 Pull Requests

| PR # | Subject / Theme | File(s) Touched | Problem & Failure Mode Averted | Verification Gate |
|---|---|---|---|---|
| **#1** | POSIX `dirent.h` ISO C Conformance | `include/cmsis-plus/posix/dirent.h` | Empty struct `typedef struct { ; } DIR;` violates ISO C99/C11 §6.7.2.1; triggers `-Wextra-semi`. | 72/72 pass; clean `-Wextra-semi` |
| **#2** | List Iterator Access Semantics | `include/cmsis-plus/utils/lists.h` | `node_->next` accessed as data member instead of method `node_->next()`, breaking C++17/20 concepts. | 72/72 pass; template concepts clean |
| **#3** | Newlib Syscall Return Types | `posix-io/c-syscalls-aliases-standard.h` | Newlib 64-bit uses `_READ_WRITE_RETURN_TYPE` (`int` or `_ssize_t`), causing conflicting weak alias signatures. | 72/72 pass; reentrant tests clean |
| **#4** | Export Thread Suspend Symbol | `src/rtos/os-thread.cpp` | Out-of-line `inline void suspend()` prevented symbol emission; undefined reference in C API wrapper. | 72/72 pass; wrapper links cleanly |
| **#5** | Memory Allocator Usable Size | `os-memory.*`, `malloc.cpp`, `first-fit-top.*` | Missing `do_usable_size()` broke `realloc()`; `calloc()` lacked multiplication overflow checks. | 72/72 pass; usable size verified |
| **#6** | C++17 Aligned Allocation | `src/libcpp/new.cpp` | Missing standard `operator new/delete(align_val_t)` overloads for over-aligned types. | 72/72 pass; aligned new clean |
| **#7** | Static Error Category Storage | `src/libcpp/system-error.cpp` | Temporary category objects left dangling pointers inside `throw std::system_error`. | 72/72 pass; static lifetime clean |
| **#8** | Chrono 64-Bit Duration Overflow | `src/libcpp/chrono.cpp` | `cycles * 1e9 / freq` overflowed 64-bit int after ~13 minutes. Decompose into seconds and remainder. | 72/72 pass; chrono math overflow-free |
| **#9** | CMSIS-RTOS C Wrapper Cleanups | `src/rtos/os-c-wrapper.cpp` | Default timer must be one-shot; polymorphic mutex delete; cast `millisec` to `uint64_t` prior to `* 1000`. | 72/72 pass; validator 60/60 clean |
| **#10** | POSIX I/O FD Table Mutexing | `src/posix-io/file-descriptors-manager.cpp` | Unprotected descriptor table corrupted under concurrent multi-threaded `open()`/`close()`. | 72/72 pass; concurrent I/O stress pass |
| **#11** | POSIX I/O Deferred List Locking | `posix-io/file-system.h`, `net-stack.h` | Concurrent recycling of deferred file/socket nodes caused corrupted intrusive list links. | 72/72 pass; list recycling clean |
| **#12** | Block Device Sector Size Check | `src/posix-io/block-device.cpp` | Inverted check in `vfcntl`: tested `!= 0` instead of `== 0`, falsely rejecting valid block devices. | 72/72 pass; valid block size returned |
| **#13** | ARMv8-M Semihosting Traps | `include/cmsis-plus/arm/semihosting.h` | Missing `__ARM_ARCH_8M_MAIN__` macro guards and `SEMIHOST_TRAP_HLT` support. | 72/72 pass; ARM semihosting pass |
| **#14** | ARMv8-M Exception Handlers | `src/startup/exception-handlers.c` | SCB register setup and fault dump routines lacked `__ARM_ARCH_8M_MAIN__` guards. | 72/72 pass; fault handlers compile |
| **#15** | Semihosting `fstat()` & Mirror | `src/semihosting/c-syscalls-semihosting.cpp` | Assign `S_IFCHR` only when mode unset; add weak `os_board_console_mirror()` hook. | 72/72 pass; console mirror clean |
| **#16** | Timer Callback Decoupling | `internal/os-lists.cpp`, `os-timer.cpp` | Executing timer callbacks inside critical section caused deadlocks; drift catch-up guard. | 72/72 pass; timer callback mutexes clean |
| **#17** | Mutex Priority Ceiling Protocol | `src/rtos/os-mutex.cpp` | Enforce ceiling before acquiring ownership; track maximum boost among multiple waiters. | 72/72 pass; `mutex-stress-test` pass |
| **#18** | Thread Lifecycle State & Reaper | `os-c-decls.h`, `os-thread.h`, `os-idle.cpp` | Add `state::destroying = 7`; idle thread reaper safely validates no core is running thread before free. | 72/72 pass; thread reaper green |
| **#19** | CondVar Lost-Signal Elimination | `src/rtos/os-condvar.cpp`, `os-condvar.h` | Atomic link node & mutex unlock under `scheduler::critical_section`; bind condvar to clock. | 72/72 pass; condvar concurrency green |
| **#20** | `std::thread` Handle Sync | `thread-cpp.h`, `thread_internal.h` | `thread::join()` waits on native thread handle; retain functor object to eliminate use-after-free. | 72/72 pass; functor lifetime verified |
| **#21** | MQueue Preemptive Reschedule | `src/rtos/os-mqueue.cpp` | Call `port::scheduler::reschedule()` immediately after send/receive wakeups. | 72/72 pass; queue preemption green |
| **#22** | High-Res Clock Port Sync | `os-decls.h`, `os-clocks.cpp`, Port inlines | Declares `has_hardware_counter()`; fast-paths now(); SysTick ICSR pending overflow inspection. | 72/72 pass; ICSR pending fix verified |

---

<div class="pr-block"></div>

## 5. Phase 2: Common Multi-Core SMP Kernel Infrastructure & Host Runtime (PR #23 / Step 14)

### 5.1 Architectural Foundations of the SMP Kernel
Phase 2 constitutes the architectural core of the entire SMP migration. It transitions the kernel from a single-CPU RTOS to a Symmetric Multiprocessing engine capable of executing threads concurrently across $N$ physical cores.

Key data structure transformations in `include/cmsis-plus/rtos/os-sched.h` and `src/rtos/os-core.cpp`:
- **Per-CPU Current Threads:** Replaces scalar `current_thread_` with an array indexed by `port_cpu_id()`:
  ```cpp
  #if defined(OS_USE_SMP_SCHEDULER)
  extern thread* volatile current_thread_[OS_NCPU];
  #else
  extern thread* volatile current_thread_;
  #endif
  ```
- **Per-CPU Ready Lists:** Replaces the monolithic ready list with `ready_list_[OS_NCPU]`, eliminating global queue lock bottlenecking during normal thread execution.
- **Recursive Kernel Spinlock (`_smp_klock`):** Protects scheduler state transitions. Backed by architecture hardware spinlocks (e.g. RP2350 SIO spinlock 0, Cortex-M33 LDREX/STREX, or POSIX mutex).

### 5.2 The 5-Stage Stack Pointer Claim/Publish Protocol
To prevent fatal stack corruption when two cores attempt to switch to or from the same thread simultaneously, the scheduler implements a strict 5-stage handshake:
1. **Claim:** The incoming thread stack pointer is atomically set to `nullptr` on the target core, marking it actively running.
2. **Spill:** The outgoing thread's callee-saved registers are pushed to its current stack.
3. **Switch:** Hardware Stack Pointer register (SP) is updated to the incoming thread's stack.
4. **Publish:** The outgoing thread's saved stack pointer is published to `from->context_.port_.stack_ptr = sp` **only after** state is completely saved.
5. **Restore:** Callee-saved registers are popped from the new stack, and thread execution resumes.

### 5.3 Prohibiting Context Switch While Holding Spinlock
A primary invariant in µOS++ SMP: **A hardware context switch must never be executed while holding `_smp_klock`**.
Context switching while holding the kernel spinlock causes deadlocks across cores. Instead, `internal_switch_threads()` schedules the switch, marks the CPU as requiring rescheduling, releases `_smp_klock`, and allows the architecture PendSV interrupt or signal handler to execute the actual register swap.

### 5.4 Phase 2 Verification Gates
1. **The `unifdef` Single-Core Invariant:**
   Running `unifdef -UOS_USE_SMP_SCHEDULER` on the Phase 2 kernel source must produce a tree that is **100% byte-identical to Step 22**. Uniprocessor builds incur zero code bloat and zero overhead.
2. **72/72 Uniprocessor Test Gate:** `xpm run test-all` passes with 100% green status.
3. **Genuine Dual-Core Host Verification (`native-smp`):**
   Executes `tests/platforms/native-smp/` under Linux host using 2 OS threads as virtual CPU cores:
   ```bash
   cd "$WORK/micro-os-plus-iii/tests"
   xpm run test-native-smp
   # Must execute and pass:
   # 1. rtos-apis-test (dual-core concurrency)
   # 2. mutex-stress-test (contention across cores)
   # 3. cmsis-os-validator-test (60/60 test cases)
   ```

---

<div class="pr-block"></div>

## 6. Phase 3: Semantic Versioning, Port Releases & Silicon Extensions (PR #24 through PR #27)

### 6.1 PR #24: Port Package Semantic Releases
Publishes the formal multi-core hardware abstraction contract:
- `micro-os-plus-iii-posix-arch`: Version bumped from `1.0.1` $\rightarrow$ `1.1.0`.
- `micro-os-plus-iii-cortexm`: Version bumped from `1.1.0` $\rightarrow$ `1.2.0`.
Local semantic git tags (`v1.1.0`, `v1.2.0`) are generated for repeatable downstream dependency resolution.

### 6.2 PR #25: Execution of Devices Subtree Dissolution, CMake Realignment & Repository Deletion
Finalizes the historical merge of `soc/*` and `drivers/*` into the owning architecture ports, establishing clean build targets and permanent ALIAS compatibility shims.

**Key Implementation Actions:**
1. **Subtree Merge:** Folds `soc/stm32f4xx` and `soc/rp2350` into `cortexm`, `soc/native` and `drivers/*` into `posix-arch`, and `soc/bcm2837` into `aarch32`/`aarch64`.
2. **CMakeLists.txt Realignment:**
   - In `posix-arch/CMakeLists.txt`: Remove `UOS_DEVICES_DIR` dependency check. Declare `micro-os-plus::devices-hostfile` (from `soc/native/src/sd_hostfile.cpp` and `drivers/src/flatfs.cpp` with `SD_BACKEND_HOSTFILE`) and `micro-os-plus::devices` directly.
   - In `cortexm/CMakeLists.txt`: Remove `UOS_DEVICES_DIR` dependency check. Declare `micro-os-plus::soc-stm32f411xe`, `micro-os-plus::soc-stm32f412rx`, and `micro-os-plus::soc-rp2350` directly from the local `soc/` paths.
3. **Repository Deletion:** Immediately upon completion of the subtree graft and CMake realignment, the `micro-os-plus-iii-devices` repository folder and Git repository are **permanently deleted from the workspace**, retiring the standalone repository and guaranteeing that all downstream projects build and test 100% self-contained.

### 6.3 PR #26: Modern Multi-Core Silicon Ports (Cortex-M33 & RP2350)
Introduces genuine silicon hardware multi-core implementations:
- **ARM Cortex-M33 Port:** Supports ARMv8-M architecture, Message Handling Unit (MHU) Inter-Processor Interrupts (IPI), and per-core SysTick clocks.
- **Raspberry Pi RP2350 Port:** Implements recursive `_smp_klock` backed by SIO Hardware Spinlock 0 (`*(volatile uint32_t*)(0xD0000100)`), Core 1 wake-up mailbox, and FIFO IRQ 25.
- **Kernel IPI Dispatching:** In `src/rtos/os-thread.cpp`, dispatches wake-up IPIs whenever a thread unblocks on an alternate core (`OS_INTEGER_RTOS_PORT_NCPU > 1`).

### 6.4 PR #27: Modular Add-Only CMake Build Architecture
Splits the monolithic CMake interface into clean, granular sub-targets:
- `micro-os-plus::iii-core`: Bare kernel RTOS engine without POSIX I/O.
- `micro-os-plus::iii-posix-io`: File system, mount tables, and character devices.
- `micro-os-plus::port-smp-decls`: Pure SMP forward declarations for thin ports.
- Adds cross-compilation toolchain profiles (`cmake/toolchains/arm-none-eabi.cmake`, `cmake/toolchains/aarch64-none-elf.cmake`).
- Adds QEMU 2-core platform `tests/platforms/2xcortex-m33/` (`mps2-an521 --cpu cortex-m33 --smp 2`).

---

<div class="pr-block"></div>

## 7. Phase 4: Multi-Core Test Suites, Multi-Arch Platforms & CI Harness (PR #28 & PR #29)

### 7.1 PR #28: Multi-Core FPU Stress Suite & Scaffolding Relocation
- **FPU Context Switch Stress Suite (`tests/sources/fp-switch/`):** 6 threads computing mathematical floating-point series across cores under aggressive 1ms preemptive slicing (3000 ticks). Detects missing hardware FPU lazy-stacking or register corruptions.
- **Scaffolding Relocation:** Moves legacy root `test_smpl/` into `tests/smp-support/`, cleanly exported as `micro-os-plus::test-support` providing standardized test reporting and hardware exit registers.

### 7.2 PR #29: Multi-Architecture 4-Core Platforms & Composite CI Action
- **AArch32 & AArch64 4-Core Platforms:** Implements QEMU `raspi3b` platforms (`tests/platforms/aarch32-rpi3b/`, `tests/platforms/aarch64-rpi3b/`) executing across 4 ARM Cortex-A53 cores.
- **Composite Test Action (`test-smp-all`):** Registered in `tests/package.json`, executing the complete multi-core test matrix in one command:
  ```json
  "test-smp-all": {
    "description": "Run all SMP test suites across Native, Cortex-M33, and AArch32/64",
    "actions": [
      "xpm run test-native-smp",
      "xpm run test-2xcortex-m33-cmake",
      "xpm run test-aarch32-rpi3b",
      "xpm run test-aarch64-rpi3b"
    ]
  }
  ```

---

<div class="pr-block"></div>

## 8. Phase 5: Documentation Suite, Master Reconciliation & Silicon Wiring (PR #30 through PR #32)

### 8.1 PR #30: Comprehensive Documentation & Specification Runbooks Suite
Integrates all architectural runbooks and migration specifications into `docs/render-pdfs.sh`. Builds the complete 16-document PDF publication suite.

### 8.2 PR #31: Final Master Reconciliation & Repository Cleansing
- Merges upstream `origin/xpack-development` cleanly.
- Restores `.github/workflows/ci.yml`, `README.md`, `LICENSE`, and Doxygen templates to be **100% byte-identical** to upstream baseline.
- Purges temporary transition scripts (`scripts/smp/`).

### 8.3 PR #32: Dedicated Raspberry Pi Pico 2 Physical Hardware Platform Wiring
Adds standalone hardware platform `tests/platforms/cortexm-pico2/` enabling direct OpenOCD SWD flashing and UART verification on physical RP2350 silicon. Implements Core 1 secondary boot handshake via SIO mailbox registers (`sio_hw->fifo_wr` / `sio_hw->fifo_rd`).

---

<div class="pr-block"></div>

## 9. Operator's Execution Manual: The Step-by-Step Lifting Loop

> **Superseded.** The script-driven loop below (`new-step.sh`, `chunks/stepNN.sh`, `verify-step.sh`, `advance-step.sh`) is kept only as a historical record. The authoritative procedure is the commit-only cycle in §12. Experience with this loop showed that the recipes mix subjects: a `git checkout golden/smp -- <files>` lift staged the files of PR #2 and PR #3 into the commit for PR #1. The scripts also leave transition tooling in the repository, which then has to be removed again (PR #31).

### 9.1 The Golden 4-Command Development Cycle per Step
For each of the 32 pull requests, the developer executes a standardized four-command loop:

```text
+-------------------+      +-------------------+      +-------------------+      +-------------------+
|  1. NEW STEP      | ---> |  2. APPLY CHUNK   | ---> |  3. VERIFY GATE   | ---> |  4. COMMIT / ADV  |
|  Fork step branch |      |  Lift clean diff  |      |  Compile & Test   |      |  Atomic git commit|
+-------------------+      +-------------------+      +-------------------+      +-------------------+
```

#### Step 1: Fork the Step Branch
```bash
cd "$WORK/micro-os-plus-iii"
# Creates step/NN branched from step/NN-1 (or xpack-development at Step 1)
bash scripts/smp/new-step.sh <NN>
```

#### Step 2: Apply the Step's Isolated Chunk
```bash
# Sourced directly from golden reference repo in ~/Work2/micro-os-plus/
bash scripts/smp/chunks/step<NN>.sh
# Or inspect unified diff:
bash scripts/smp/show-chunk.sh <NN> <file...>
```

#### Step 3: Execute the Verification Gate
```bash
# Validates pristine rules, unifdef projection, and runs 72/72 test matrix
bash scripts/smp/verify-step.sh <NN>
```

#### Step 4: Commit and Advance
```bash
# Creates atomic git commit with conventional commit header
bash scripts/smp/advance-step.sh <NN> "commit message description"
```

### 9.2 Stacking Pull Requests on GitHub
When submitting the 32 steps to GitHub:
1. Push each local step branch: `git push -u origin step/<NN>`.
2. Open Pull Request on GitHub:
   - For PR #1: Target base `xpack-development` $\leftarrow$ Head `step/01`.
   - For PR #2: Target base `step/01` $\leftarrow$ Head `step/02`.
   - For PR #N: Target base `step/<N-1>` $\leftarrow$ Head `step/<N>`.
3. When upstream merges PR #1 into `xpack-development`, use GitHub's web UI to retarget PR #2's base from `step/01` to `xpack-development`.

### 9.3 Cherry-Picking Commits Back into `xpack-development`
Because each commit is strictly self-contained and touches only files relevant to its single theme, any individual commit or group of commits can be cherry-picked directly into `xpack-development`:

```bash
cd "$WORK/micro-os-plus-iii"
git checkout xpack-development
git fetch origin

# Example: Cherry-pick PR #1 (dirent) and PR #2 (lists) directly
git cherry-pick <PR_1_COMMIT_HASH>
git cherry-pick <PR_2_COMMIT_HASH>

# Verify baseline tests remain 100% green
xpm run test-all
```

---

<div class="pr-block"></div>

## 10. Comprehensive Verification Matrix & Acceptance Gates

Every pull request satisfies an explicit, automated acceptance gate prior to being advanced:

| PR ID | Theme & Domain | Repositories | Self-Contained? | Automated Gate Command | Acceptance Pass Criteria |
|---|---|---|---|---|---|
| **PR #1** | POSIX `dirent.h` Conformance | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; `-Wextra-semi` clean |
| **PR #2** | List Iterator Member Semantics | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; template concepts clean |
| **PR #3** | Newlib Syscall Return Types | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; newlib reentrant tests pass |
| **PR #4** | Thread Suspend Symbol Export | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; C wrapper resolves symbol |
| **PR #5** | Memory Allocator Usable Size | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; `malloc_usable_size` verified |
| **PR #6** | C++17 Aligned Allocation | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; aligned `operator new` clean |
| **PR #7** | Static Error Category Storage | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; static storage eliminates dangling ptrs |
| **PR #8** | Steady Clock Duration Overflow | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; chrono math overflow-free |
| **PR #9** | CMSIS-RTOS C Wrapper Cleanups | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; validator (60/60) clean |
| **PR #10** | POSIX I/O FD Table Mutex | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; concurrent I/O stress green |
| **PR #11** | POSIX I/O Deferred List Locking | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; list recycling thread-safe |
| **PR #12** | Block Device Sector Size Check | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; valid block size returned |
| **PR #13** | ARMv8-M Semihosting Traps | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; ARM semihosting tests pass |
| **PR #14** | ARMv8-M Exception Handlers | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; ARMv8-M fault vectors compile |
| **PR #15** | Semihosting `fstat()` & Mirror | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; mode preserved & console mirror hook |
| **PR #16** | Software Timer Decoupling | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; timer callback mutexes clean |
| **PR #17** | Mutex Priority Ceiling | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; `mutex-stress-test` passes |
| **PR #18** | Thread Lifecycle & Reaper | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; dynamic thread reaper green |
| **PR #19** | CondVar Lost-Signal Elimination | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; condvar concurrency stress green |
| **PR #20** | `std::thread` Handle Sync | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; functor closure lifetime verified |
| **PR #21** | MQueue Preemptive Reschedule | Kernel | standalone | `xpm run test-all` | 72/72 tests pass; message queue preemption green |
| **PR #22** | High-Res Clock Port Sync | K + C + P | atomic | `xpm run test-all` | 72/72 tests pass; ICSR pending fix verified |
| **PR #23** | Multi-Core SMP Core & Host | K + C + P | atomic | `scripts/smp/verify-step.sh 14` | `unifdef` zero-diff + 72/72 + `native-smp` (3/3) PASS |
| **PR #24** | Port Semantic Releases | P + C | standalone | `git tag -l` | `v1.1.0` and `v1.2.0` local tags generated |
| **PR #25** | Devices Subtree Dissolution | P + C + Arch | standalone | `xpm run build ...` | Subtree merged; CMake ALIAS targets resolve; `devices` folder deleted from workspace |
| **PR #26** | Modern Silicon Ports | C + K | add-only | `scripts/smp/verify-step.sh 25` | M33/RP2350 port targets compile cleanly |
| **PR #27** | Modular Add-Only CMake | K + C | add-only | `scripts/smp/verify-step.sh 26` | 72/72 baseline + `2xcortex-m33` (4/4) PASS |
| **PR #28** | FPU Context Switch Stress | Kernel | add-only | `scripts/smp/verify-step.sh 27` | `fp-switch` passes on `2xcortex-m33` (4/4) |
| **PR #29** | Multi-Arch 4-Core Platforms | K + A32 + A64 | add-only | `scripts/smp/verify-step.sh 28` | `test-smp-all` passes (Native, M33, AArch) |
| **PR #30** | Documentation Suite | Kernel | standalone | `docs/render-pdfs.sh` | All PDFs compile cleanly without warnings |
| **PR #31** | Final Merge & Cleansing | All Repos | clean-merge | `bash scripts/smp/finalize.sh` | Upstream CI metadata 100% byte-identical |
| **PR #32** | Pico 2 Hardware Platform | K + C | add-only | `xpm run build --config cortexm-pico2` | Pico 2 platform compiles for hardware SWD |

### 10.2 Final Parity Verification with Golden Source
At the conclusion of Step 32:
- The rebuilt `smp` branch in `$WORK/micro-os-plus-iii` is compared against `/home/dan/Work2/micro-os-plus/micro-os-plus-iii`:
  ```bash
  diff -ruN -x ".git" "$WORK/micro-os-plus-iii" "/home/dan/Work2/micro-os-plus/micro-os-plus-iii"
  ```
- **Acceptance Invariant:** The source code trees across all five repositories (`micro-os-plus-iii`, `cortexm`, `posix-arch`, `aarch32`, `aarch64`) achieve **100% functional and structural parity** with the reference implementation in `~/Work2/micro-os-plus/`, but possess a **clean, granular, 32-commit GitHub Pull Request history** ready for immediate upstream integration.

---

<div class="pr-block"></div>

# Part II — Commit-Only Migration Procedure (Authoritative)

## 11. Principles: Only Commits, One Subject per Commit, No Scripts

### 11.1 Why Part I's script loop is replaced
Part I (§9) drives the rebuild with `scripts/smp/*.sh` and `chunks/stepNN.sh` recipes. A dry run on clean clones of `github.com/dan-maio/*` showed three structural problems with it:

1. **Recipes mix subjects.** A recipe lifts whole files with `git checkout golden/smp -- <files>`. When that happens, the lift *stages* every lifted file. Step 01's recipe staged `lists.h` (PR #2) and `c-syscalls-aliases-standard.h` (PR #3) into the commit for PR #1, so the commit no longer matched its PR.
2. **The tooling becomes part of the history.** `scripts/smp/`, its chunks and their `__pycache__` are committed, and later have to be removed again (PR #31). A GitHub reviewer sees tooling churn that has nothing to do with the kernel.
3. **A step's result is not reviewable before it exists.** What lands is whatever the script produced at run time. A reviewer cannot read a recipe and know the exact resulting diff.

**Decision:** the rebuild uses **git commits only**. Every commit is written as the pull request it will become: one subject, a self-contained message, and a diff that is reviewable on its own. The procedure needs no shell or Python script. The only commands are `git` (including the interactive hunk selection built into git) and `xpm` (the µOS++ test framework).

### 11.2 The ten rules
| # | Rule | Consequence |
|---|---|---|
| R1 | **One subject per commit**: one correction, one feature, one test, one board, one platform, or one document. | A file touched by several subjects is lifted hunk by hunk (`git checkout -p`, §12.2), never whole. |
| R2 | **A commit only modifies or adds files.** It never deletes or renames an upstream file. | Golden's deletions (`.github/`, `doxygen/`, `inspiration/`, `templates/`, `.vscode/`, `.settings/`, `CHANGELOG.md`, `README*.md`, `LICENSE`→`LICENSE-micro-os-plus-iii`, `package-lock.json`, `CLAUDE.md`, arch `.npmignore`/`LICENSE`/`README.md`, posix-arch `test/trace-*`) are **not reproduced**. PR #31's "restore to upstream" therefore has nothing to do. |
| R3 | **No procedure tooling is committed.** | `scripts/smp/**` and `tests/xpacks/**` (installed packages, created by `xpm install`) are never committed. |
| R4 | **Product files may be shell, procedure files may not.** | Test runners that `ctest` executes (`test_smpl/run-{host,qemu,hw}.sh`, `test/boards/*/hw.sh`, `test/qemu.sh`, `test/boards/native/run.sh`) are product files. They are committed with the test infrastructure that calls them. |
| R5 | **A fix to code that this series introduces is folded into the commit that introduces that code.** | No PR ships a known bug that a later PR repairs. Fixes to *upstream* code are separate commits (the Phase 1 corrections). |
| R6 | **The provider lands before the consumer.** | A port symbol lands before the kernel code that calls it, and kernel declarations land before port code that implements them. When neither order compiles alone, the commits form a **group**. The gate runs at the group's last commit, and every message in the group names the group (`Group: G-hrclock`). |
| R7 | **Every commit compiles in the single-core configurations.** | New SMP code sits under `#if defined(OS_USE_SMP_SCHEDULER)`. `unifdef -UOS_USE_SMP_SCHEDULER` of any SMP commit gives the tree of its parent. |
| R8 | **New build files grow with their sources.** | A commit that adds a `.cpp` also adds its line to the port's `CMakeLists.txt`. No commit lists a file that does not exist yet. |
| R9 | **Tests are added one per commit.** | The port test builders (`test/CMakeLists.txt`) and the kernel platforms register *every directory present* under `test/<board>/`. One new test directory therefore equals one commit and one new `ctest` entry. |
| R10 | **Every gate is an `xpm` action of the µOS++ test framework.** | §13.3. No ad-hoc gate script exists. |

### 11.3 Corrections to Part I, checked against the golden `smp` branches
These facts were read from `~/Work2/micro-os-plus/*` (`xpack-development..smp`, read-only):

| Part I says | Golden `smp` actually has | Part II rule |
|---|---|---|
| Clone from `github.com/micro-os-plus/*` (§2.2) | Fork `github.com/dan-maio/*`. On aarch64, local `xpack-development` is `366c957` but GitHub `origin/xpack-development` is `fe904c0`. | Clone from `dan-maio`. Before starting, compare the aarch64 base with `git log --oneline 366c957...fe904c0` and record which one was used. |
| `xpm link @micro-os-plus/cortexm` (§2.4) | The package names are `@micro-os-plus/micro-os-plus-iii-{posix-arch,cortexm,aarch32,aarch64}`. | Link them per configuration through `xpm run install --config <cfg>`; each `*-actions` configuration already runs `xpm link`. Do not use `link-deps-all`: it aborts on `@micro-os-plus/build-helper`. |
| `tests/platforms/native-smp/`, `test-native-smp` (§5.4) | No such platform. `tests/platforms/native` builds and runs posix-arch's own `test/native/*` (rtos-apis, mutex-stress, flatfs, mutex-ceiling, smp-*) through `test_smpl/run-host.sh`. | Native SMP tests are posix-arch test directories (§16.3). They run under `xpm run test-native-cmake`. |
| `test-smp-all` action (§7.2) | The action is `test-smp-cmake`, and it is part of `test-all` (`native` + `cortex` + `smp`). | The first SMP platform commit creates `test-smp-cmake` and adds it to `test-all`. Each later platform commit appends one line to it (§15.6). |
| `test_smpl/` → `tests/smp-support/` plus a symlink (§3.3, §7.1) | `test_smpl/` is a real directory at the kernel root, and the platforms reference `../test_smpl`. | `test_smpl/` is added as is (K-H5*). No relocation, no symlink. |
| Release bumps posix-arch 1.1.0, cortexm 1.2.0 (§6.1) | `package.json` versions are unchanged: posix-arch 1.0.1, cortexm 1.1.0, aarch32/64 0.1.0. | A version bump is an optional last commit per port (`chore(release)`), made only when publishing. |
| PR #25 = devices dissolution (§6.2) | This is the same work as Phase 0. | Done once, as stage S0 (§14). |
| PR #23 must be one atomic K+C+P commit (§5, files-modif-by-step) | The kernel SMP code is guarded (R7), so single-core builds do not see it. | It is split into themed commits per repository (§15.3, §16.2, §17.2). SMP builds are expected to be green only at the end of stage S2, which is the S2 gate. |
| Final parity is "100% identical" (§10.2) | Identity is impossible by design: R2/R3 keep upstream files that golden deletes, and the arch repos gain `soc/`, `drivers/` that golden only references. | The parity check lists the **intended differences** (§19.2). Every other difference is a defect. |
| `devices` subtree is added under `devices/` and then moved (§3.2) | The devices repository (`github/smp` = `e8e39d5`) has `include/`, `src/`, `fatfs/` and `soc/<chip>/` at its top level. | It is imported with plain add commits into `drivers/include`, `drivers/src`, `drivers/fatfs`, `soc/<chip>` (§14). |

---

## 12. The Commit Cycle (Manual, No Scripts)

### 12.1 Workspace
```bash
export WORK=/tmp                    # or any empty directory
cd "$WORK"
for r in micro-os-plus-iii micro-os-plus-iii-cortexm micro-os-plus-iii-posix-arch \
         micro-os-plus-iii-aarch32 micro-os-plus-iii-aarch64 micro-os-plus-iii-devices; do
  git clone https://github.com/dan-maio/$r.git
done
for r in micro-os-plus-iii micro-os-plus-iii-cortexm micro-os-plus-iii-posix-arch \
         micro-os-plus-iii-aarch32 micro-os-plus-iii-aarch64; do
  git -C "$WORK/$r" remote add golden "$HOME/Work2/micro-os-plus/$r"   # read-only reference
  git -C "$WORK/$r" fetch golden smp                                   # fetch runs in $WORK, not in golden
  git -C "$WORK/$r" switch -c smp origin/xpack-development
done
```
The golden repositories are **only read**. Every write (`fetch`, `switch`, `commit`) runs in `$WORK`.

### 12.2 Building one commit: four git-native ways to lift content
| Need | Command | Note |
|---|---|---|
| New file, whole | `git checkout golden/smp -- <path>` | Then `git restore --staged <path>` if other paths are staged. Commit with an explicit path list (step 3 below). |
| Part of a modified file | `git checkout -p golden/smp -- <path>` | Interactive: answer `y` only for the hunks of this commit's subject. |
| Hunk needs editing (two subjects in one hunk) | `git checkout -p` then `e` | Or edit in the editor. The diff to golden for the remaining subject stays visible with `git diff golden/smp -- <path>`. |
| Content from the devices repository | `git -C ../micro-os-plus-iii-devices show e8e39d5:<path> > <new path>` | Or `git read-tree --prefix=soc/rp2350/ -u <tree-ish>` after fetching devices as a remote (§14.2). |

### 12.3 The per-commit cycle
```text
 1. BRANCH     git switch -c pr/<ID>-<slug>            (stacked on the previous pr/ branch)
 2. LIFT       one subject only (§12.2)
 3. COMMIT     git add <exact paths> && git commit      (message template §12.4)
 4. GATE       xpm action(s) of the commit's stage (§13.3); a red gate is fixed by amending, never by a follow-up
 5. TAG        git tag pr-<ID>                          (optional, for bookkeeping)
```

### 12.4 Commit message template
```text
<type>(<scope>): <imperative summary, at most 72 chars>

Problem:   what is wrong or missing in xpack-development
Failure:   the visible symptom (error text, wrong result, hang)
Change:    what this commit does, file by file if more than one
Scope:     single-core | SMP-guarded | test | build | docs
Gate:      xpm run <action>  ->  <N>/<N> passed
Group:     <group name>                    (only for R6 groups)
Source:    golden smp <short sha or subject> | devices@e8e39d5:<path>
Legacy:    PR #<n> of Part I              (when it maps to one)

Co-Authored-By: ...
```
`type` is one of `fix`, `feat`, `test`, `build`, `docs`, `chore`, `refactor`.

### 12.5 From commits to pull requests
Each commit is on its own `pr/<ID>-<slug>` branch, stacked on the previous one in the same repository. A PR targets `xpack-development` for the first commit and the previous `pr/` branch for the others (as in §9.2). After a merge, the next PR is retargeted. Because of R1, R2 and R7, any Phase 1 commit can also be cherry-picked onto `xpack-development` on its own.

---

## 13. Global Ordering, Stages and Gates

### 13.1 Stages
| Stage | Content | Repositories | Ends with gate |
|---|---|---|---|
| **S0** | Dissolve `devices` into the arch repos, retire `devices` | P, C, A32, A64, D | G0 |
| **S1** | Single-core corrections and improvements (Part I PR #1–#22, plus new ones) | K (+C, P for the hrclock group) | G1 after every commit |
| **S2** | SMP core: kernel SMP, POSIX host SMP, Cortex-M SMP contract | K, P, C | G1 after every commit; G2 at the end |
| **S3** | New silicon and new architectures: M33, RP2350, AArch32, AArch64 ports | C, A32, A64 | Each port commit builds its port library |
| **S4** | Test framework: kernel harness, platforms, port test builders, then **one commit per test** | K, P, C, A32, A64 | G1 + G3 (growing) |
| **S5** | Documentation, one commit per document | K (+ port READMEs) | None (docs only) |
| **S6** | Final parity and the full test run | all | G-final |

### 13.2 Cross-repository order (R6)
```text
S0:  P01-P03 -> C01-C03 -> A32-01..03 -> A64-01..02 -> D01 (retire devices)
S1:  K01 ... K29   (group G-hrclock = K28 + C04 + P04; gate after the last of the three)
S2:  K30-K38 (kernel SMP, guarded) -> P05-P11 (host SMP) -> C05-C07 (Cortex-M SMP contract)
S3:  C08-C12 (M33, RP2350) | A32-04..12 | A64-04..11      (the three columns are independent)
S4:  K40-K47 (harness) -> P20 / C20 / A32-20 / A64-20 (port test builders and boards)
     -> K50.. (one platform per commit) -> one commit per test in each port
S5:  K90..
```

### 13.3 Gates (all of them are xpm actions in `micro-os-plus-iii/tests/package.json`)
Once per workspace:
```bash
cd "$WORK/micro-os-plus-iii-posix-arch" && xpm install && xpm link
cd "$WORK/micro-os-plus-iii-cortexm"    && xpm install && xpm link
cd "$WORK/micro-os-plus-iii-aarch32"    && xpm install && xpm link   # from S3
cd "$WORK/micro-os-plus-iii-aarch64"    && xpm install && xpm link   # from S3
cd "$WORK/micro-os-plus-iii/tests"      && xpm run install-all
```
| Gate | Command (in `micro-os-plus-iii/tests`) | Pass criterion |
|---|---|---|
| **G0** | `xpm run test-native-cmake && xpm run test-cortex-cmake` | Same result as on `xpack-development` plus PR #1. Note that the base is red on `-Werror=extra-semi` in `dirent.h` until K01. |
| **G1** | `xpm run test-native-cmake` + `xpm run test-cortex-cmake` (the two may run in parallel) | 24 configurations × 3 suites = **72/72** with the `xpack-development` harness. After the harness switch (K44–K46), all `ctest` entries of the 24 configurations pass, and the new count is written into the `Gate:` line. |
| **G2** | The G1 commands, then the SMP builds of stage S2 through `xpm run test-native-cmake` (posix-arch `test/native/smp-*` after P21+) | G1 green, and the SMP host tests pass |
| **G3** | `xpm run test-<platform>-cmake` for the platform the commit touches | All non-`hwd` tests of the platform pass (`ctest -LE hwd`) |
| **G-final** | `xpm run test-all` | native + cortex + `test-smp-cmake` all green |
| **Unifdef review** (S2 only, optional) | `git diff HEAD~1 \| unifdef -UOS_USE_SMP_SCHEDULER` (review aid) | No single-core change |

`hwd` tests (real hardware: pico2, weact, nucleo, Raspberry Pi, Luckfox) are built by G3 but run only on a bench, through `xpm run test-<…>-hwd --config <cfg>`. Their result is recorded in the commit message when it is available.

---

## 14. Stage S0 — Dissolving `devices` with Commits Only

### 14.1 Source layout → destination layout
| `devices@e8e39d5` | posix-arch | cortexm | aarch32 | aarch64 |
|---|---|---|---|---|
| `include/` (`sd.hpp`, `flatfs.hpp`, `fatfs_hw.hpp`, `usb_dwc2.hpp`) | `drivers/include/` | — | `drivers/include/` | `drivers/include/` |
| `src/` (`sd.cpp`, `flatfs.cpp`, `usb_dwc2.cpp`) | `drivers/src/` | — | `drivers/src/` | `drivers/src/` |
| `fatfs/` (FatFs R0.15 + `diskio_sd.cpp`, `fatfs_hw.cpp`) | `drivers/fatfs/` | — | `drivers/fatfs/` | `drivers/fatfs/` |
| `soc/native/` | `soc/native/` | — | — | — |
| `soc/stm32f4xx/` | — | `soc/stm32f4xx/` | — | — |
| `soc/rp2350/` | — | `soc/rp2350/` | — | — |
| `soc/bcm2837/` | — | — | `soc/bcm2837/` | `soc/bcm2837/` |
| `soc/rk3506/` (+ `sdcard.md`) | — | — | `soc/rk3506/` | — |

### 14.2 Commit list
To import without scripts, use `git fetch ../micro-os-plus-iii-devices smp:devices-src` once per arch repo, then `git read-tree --prefix=<dest>/ -u devices-src:<src>` for each row. This only stages the added files; commit each one separately. The branch `devices-src` is local and is deleted after S0.

| ID | Repo | Commit | Files | Gate |
|---|---|---|---|---|
| P01 | posix-arch | `feat(drivers): import the neutral SD, flatfs, USB and FatFs drivers` | `drivers/{include,src,fatfs}/**` | builds (not yet referenced) |
| P02 | posix-arch | `feat(soc): import the native host-file SD backend` | `soc/native/**` | idem |
| P03 | posix-arch | `build(cmake): define the dissolved devices targets locally` | `CMakeLists.txt`: drop `UOS_DEVICES_DIR` and its check, add `micro-os-plus::devices-hostfile` and `micro-os-plus::devices` (§3.3 block) | G0 |
| C01 | cortexm | `feat(soc): import the STM32F4xx SoC support` | `soc/stm32f4xx/**` | builds |
| C02 | cortexm | `feat(soc): import the RP2350 SoC support` | `soc/rp2350/**` | builds |
| C03 | cortexm | `build(cmake): define the dissolved SoC targets locally` | `CMakeLists.txt`: drop `UOS_DEVICES_DIR`, add `soc-stm32f411xe`, `soc-stm32f412rx`, `soc-rp2350` | G0 |
| A32-01 | aarch32 | `feat(drivers): import the neutral SD, flatfs, USB and FatFs drivers` | `drivers/**` | — (the repo has no build yet) |
| A32-02 | aarch32 | `feat(soc): import the BCM2837 (Raspberry Pi 3 / Zero 2 W) SoC support` | `soc/bcm2837/**` | — |
| A32-03 | aarch32 | `feat(soc): import the RK3506 (Luckfox Lyra) SoC support` | `soc/rk3506/**` | — |
| A64-01 | aarch64 | `feat(drivers): import the neutral SD, flatfs, USB and FatFs drivers` | `drivers/**` | — |
| A64-02 | aarch64 | `feat(soc): import the BCM2837 SoC support` | `soc/bcm2837/**` | — |
| D01 | devices | `docs: retire the repository -- its contents moved to the architecture ports` | `README.md` only (a table of the moves in §14.1) | — |

Each body has the trailer `Source: devices@e8e39d5:<src path>`. The devices history stays reachable in the archived repository, so a subtree merge is not needed. After D01: archive `dan-maio/micro-os-plus-iii-devices` on GitHub (Settings → Archive, an administrative action, not a commit), then delete the local clone (`rm -rf "$WORK/micro-os-plus-iii-devices"`). From here on, no CMake file may mention `micro-os-plus-iii-devices` (`git grep -n micro-os-plus-iii-devices` is empty in all five repositories).

---

## 15. Kernel `micro-os-plus-iii` — Commit List

### 15.1 Stage S1: single-core corrections and improvements (gate G1 after each)
| ID | Commit subject | Files | Legacy |
|---|---|---|---|
| K01 | `fix(posix): ISO C conformant DIR in dirent.h` | `include/cmsis-plus/posix/dirent.h` | PR #1 |
| K02 | `fix(utils): list iterators call node_->next()/prev()` | `include/cmsis-plus/utils/lists.h` | PR #2 |
| K03 | `fix(posix-io): match newlib's syscall return types in the weak aliases` | `include/cmsis-plus/posix-io/c-syscalls-aliases-standard.h` | PR #3 |
| K04 | `fix(rtos): emit thread::suspend() out of line` | `src/rtos/os-thread.cpp` (that hunk only) | PR #4 |
| K05 | `fix(libc): declare timegm() only when the C library does not` | `src/libc/stdlib/timegm.c` | new (was hidden in step01) |
| K06 | `fix(memory): block_pool asserts on a null result, not a valid one` | `src/memory/block-pool.cpp` | new (was hidden in step02) |
| K07 | `fix(estd): polymorphic_allocator copy keeps its resource` | `include/cmsis-plus/estd/memory_resource` | new (was hidden in step02) |
| K08 | `feat(memory): usable size for the RTOS allocators, overflow-checked calloc()` | `rtos/os-memory.h`, `src/rtos/os-memory.cpp`, `memory/first-fit-top.h`, `src/memory/first-fit-top.cpp`, `src/memory/lifo.cpp`, `src/libc/stdlib/malloc.cpp` | PR #5 |
| K09 | `feat(libcpp): C++17 aligned operator new/delete` | `src/libcpp/new.cpp` | PR #6 |
| K10 | `fix(libcpp): error categories with static storage` | `src/libcpp/system-error.cpp` | PR #7 |
| K11 | `fix(libcpp): steady_clock::now() without 64-bit overflow` | `src/libcpp/chrono.cpp` | PR #8 |
| K12 | `fix(rtos): CMSIS-RTOS osTimerCreate() defaults to one-shot` | `src/rtos/os-c-wrapper.cpp` (hunk) | PR #9 a |
| K13 | `fix(rtos): CMSIS-RTOS mutex delete through the polymorphic type` | idem (hunk) | PR #9 b |
| K14 | `fix(rtos): widen millisec before scaling in the C wrapper` | idem (hunk) | PR #9 c |
| K15 | `fix(posix-io): serialize the file descriptor table` | `src/posix-io/file-descriptors-manager.cpp` | PR #10 |
| K16 | `fix(posix-io): lock the deferred file-system and socket lists` | `posix-io/file-system.h`, `posix-io/net-stack.h` | PR #11 |
| K17 | `fix(posix-io): block_device sector-size check was inverted` | `src/posix-io/block-device.cpp` | PR #12 |
| K18 | `feat(arm): ARMv8-M semihosting trap` | `include/cmsis-plus/arm/semihosting.h` | PR #13 |
| K19 | `feat(startup): ARMv8-M exception handlers and fault dump` | `src/startup/exception-handlers.c`, `include/cmsis-plus/cortexm/exception-handlers.h` | PR #14 |
| K20 | `fix(semihosting): fstat() keeps an explicit mode; weak console mirror hook` | `src/semihosting/c-syscalls-semihosting.cpp` | PR #15 (split into two commits if the hunks are independent) |
| K21 | `fix(rtos): run timer callbacks outside the critical section` | `src/rtos/internal/os-lists.cpp`, `src/rtos/os-timer.cpp` (hunks) | PR #16 a |
| K22 | `fix(rtos): periodic timer drift catch-up guard` | `src/rtos/os-timer.cpp` (hunks) | PR #16 b |
| K23 | `fix(rtos): mutex priority ceiling before ownership, highest boost among waiters` | `src/rtos/os-mutex.cpp` | PR #17 |
| K24 | `feat(rtos): thread state destroying, and an idle reaper that waits for it` | `rtos/os-c-decls.h`, `rtos/os-thread.h`, `src/rtos/os-idle.cpp`, `estd/condition_variable` (step09 hunks) | PR #18 |
| K25 | `fix(rtos): condition variable without lost signals` | `src/rtos/os-condvar.cpp`, `rtos/os-condvar.h`, `diag/instrumentation.h` (`SUSPEND_CAUSE_CONDVAR`), `estd/condition_variable` (step10 hunks) | PR #19 |
| K26 | `fix(estd): std::thread::join() waits on the native handle, keeps its functor` | `src/libcpp/thread-cpp.h`, `estd/thread_internal.h` | PR #20 |
| K27 | `fix(rtos): message queue reschedules after a wake-up` | `src/rtos/os-mqueue.cpp` | PR #21 |
| K28 | `feat(rtos): high-resolution clock uses the port's hardware counter` | `rtos/os-decls.h` (hunk), `src/rtos/os-clocks.cpp` | PR #22 K, **Group G-hrclock** with C04, P04 |
| K29 | `test(rtos-apis): 512 KiB RTOS arena for the FatFs leg, and a switch to leave FatFs out` | `tests/sources/rtos-apis/include/cmsis-plus/os-app-config.h`, `tests/sources/rtos-apis/src/main.cpp` (two commits, K29a/K29b, if you prefer one subject each) | new |

Also in S1, one commit each, harness corrections that are independent of SMP:
| ID | Commit subject | Files |
|---|---|---|
| K29c | `fix(test): enable the FPU when the compiler targets one (__ARM_FP)` | `tests/device-qemu-cortexm/src/system-cortexm.c` |
| K29d | `docs(test): the AN385 flash comment says 128M` | `tests/device-qemu-cortexm/linker-scripts/mem-mps2-an385.ld`, `…an386.ld` |

### 15.2 Remaining golden kernel changes and their commits (completeness check)
Every kernel file that differs between `xpack-development` and golden `smp` belongs to exactly one row of §15.1, §15.3, §15.4, §15.5 or §15.7, or to the intended differences in §19.2. When a file appears in two rows (for example `os-thread.cpp` in K04 and K35), each row takes only its own hunks.

### 15.3 Stage S2: kernel SMP core (guarded by `OS_USE_SMP_SCHEDULER`, gate G1 after each)
| ID | Commit subject | Files (SMP hunks only) |
|---|---|---|
| K30 | `feat(port): smp-common -- the SMP declarations a thin port shares` | `port/smp-common/README.md`, `port/smp-common/cmsis-plus/rtos/port/os-decls.h` |
| K31 | `feat(rtos): SMP_NO_OWNER and the per-CPU thread context` | `rtos/os-c-decls.h`, `rtos/os-decls.h` |
| K32 | `feat(rtos): one current thread per CPU` | `rtos/os-sched.h` |
| K33 | `feat(rtos): thread CPU affinity and per-core run state` | `rtos/os-thread.h` |
| K34 | `feat(rtos): SMP scheduler -- per-CPU ready lists, recursive kernel lock, no switch while holding it` | `src/rtos/os-core.cpp` |
| K35 | `feat(rtos): thread migration and the five-stage stack-pointer claim/publish` | `src/rtos/os-thread.cpp` |
| K36 | `feat(rtos): wake a thread's CPU with an IPI when it unblocks elsewhere` | `src/rtos/os-thread.cpp` (IPI hunks; Part I PR #26 kernel part) |
| K37 | `feat(rtos): one idle thread per CPU` | `src/rtos/os-idle.cpp` |
| K38 | `feat(rtos): pin the main thread to CPU 0` | `src/rtos/os-main.cpp` |
| K39 | `test(validator): use glibc's ucontext, not libucontext` | `tests/sources/cmsis-os-validator/include/cmsis-plus/os-app-config.h` (lands right after P05, see R6) |

### 15.4 Stage S4a: build and harness infrastructure (gate G1 after each)
| ID | Commit subject | Files |
|---|---|---|
| K40 | `build(cmake): cross toolchain profiles for arm-none-eabi, aarch64-none-elf, native` | `cmake/toolchains/*.cmake` |
| K41 | `build(cmake): uos-app.cmake -- one call builds an application against a port` | `cmake/uos-app.cmake` |
| K42 | `build(cmake): modular kernel targets iii-core, iii-posix-io, port-smp-decls, test-support` | `CMakeLists.txt` (keep `micro-os-plus::iii` as the umbrella alias) |
| K42b | `build(cmake): fail the configure on a source compiled twice` (optional) | `tools/verify-no-duplicate-sources.py` plus its hook in `CMakeLists.txt`. If omitted, K42 has no hook. |
| K43a | `test: the verdict contract shared by every board (hw_result, board contract)` | `test_smpl/include/hw_result.hpp`, `test_smpl/src/board-contract.cpp` |
| K43b | `test: host runner for the port test applications` | `test_smpl/run-host.sh` |
| K43c | `test: QEMU runner for the port test applications` | `test_smpl/run-qemu.sh` |
| K43d | `test: hardware runner and the OpenOCD configs that need no power cycle` | `test_smpl/run-hw.sh`, `test_smpl/no-power-cycle/*` |
| K44 | `test(cmake): find the ports as siblings (UOS_<PORT>_DIR), with the xpack link as fallback` | `tests/cmake/tests-main.cmake`, `tests/CMakeLists.txt` |
| K45 | `test(native): run posix-arch's own test applications` | `tests/platforms/native/**` (after P20, R6) |
| K46a–d | `test(qemu-cortex-m0|m3|m4f|m7f): build against the cortexm port targets` | `tests/platforms/qemu-cortex-m{0,3,4f,7f}/**`, one commit each (after C20) |
| K47 | `test(qemu): MPS2 AN505/AN521 memory maps and ARMv8-M vectors` | `tests/device-qemu-cortexm/linker-scripts/mem-mps2-an505.ld`, `mem-mps2-an521.ld`, `src/vectors-cortexm.c`, `include/cmsis_device.h`, `src/exception-handlers.cpp` |
| K48 | `test(nucleo-f411re): build against the dissolved soc-stm32f411xe target` | `tests/platforms/nucleo-f411re/**` |

### 15.5 Stage S4b: new test suite (one commit per test)
| ID | Commit subject | Files |
|---|---|---|
| K49 | `test: fp-switch -- floating-point context integrity under 1 ms preemption` | `tests/sources/fp-switch/**` |

### 15.6 Stage S4c: platforms (one commit per platform; gate G3 for that platform)
Each commit adds the platform directory **and** in `tests/package.json` its `*-cmake-gcc-{debug,release}` configurations, its `test-<platform>-cmake` action, and **one line** in `test-smp-cmake`. The first of these commits also creates `test-smp-cmake` and appends it to `test-all`. Configuration templates that several platforms share (`aarch32-actions`, `aarch32-dependencies`, `aarch64-*`, `arm-cmsis-core-dependencies`, `clang-gcc14-properties`) land with the first platform that uses them.

| ID | Platform | Needs (R6) | QEMU in `test-smp-cmake` |
|---|---|---|---|
| K50 | `2xcortex-m33` (MPS2 AN521, 2 × M33) | C08, K47 | yes |
| K51 | `pico2-1cpu` (RP2350 code at NCPU=1 on QEMU) | C09 | yes |
| K52 | `cortexm-pico2` | C21 + pico2 tests | yes |
| K53 | `cortexm-pico2-rp2350b-psram` | C22 | yes |
| K54 | `cortexm-pico2-pizero` | C23 | no (build and `hwd` only) |
| K55 | `cortexm-nucleof411` | C24 | no |
| K56 | `cortexm-weactf411` | C25 | no |
| K57 | `cortexm-weactf412` | C26 | no |
| K58 | `aarch32-rpi-zero-2w` (raspi3b, 4 × A53) | A32-20, A32-21 | yes |
| K59 | `aarch32-rpi3b` | A32-22 | yes |
| K60 | `aarch64-rpi-zero-2w` | A64-20, A64-21 | yes |
| K61 | `aarch64-rpi3b` | A64-22 | yes |
| K62 | `aarch32-luckfox-lyra` (RK3506, 3 × A7; hardware only) | A32-23 | no (`build-aarch32-luckfox-lyra-cmake`) |
| K63 | `test(package): Debug/Release aliases and the clang 13–15 native configurations` | — | — |

### 15.7 Stage S5: documentation (one commit per document)
One commit for each `docs/*.md` (18 files), for each `docs/smp-integration/*.md` together with its own `diagrams/*` (24 documents), for each `docs/tests/*` group, for `docs/specs/*`, for `README-DEVELOPER.md`, `tests/README.md` and `tests/TO-CHECK.md`, and for `port/smp-common/README.md` if it is not in K30. `.clang-format` and the `.gitignore` additions are one `chore` commit each.

---

## 16. `micro-os-plus-iii-posix-arch` — Commit List

### 16.1 S0 and S1
P01–P03 (§14.2). **P04** `feat(port): high-resolution counter from CLOCK_MONOTONIC` belongs to group G-hrclock with K28.

### 16.2 S2: the host as a multi-core machine (one feature per commit; later golden fixes folded in by R5)
| ID | Commit subject | Files | Golden fixes folded in |
|---|---|---|---|
| P05 | `fix(port): header hygiene for GCC < 14 and clang -Weverything` | `include/cmsis-plus/rtos/port/os-{c-decls,decls,inlines}.h` (non-SMP hunks) | "build with GCC < 14 (__has_feature)", Fixes A/B/I |
| P06 | `feat(port): SMP port contract -- per-thread CPU, per-CPU ISR state, kernel lock` | the same headers (SMP hunks) | "block the tick before reading the CPU id in locked()", "never read the CPU id through a cached thread pointer" |
| P07 | `feat(port): host CPUs are pthreads, with per-CPU timers and signal IPIs` | `include/host_cpu.hpp`, `src/host_cpu.cpp`, `CMakeLists.txt` line | "drop the dead timer lock; host CPU tick split", Fixes C/E/G |
| P08 | `feat(port): host exception dispatch and the per-core boot stage` | `include/exception_handler.hpp`, `src/exception_handler.cpp`, `CMakeLists.txt` line | "handler mode for the validator's SIGUSR1 shim", Fix F |
| P09 | `feat(port): the host free store` | `src/free-store.cpp`, `CMakeLists.txt` line | — |
| P10 | `feat(port): SMP start-up and signal-driven context switch` | `src/rtos/os-core.cpp` | "errno is the µOS++ thread's, not the host thread's" |
| P11 | `feat(port): the board verdict contract on the host` | `include/hw_result.hpp`, `src/board-contract.cpp`, `CMakeLists.txt` line | — |
| P12 | `feat(port): sanitizer support for the native board` | `CMakeLists.txt` (hunk) | — |
| P13 | `build(cmake): resolve the kernel as a sibling under either directory name` | `CMakeLists.txt` (hunk) | "support micro-os-plus-iii directory name" |
| P14 | `tools: a probe showing why TSan fiber annotations cannot work here` (optional) | `tools/tsan-fiber-probe.c` | — |

### 16.3 S4: tests (P20 first, then one commit per test; gate `xpm run test-native-cmake`)
| ID | Commit | Files |
|---|---|---|
| P20 | `test: the port test builder and the native board` | `test/CMakeLists.txt`, `test/run.sh`, `test/boards/native/**`, `test/native/include/**`, `test/native/src/**` |
| P21 | `test(native): rtos-apis at OS_NCPU=1` | `test/native/rtos-apis/**` |
| P22 | `test(native): mutex-stress` | `test/native/mutex-stress/**` |
| P23 | `test(native): flatfs-test -- append to a file created empty` | `test/native/flatfs-test/**` |
| P24 | `test(native): mutex-ceiling-test -- a refused protect lock leaves nothing` | `test/native/mutex-ceiling-test/**` |
| P25 | `test(native): smp_test0` … **P29** `smp_test4` | one directory per commit |
| P30 | `test(native): smp-num-test` | |
| P31 | `test(native): smp-mat-test (N=500, B=50)` | |
| P32 | `test(native): smp-pipeline-test` | |
| P33 | `test(native): smp-pro-cons-test` | |
| P34 | `test(native): smp-mutex-stress -- SMP leg with per-core checks` | |
| P35 | `test(native): smp-rtos-apis -- SMP leg with per-core checks` | |

All of them use `std::atomic` for counters shared between cores (golden fix "convert multi-core volatile counters to std::atomic", folded in by R5).

---

## 17. `micro-os-plus-iii-cortexm` — Commit List

### 17.1 S0 and S1
C01–C03 (§14.2). **C04** `feat(port): high-resolution counter, with the SysTick pending-overflow check` belongs to group G-hrclock.

### 17.2 S2: Cortex-M SMP contract (single-core Cortex-M builds unchanged)
| ID | Commit | Files | Golden fixes folded in |
|---|---|---|---|
| C05 | `feat(port): Cortex-M SMP contract -- per-core lock state, recursive kernel lock` | `include/cmsis-plus/rtos/port/os-{c-decls,decls,inlines}.h` | "mask IRQs before reading the core id in scheduler::locked()", "publish scheduler unlock before releasing the lock" |
| C06 | `feat(port): PendSV switch with stack-pointer claim/publish` | `src/rtos/os-core.cpp` | "unpublish the stack pointer on an identity reschedule", "release klock on null thread in switch_stacks", "save the FPU context on a switch" |
| C07 | `fix(cortexm): scheduler guards, semihosting clobbers, linker sections` | the hunks of that golden commit that touch upstream code | — |

### 17.3 S3: new silicon
| ID | Commit | Files |
|---|---|---|
| C08 | `feat(port): generic Cortex-M33 (SSE-200) dual-core port` | `include-m33/**`, `src/rtos/os-core-m33.cpp`, `CMakeLists.txt` target |
| C09 | `feat(port): RP2350 dual-core port -- SIO spinlock, FIFO IPI, core 1 launch` | `include-rp2350/**`, `src/rtos/os-core-rp2350.cpp`, `CMakeLists.txt` target (with "release the 32 SIO spinlocks at reset" folded in) |
| C10 | `feat(libc): getentropy() for the bare-metal ports` | `src/libc/getentropy.c`, `CMakeLists.txt` line |
| C11 | `feat: a semihosting exit that reports the test verdict` | `src/semihosting-exit.cpp`, `CMakeLists.txt` line |
| C12 | `build(cmake): resolve the kernel as a sibling under either directory name` | `CMakeLists.txt` (hunk) |

### 17.4 S4: tests (C20 first, then one board per commit, then one test per commit)
| ID | Commit | Files |
|---|---|---|
| C20 | `test: the port test builder, QEMU and hardware dispatch` | `test/CMakeLists.txt`, `test/qemu.sh`, `test/hw.sh`, `test/boards/shared/**` |
| C21 | `test(pico2): the Pico 2 board` | `test/boards/pico2/**`, `test/pico2/{CMakeLists,tests.cmake,include,src}` |
| C22 | `test(pico2-rp2350b-psram): the RP2350B PSRAM board` | `test/boards/pico2-rp2350b-psram/**`, `test/pico2-rp2350b-psram/tests.cmake` |
| C23 | `test(pico2-pizero): the Pico 2 on Pi Zero carrier` | `test/boards/pico2-pizero/**` |
| C24 | `test(nucleof411): the NUCLEO-F411RE board under the SMP scheduler at one CPU` | `test/boards/nucleof411/**` |
| C25 | `test(weactf411): the WeAct F411 board` | `test/boards/weactf411/**` |
| C26 | `test(weactf412): the WeAct F412 board` | `test/boards/weactf412/**` |

Then one commit per test directory (`test(<board>): <test>`):
- **pico2**: cmsis-os-validator, cmsis-os-validator-ram, exc-test, fp-switch, mutex-stress, mutex-stress-ram, rtos-apis, rtos-apis-ram, sc-test-ko, smp-mat-test, smp-mat-test-ram, smp-test0 … smp-test5, smp-test-ko, smp-test-usb-cdc-acm, smp-test-usb-hid (25 commits).
- **pico2-rp2350b-psram**: exc-test, fp-switch, sc-test-ko, smp-mat-test, smp-test0 … smp-test5, smp-test-ko, smp-test-nested, smp-test-nested-clock, smp-test-nested-clock_200, smp-test-nested-clock_250 (16).
- **pico2-pizero**: exc-test, psram-exec, psram-mat-test-250, sc-test-ko, smp-mat-test, smp-test0 … smp-test5, smp-test-ko, smp-test-usb-cdc-acm, smp-test-usb-hid (14).
- **nucleof411**, **weactf411**, **weactf412**: cmsis-os-validator, mos-test1, mutex-stress, rtos-apis; plus weactf411 spi-pipeline and weactf412 uart-test1 (14).

---

## 18. `micro-os-plus-iii-aarch32` and `micro-os-plus-iii-aarch64` — Commit Lists

On `xpack-development` both repositories contain only `.gitignore`, `.npmignore`, `LICENSE`, `README.md` and `package.json`. Everything is therefore an **add**, plus one `.gitignore` update.

### 18.1 S3: the port (each commit builds `micro-os-plus::aarch32` / `::aarch64` from the files present so far, R8)
| AArch32 | AArch64 | Commit | Files |
|---|---|---|---|
| A32-04 | A64-03 | `chore: ignore every build* directory` | `.gitignore` |
| A32-05 | A64-04 | `build(cmake): the port project, the dissolved devices target, sibling kernel` | `CMakeLists.txt` (initially only the targets whose sources exist, plus `micro-os-plus::devices` from §3.3) |
| A32-06 | A64-05 | `feat(port): device header, application config and port declarations` | `include/cmsis_device.h`, `include/cmsis-plus/os-app-config.h`, `include/cmsis-plus/rtos/port/os-{c-decls,inlines}.h` |
| A32-07 | A64-06 | `feat(port): MMU set-up` (A64: with `TCR_EL1.EPD1` folded in) | `include/mmu.hpp` |
| A32-08 | A64-07 | `feat(port): exception vectors and handlers` | `include/exception_handler.hpp`, `src/exception_handler.cpp`, `src/handlers.cpp` |
| A32-09 | A64-08 | `feat(port): ARM generic timer and the high-resolution counter (CNTPCT / CNTPCT_EL0)` | `include/timer_arm.hpp` |
| A32-10 | A64-09 | `feat(port): context switch with stack-pointer claim/publish` | `include/port_ctx.hpp`, `src/context_switch.cpp`, `src/rtos/os-core.cpp` (MPIDR Aff0 mask folded in) |
| A32-11 | A64-10 | `feat(port): secondary-core boot` | `src/smp_secondary.cpp` |
| A32-12 | A64-11 | `feat(port): semihosting console and exit` | `include/semihosting.hpp`, `src/semihosting-exit.cpp` (A32 only) |

### 18.2 S4: tests
| AArch32 | AArch64 | Commit | Files |
|---|---|---|---|
| A32-20 | A64-20 | `test: the port test builder, QEMU shim and hardware dispatch` | `test/CMakeLists.txt`, `test/qemu.sh`, `test/hw.sh` |
| A32-21 | A64-21 | `test(rpi-zero-2w): the Zero 2 W board` | `test/boards/rpi-zero-2w/**`, `test/rpi-zero-2w/{tests.cmake,include,src}` |
| A32-22 | A64-22 | `test(rpi3b): the Pi 3 B board (shares the Zero 2 W sources)` | `test/boards/rpi3b/**`, `test/rpi3b/{tests.cmake,include,src}` |
| A32-23 | — | `test(luckfox-lyra): the Luckfox Lyra board (RK3506, hardware only)` | `test/boards/luckfox-lyra/**`, `test/luckfox-lyra/{include,src}` |

Then one commit per test directory, for each of `rpi-zero-2w` and `rpi3b` in both repositories: cmsis-os-validator, mutex-stress, rtos-apis, sd_test, smp-mat-sdcard-test, smp-mat-test, smp-num-test, smp-pipeline-test, smp-pro-cons-test, smp_test0 … smp_test4, usb_test (18 per board, 72 commits in all).

For `luckfox-lyra` (AArch32 only): sd_test, smp-mat-sdcard-test, smp-mat-test, smp-num-test, smp-pipeline-test, smp-pro-cons-test, smp_test0 … smp_test7, smp_test_int, smp_test_int2 … smp_test_int5 (19 commits).

The kernel platform for a board (K58–K62) lands after the board commit and at least one test. Each further test commit makes one more `ctest` entry appear in `xpm run test-<platform>-cmake`.

---

## 19. Final Parity and the Full Test Run

### 19.1 Parity check (read-only against golden)
```bash
for r in micro-os-plus-iii micro-os-plus-iii-cortexm micro-os-plus-iii-posix-arch \
         micro-os-plus-iii-aarch32 micro-os-plus-iii-aarch64; do
  git -C "$WORK/$r" diff --stat golden/smp smp
done
```

### 19.2 Intended differences (everything else is a defect to fix with one more commit)
1. Files golden deletes but the rebuild keeps (R2): kernel `.github/`, `doxygen/`, `inspiration/`, `templates/`, `.vscode/`, `.settings/`, `CHANGELOG.md`, `CLAUDE.md`, `README.md`, `README-MAINTAINER.md`, `LICENSE` (not renamed), `package-lock.json`, and the `link-deps-native-cmake-sys` action. Ports: `.npmignore`, `LICENSE`, `README*.md`, `CHANGELOG.md`, `NOTES.md`, `scripts/xpacks-helper.sh`, `.vscode/`, `.clang-format`, posix-arch `test/trace-*`.
2. Procedure tooling golden has but the rebuild does not (R3): `scripts/smp/**`, `tests/xpacks/**`, `README.pdf`, and the optional `tools/*` that were not taken.
3. Content the rebuild has but golden lacks: `soc/` and `drivers/` in posix-arch, cortexm, aarch32 and aarch64. Golden's CMake references them, but they are absent from its tree.
4. Any version bump made as an optional `chore(release)` commit.

### 19.3 Full test run (µOS++ test framework only)
```bash
cd "$WORK/micro-os-plus-iii/tests"
xpm run install-all
xpm run test-all          # native (gcc11–14, clang16–19) + qemu-cortex-m0/m3/m4f/m7f + test-smp-cmake
```
`test-smp-cmake` runs `aarch32-rpi-zero-2w`, `aarch32-rpi3b`, `aarch64-rpi-zero-2w`, `aarch64-rpi3b`, `2xcortex-m33`, `pico2-1cpu`, `cortexm-pico2` and `cortexm-pico2-rp2350b-psram` on QEMU. Hardware-only platforms (`cortexm-pico2-pizero`, `cortexm-nucleof411`, `cortexm-weact*`, `aarch32-luckfox-lyra`, `nucleo-*`, `raspberrypi-pico`) are built by `test-all` where they are registered, and are run on the bench with their `hwd` actions.

### 19.4 Size of the series (planning estimate; the executed counts are in §20.1 and §22.1)
| Repository | Commits (approx.) | Of which tests |
|---|---|---|
| micro-os-plus-iii | 29 + 10 + 13 + 1 + 14 + ~45 docs ≈ 110 | 1 suite + 13 platforms |
| posix-arch | 3 + 1 + 10 + 16 ≈ 30 | 16 |
| cortexm | 3 + 1 + 3 + 5 + 7 + 69 ≈ 88 | 69 |
| aarch32 | 3 + 9 + 4 + 36 + 19 ≈ 71 | 55 |
| aarch64 | 2 + 9 + 3 + 36 ≈ 50 | 36 |
| devices | 1 (retirement) | — |

Every row is one pull request. Tests and documents are small and add-only, so they review fast and can be merged in bulk once their builder or platform commit has landed.

---

# Part III — Execution Record, Step Summary and Complete Commit List

Part II was executed once from scratch on 2026-10-06. Fresh clones of `github.com/dan-maio/*` went into `/tmp`, with `~/Work2/micro-os-plus/*` as the read-only `golden` remote. This part records what was done, how it differs from the Part II plan, and every commit that resulted. It is the reference for opening the pull requests.

## 20. Summary of All Steps: `xpack-development` (single CPU) → `smp` (SMP)

### 20.1 Starting point
| Repository | Base (`origin/xpack-development`) | Result branch | Commits |
|---|---|---|---:|
| `micro-os-plus-iii` (kernel, K) | `7f1ce5ca` | `smp` | 125 (+ 34 documentation updates, §22.4) |
| `micro-os-plus-iii-posix-arch` (P) | `86a6a1f` | `smp` | 24 |
| `micro-os-plus-iii-cortexm` (C) | `687e975` | `smp` | 86 |
| `micro-os-plus-iii-aarch32` (A32) | `307c62f` | `smp` | 64 |
| `micro-os-plus-iii-aarch64` (A64) | `fe904c0` (GitHub; golden's base `366c957` is one commit older) | `smp` | 43 |
| `micro-os-plus-iii-devices` (D) | `smp` | retired (D01) | 1 |
| **Total** | | | **343** |

Each commit carries the trailer `Commit-ID: <ID> (xpack-dev-smp.md Part II)`. Each commit also has a local branch `pr/<ID>` pointing at it, so commit *n* becomes the PR `pr/<ID>` → `pr/<previous ID>` (§12.5). Nothing has been pushed.

### 20.2 The steps, in the order they were committed
| Step | Stage | Repositories and commit IDs | What the step does | Build check |
|---:|---|---|---|---|
| 1 | Workspace | all | Clone from `dan-maio`, add the read-only `golden` remote, create `smp` from `origin/xpack-development` (§12.1). Install with `xpm install` / `xpm link` in each port, then `xpm run install-all` in `micro-os-plus-iii/tests` (§13.3). | `install-all` rc 0 |
| 2 | S0 devices | P01–P03, C01–C03, A32-01..03, A64-01..02, D01 | Dissolve `devices`. Its drivers (SD, flatfs, USB DWC2, FatFs) go to `drivers/` and its SoC support to `soc/<chip>/` in each port that uses them. The `micro-os-plus::devices*` / `soc-*` CMake targets are defined in the port. The devices repo gets one README commit that records where everything went. | native + cortex build |
| 3 | S1 single-core | K01–K29d (41 commits) | Upstream corrections and improvements, one per commit. They cover `dirent`, `lists`, the syscall aliases, `suspend`, the allocators, aligned `new`, `system_error`, `chrono`, the C API, POSIX I/O locking, block device, ARMv8-M semihosting and fault handlers, timers, the mutex ceiling and inheritance, the thread life cycle (`destroying`, `detach`, `join`), the condition variable, `std::thread`, mqueue, and the rtos-apis test arena. | build after each |
| 4 | S1 hrclock group | K28a, K28 + C04, C04b + P04 | The high-resolution clock reads the port's hardware counter. The kernel declares it, cortexm reports that it has no hardware counter and fixes `cycles_since_tick()`, and posix-arch reads `CLOCK_MONOTONIC`. | builds at the last commit of the group |
| 5 | S2 SMP core (kernel) | K30–K39b | Everything is guarded by `OS_USE_SMP_SCHEDULER`: `port/smp-common`, one current thread per CPU, CPU affinity, the SMP picker with the stack-pointer claim, the IPI wake-up, `join`/`kill`/reaper aware of other CPUs, main thread and CMSIS-RTOS v1 threads on CPU 0. | single-core builds unchanged |
| 6 | S2 host SMP | P05, P06 | posix-arch becomes a multi-core host (one host thread per CPU, signal IPIs, per-CPU timers, exception dispatch) and gets the board verdict contract. | native build |
| 7 | S2 Cortex-M SMP | C05–C08 | The SMP port contract on the generic Cortex-M core (SMP scheduler at one CPU), a `_getentropy()` stub, and a semihosting `_Exit()` that reports the verdict. | cortex build |
| 8 | S3 new silicon | C09, C10 | A generic dual-core Cortex-M33 (SSE-200) port for QEMU, and the RP2350 dual-core port. | build |
| 9 | S3 new architectures | A32-04..11, A64-03..10 | The AArch32 and AArch64 ports: declarations, MMU, vectors, generic timer, context switch, secondary-core entry, semihosting. Add-only; nothing builds them until step 12. | — (no board yet) |
| 10 | S4a harness | K40, K41, K43a–d, then group G-harness: K42, K44, K45, K46-m0..m7f + P20 + C20a/b, then K47 | Toolchain profiles, `uos_add_app()`, the `test_smpl` verdict contract and runners, and modular kernel targets. Each port has a test builder that selects a board, and the kernel harness finds the ports as siblings. The native and QEMU Cortex-M platforms build against the port targets. | builds at the last commit of the group |
| 11 | S4b/c Cortex-M platforms | K49, K50–K57; C21–C27 boards; one commit per test | The fp-switch suite; platforms `2xcortex-m33`, `pico2-1cpu`, `cortexm-pico2`, `-rp2350b-psram`, `-pizero`, `-nucleof411`, `-weactf411`, `-weactf412`; the boards pico2 (with TinyUSB in C21b–d), pico2-rp2350b-psram, pico2-pizero, nucleof411, weactf411 and weactf412; 63 test commits. | build per commit |
| 12 | S4 AArch32/AArch64 boards | A32-20, A32-21, A32-R3, A32-LL; A64-20, A64-21, A64-R3; K58–K62 | Port CMake, board models (rpi-zero-2w, rpi3b, luckfox-lyra), and the kernel platforms `aarch32-rpi-zero-2w`, `aarch32-rpi3b`, `aarch32-luckfox-lyra`, `aarch64-rpi-zero-2w`, `aarch64-rpi3b`. | build per commit |
| 13 | S4 port tests | P21–P35, A32-T-*, A32-R3-*, A32-LL-*, A64-T-*, A64-R3-* | One commit per test directory, each adding one `ctest` entry: 15 native, 30 AArch32 Raspberry Pi, 20 Luckfox Lyra, 30 AArch64. | build per commit |
| 14 | S4 remaining harness | K39c, K48-nucleo-f411re/-f767zi/-h743zi/-raspberrypi-pico | The validator host build uses glibc's `ucontext`. The legacy hardware platforms label their tests `hwd` and link the modular targets. | see §21.3 |
| 15 | S5 docs and chores | K901–K935, K980–K984, P14, P36, C28, C29; after the run K985–K989 (§22.4) | One commit per document; `.clang-format`; `.gitignore` additions; the TSan probe; the cortexm board README; this document. | — |
| 16 | S6 parity | all (read-only diff with `golden/smp`) | §21.4. | — |
| 17 | S6 full test | `micro-os-plus-iii/tests` | §21.5. | all green |

## 21. Execution Record

### 21.1 Where the executed IDs differ from the Part II plan
| Plan (Part II) | Executed | Reason |
|---|---|---|
| K05 `timegm()` declaration | **dropped** | Golden's version fails on glibc 2.44 with `-Werror=missing-prototypes`. The baseline `timegm.c` is kept (intended difference). |
| K20, K23, K24, K25, K26 | split into K20a/b, K23a–c, K24a–e, K25a/b, K26a/b | R1: their golden hunks turned out to hold several independent subjects. |
| K21a (new) | `fix(rtos): errno in handler mode does not assert` | A separate golden subject in the K21 files. |
| K22 periodic-timer drift guard | folded into K21 | It shares one hunk with the relink (stated in K21's `Legacy:` line). |
| K28a (new) | `os-decls.h` includes the C declarations again | The provider of K28 (R6). |
| K31–K39 | renumbered by subject (see §22.2) | The golden SMP hunks group by behaviour (current thread, affinity, picker, IPI, join, kill, reaper, CPU 0) rather than by file. |
| K39b (new) | `port_cpu_id()` declarations tolerate the port's own | Needed by P05. |
| K42b duplicate-source check | not taken | It is a Python tool (R3). |
| K46a–d | K46-m0, -m3, -m4f, -m7f | Named by platform. |
| K48 | four commits K48-nucleo-f411re/-f767zi/-h743zi/-raspberrypi-pico | One per legacy platform (R1). |
| K63 Debug/Release aliases, clang 13–15 | not needed | `tests/package.json` is already byte-identical to golden after K62. |
| K90.. docs | K901–K935 (one per document) + K980–K984 | §15.7. |
| P05–P13 host SMP | P05 (one commit) + P06 | Golden's host-SMP files only compile together. The fixes (A–J, GCC < 14, errno) are folded in (R5). |
| C05–C12 | C04b, C05–C10 | `cycles_since_tick()` became its own fix. getentropy/_Exit came before the new silicon. The CMake sibling lookup was folded into C20b. |
| C20 | C20a (nucleof411 board, needed by the builder) + C20b (builder) | R6. |
| C21–C26 boards | C21 (+C21b–d TinyUSB), C23–C27 | pico2's USB stack is three commits. The pico2 test series is C22-*. |
| A32-05..12 / A64-04..11 | A32-05..11 / A64-04..10, then A32-21 / A64-21 for CMake | Port CMake lands with the first board (R8: no target without sources). |
| A32-22/23, A64-22 | A32-R3, A32-LL, A64-R3 | Named by board. |

### 21.2 Groups (built only at their last commit)
| Group | Commits | Why |
|---|---|---|
| G-hrclock | K28a, K28, C04, C04b, P04 | The kernel calls `clock_highres::has_hardware_counter()`, which each port defines. |
| G-harness | K42, K44, K45, K46-m0..m7f, P20, C20a, C20b | The kernel test harness switches from its own device sources to the port test builders, and neither side builds alone. The messages of the intermediate commits say so. |

### 21.3 Builds
Every commit was built with `xpm run build --config <cfg>` in `micro-os-plus-iii/tests`, with uncommitted changes stashed, and was green, except:
1. The intermediate commits of the two groups (§21.2).
2. A32-01..11 and A64-01..10. They only add files, and nothing builds them until the board commits A32-21 / A64-21.
3. `nucleo-f411re`, `nucleo-f767zi`, `nucleo-h743zi` and `raspberrypi-pico` fail at configure: the golden cortexm CMake does not find the kernel through the xpacks path. The files are identical to golden, so this is a golden defect, reported here and not fixed in this series.

Build fixes beyond golden, each folded into the commit that introduced the code (R5):
- warning suppressions in `system-error.cpp`, `first-fit-top.cpp`, `file-descriptors-manager.cpp`;
- `Fix H` pragmas in `os-core.cpp` and `os-thread.cpp`;
- the kernel `test-support` target falls back to `test_smpl/src/board-contract.cpp` (K42);
- posix-arch fixes A–J (P05);
- the AArch32 `micro-os-plus::soc-bcm2837` and `micro-os-plus::devices-rk3506` targets (A32-21);
- the AArch64 `soc-bcm2837` target (A64-21).

### 21.4 Final parity with `~/Work2/micro-os-plus/*` (`golden/smp`, devices excluded)
- **Identical:** all cortexm sources and CMake, and `tests/package.json`.
- **Kept although golden deletes them (R2):** `.github/`, `doxygen/`, `inspiration/`, `templates/`, `.vscode/`, `.settings/`, `CHANGELOG.md`, `CLAUDE.md`, `README*.md`, `LICENSE` (not renamed), `package-lock.json`, the port `LICENSE`/`.npmignore`/`README.md`, posix-arch `test/trace-*`, and `scripts/xpacks-helper.sh`.
- **Golden content not taken (R3):** `scripts/smp/**`, `tools/verify-*`, `docs/**/*.sh` and `*.py`, the diagram generators, `tests/xpacks/**`.
- **In the rebuild but not in golden:** `soc/` and `drivers/` in all four ports (the dissolved devices).
- **Build fixes:** listed in §21.3; plus `timegm.c` at baseline.
- **Other:** the aarch64 `package.json` description is the original one, and this document's Part II and Part III are new.

No other difference remains.

### 21.5 Full test run (µOS++ test framework, latest compilers, `sys` for native)
| Action (in `micro-os-plus-iii/tests`) | Result |
|---|---|
| `xpm run install-all` | rc 0 |
| `xpm run test-native-cmake-sys` (debug, release) | 16/16 passed in each |
| `xpm run test-cortex-cmake` (qemu-cortex-m0/m3/m4f/m7f × gcc/clang × debug/release = 8 configs) | 3/3 passed in each. The CMSIS validator reports 60/60. |
| `xpm run test-smp-cmake`: `aarch32-rpi-zero-2w`, `aarch32-rpi3b` (debug, release) | 15/15 passed in each |
| `aarch64-rpi-zero-2w`, `aarch64-rpi3b` (debug, release) | 15/15 passed in each |
| `2xcortex-m33` (debug, release) | 4/4 passed in each |
| `pico2-1cpu` (debug, release) | 4/4 passed in each |
| `cortexm-pico2` (debug, release) | 6/6 passed in each |
| `cortexm-pico2-rp2350b-psram` (debug, release) | 3/3 passed in each |

All of them run on QEMU or on the host; `ctest -LE hwd` excludes the real-hardware tests. The hardware-only platforms are built but not run.

### 21.6 Verification replay from golden (2026-10-06)
To check that the procedure of Part II, as recorded here, rebuilds the `smp` branches, the whole series was executed again from scratch in an empty `/tmp`:

1. **Clone.** Each repository was cloned from the golden working copies in `~/Work2/micro-os-plus/`, branch `xpack-development`, with the documented bases: kernel `7f1ce5ca`, cortexm `687e975`, posix-arch `86a6a1f`, aarch32 `307c62f`, aarch64 `fe904c0`, devices `e8e39d5`. The golden repositories are the read-only `golden` remote; the kernel's `golden/smp` is the commit before this document's own golden commit.
2. **Install.** `xpm run install-all` in `micro-os-plus-iii/tests`, then `xpm install` and `xpm link` in each port (§13.3).
3. **Commits.** Every commit of §22 was made again in the same order, with the same lifts and hunk selections, and built after each commit as in the first run (`xpm run build --config <cfg>`).
4. **Result.** The same 375 commits (kernel 158, posix-arch 24, cortexm 86, aarch32 64, aarch64 43) plus devices D01, with the same Commit-IDs, order and subjects, and the same build result at every commit (the exceptions of §21.3 included). Only the SHAs differ, because the commit dates differ; the SHAs in §22.3 are those of this replay.
5. **Parity with golden `smp`.** Exactly the intended differences of §21.4, plus the documentation updates of §22.4. This document itself differs from the golden copy only in the SHA columns.
6. **Full test run** (latest compilers, `ctest -LE hwd`):

| Action | Result |
|---|---|
| `xpm run install-all` | rc 0 |
| `xpm run test-native-cmake-sys` | 16/16 in debug and release |
| `xpm run test-cortex-cmake` | 3/3 in each of the 8 configurations |
| `xpm run test-smp-cmake` | aarch32 and aarch64 `rpi-zero-2w`/`rpi3b` 15/15, `2xcortex-m33` 4/4, `pico2-1cpu` 4/4, `cortexm-pico2` 6/6, `cortexm-pico2-rp2350b-psram` 3/3 — debug and release, rc 0 |

In the first pass of `test-smp-cmake`, `aarch32-rpi-zero-2w-smp-pipeline-test-qemu` (release) stopped printing after 26 s of guest time and was killed at its 1000 s timeout. Run alone it then passed 5 times in 5 (35 s each), and the complete second pass of `test-smp-cmake` was green. It is recorded as an intermittent stall of the SMP pipeline test under QEMU (`raspi3b`, 4 cores), to be investigated separately; it is not a defect of the migration series.

## 22. Complete Pull-Request and Commit List (all repositories)

Every commit of every repository is one pull request. A PR's head is the local branch `pr/<Commit-ID>`, which points at that commit; its base is the previous PR's branch in the same repository (the first PR of a repository targets `xpack-development`). After a PR is merged, the next one is retargeted to `xpack-development` (§12.5). The branches exist locally in each `/tmp/<repository>` clone and are pushed to `github.com/dan-maio/<repository>` only when the PRs are opened.

### 22.1 Legend and totals
- **PR**: position on `smp`, counted from the base (§20.1); this is the order in which the repository's PRs are opened and merged.
- **Head branch (Commit-ID)**: `pr/<ID>`, where `<ID>` is the ID in the commit trailer `Commit-ID: <ID> (xpack-dev-smp.md Part II)`.
- **Base branch**: the branch the PR targets.
- **Category**: `correction` (fix), `new code` (feat), `test`, `build`, `docs`, `chore`, `tool`.
- **Stage / theme**: the Part II stage (§13.1), followed by the R6 group (§21.2) when the commit belongs to one.

| Repository | Corrections | New code | Tests | Build | Docs | Chore / tool | PRs |
|---|---:|---:|---:|---:|---:|---:|---:|
| micro-os-plus-iii (migration) | 31 | 18 | 32 | 3 | 39 | 2 | 125 |
| micro-os-plus-iii (documentation updates, §22.4) | 0 | 0 | 0 | 0 | 34 | 0 | 34 |
| micro-os-plus-iii-posix-arch | 0 | 5 | 15 | 2 | 0 | 2 | 24 |
| micro-os-plus-iii-cortexm | 1 | 9 | 72 | 2 | 1 | 1 | 86 |
| micro-os-plus-iii-aarch32 | 0 | 10 | 52 | 1 | 0 | 1 | 64 |
| micro-os-plus-iii-aarch64 | 0 | 9 | 32 | 1 | 0 | 1 | 43 |
| micro-os-plus-iii-devices | 0 | 0 | 0 | 0 | 1 | 0 | 1 |
| **Total** | **32** | **51** | **203** | **9** | **75** | **7** | **377** |

### 22.2 Cross-repository merge order
The PRs of one repository merge in their own order (22.3). Across repositories, R6 (provider before consumer) adds these constraints:

| Before | Merge | Why |
|---|---|---|
| — | S0 in every port: posix-arch PR 1–3, cortexm PR 1–3, aarch32 PR 1–3, aarch64 PR 1–2; then devices PR 1 | The drivers and SoC support exist in the ports before the devices repository is retired. |
| kernel K28a | **G-hrclock together:** kernel K28 + cortexm C04, C04b + posix-arch P04 | The kernel calls `clock_highres::has_hardware_counter()`, which each port defines. |
| kernel K39b | posix-arch P05, P06 | The host SMP port relies on the kernel's tolerant `port_cpu_id()` declarations. |
| kernel K30–K39b, K40, K41, K43a–d | **G-harness together:** kernel K42, K44, K45, K46-m0..m7f + posix-arch P20 + cortexm C20a, C20b | The kernel harness switches to the port test builders; neither side builds alone. |
| cortexm C09 / C10 and its board PR | kernel K50 (`2xcortex-m33`), K51 (`pico2-1cpu`), K52–K57 (one per cortexm board) | A kernel platform needs its port core and board. |
| aarch32 A32-20, A32-21 (and A32-R3, A32-LL) | kernel K58, K59, K62 | idem for AArch32. |
| aarch64 A64-20, A64-21 (and A64-R3) | kernel K60, K61 | idem for AArch64. |
| the board PR of a port | that board's test PRs (`pr/<board-ID>-<test>`) | One test directory = one `ctest` entry on an existing platform. |

### 22.3 Pull requests per repository

#### micro-os-plus-iii -- 159 pull requests (github.com/dan-maio/micro-os-plus-iii)

| PR | Head branch (Commit-ID) | Base branch | SHA | Category | Stage / theme | Subject |
|---:|---|---|---|---|---|---|
| 1 | `pr/K01` | `xpack-development` | `b364e689` | correction | S1 single-core | `fix(posix): ISO C conformant DIR in dirent.h` |
| 2 | `pr/K02` | `pr/K01` | `52a7f499` | correction | S1 single-core | `fix(utils): list iterators call node_->next()/prev()` |
| 3 | `pr/K03` | `pr/K02` | `2f8c482e` | correction | S1 single-core | `fix(posix-io): match newlib's syscall return types in the weak aliases` |
| 4 | `pr/K04` | `pr/K03` | `bcb5737e` | correction | S1 single-core | `fix(rtos): emit this_thread::suspend() out of line` |
| 5 | `pr/K06` | `pr/K04` | `ef9bb2ce` | correction | S1 single-core | `fix(memory): block_pool asserts on a null result, not on a valid one` |
| 6 | `pr/K07` | `pr/K06` | `a6d6c475` | correction | S1 single-core | `fix(estd): polymorphic_allocator copy keeps its memory resource` |
| 7 | `pr/K08` | `pr/K07` | `51bdad10` | new code | S1 single-core | `feat(memory): usable size for the RTOS allocators, overflow-checked calloc()` |
| 8 | `pr/K09` | `pr/K08` | `1c589065` | new code | S1 single-core | `feat(libcpp): C++17 aligned operator new/delete` |
| 9 | `pr/K10` | `pr/K09` | `de47254b` | correction | S1 single-core | `fix(libcpp): error categories with static storage` |
| 10 | `pr/K11` | `pr/K10` | `c8aa3024` | correction | S1 single-core | `fix(libcpp): steady_clock::now() without 64-bit overflow` |
| 11 | `pr/K12` | `pr/K11` | `0c11e258` | correction | S1 single-core | `fix(rtos): C API timers default to one-shot` |
| 12 | `pr/K13` | `pr/K12` | `ebfa07b3` | correction | S1 single-core | `fix(rtos): C API deletes mutexes and semaphores through their concrete type` |
| 13 | `pr/K14` | `pr/K13` | `b4d6fdcf` | correction | S1 single-core | `fix(rtos): widen millisec before scaling in the CMSIS-RTOS API` |
| 14 | `pr/K15` | `pr/K14` | `8ed1c7b0` | correction | S1 single-core | `fix(posix-io): serialize the file descriptor table` |
| 15 | `pr/K16` | `pr/K15` | `fa232ed7` | correction | S1 single-core | `fix(posix-io): lock the deferred file-system and socket lists` |
| 16 | `pr/K17` | `pr/K16` | `01b50480` | correction | S1 single-core | `fix(posix-io): block_device size queries tested the wrong condition` |
| 17 | `pr/K18` | `pr/K17` | `deeabab3` | new code | S1 single-core | `feat(arm): semihosting trap for ARMv8-M, and an optional HLT trap` |
| 18 | `pr/K19` | `pr/K18` | `b85b378a` | new code | S1 single-core | `feat(startup): exception handlers and fault dump for ARMv8-M Mainline` |
| 19 | `pr/K20a` | `pr/K19` | `182b5f41` | correction | S1 single-core | `fix(semihosting): fstat() keeps a file type the caller already set` |
| 20 | `pr/K20b` | `pr/K20a` | `98eaf96f` | new code | S1 single-core | `feat(semihosting): weak board console mirror for stdout/stderr` |
| 21 | `pr/K21a` | `pr/K20b` | `236b2d1a` | correction | S1 single-core | `fix(rtos): errno in handler mode does not assert` |
| 22 | `pr/K21` | `pr/K21a` | `8ea2f2f6` | correction | S1 single-core | `fix(rtos): run timer callbacks outside the critical section` |
| 23 | `pr/K23a` | `pr/K21` | `267b955b` | correction | S1 single-core | `fix(rtos): refuse a priority-ceiling lock before taking ownership` |
| 24 | `pr/K23b` | `pr/K23a` | `f5861fc2` | correction | S1 single-core | `fix(rtos): priority inheritance keeps the highest boost among waiters` |
| 25 | `pr/K23c` | `pr/K23b` | `e2b3709c` | correction | S1 single-core | `fix(rtos): mutex lock re-checks the owner after boosting it` |
| 26 | `pr/K24a` | `pr/K23c` | `5390f31d` | new code | S1 single-core | `feat(rtos): thread state destroying, claimed by exactly one destroyer` |
| 27 | `pr/K24b` | `pr/K24a` | `8fcfbc41` | correction | S1 single-core | `fix(rtos): resume() re-enqueues only a suspended or initializing thread` |
| 28 | `pr/K24c` | `pr/K24b` | `61756303` | correction | S1 single-core | `fix(rtos): priority changes test and relink under one lock` |
| 29 | `pr/K24d` | `pr/K24c` | `94dce976` | new code | S1 single-core | `feat(rtos): implement thread::detach()` |
| 30 | `pr/K24e` | `pr/K24d` | `af3dfd7b` | correction | S1 single-core | `fix(rtos): join() and thread destruction without a lost wake-up` |
| 31 | `pr/K25a` | `pr/K24e` | `325a75cc` | correction | S1 single-core | `fix(estd): condition_variable::wait_for() trusts the kernel's timeout verdict` |
| 32 | `pr/K25b` | `pr/K25a` | `102a9136` | correction | S1 single-core | `fix(rtos): condition variable without lost signals, bound to its clock` |
| 33 | `pr/K26a` | `pr/K25b` | `e57aff39` | correction | S1 single-core | `fix(estd): std::thread keeps its own pointer to the bound function object` |
| 34 | `pr/K26b` | `pr/K26a` | `8742e5f4` | correction | S1 single-core | `fix(estd): std::thread::join() waits for the thread before freeing it` |
| 35 | `pr/K27` | `pr/K26b` | `72af88d8` | correction | S1 single-core | `fix(rtos): message queue reschedules after waking a peer` |
| 36 | `pr/K28a` | `pr/K27` | `135edeb3` | correction | S1 single-core | `fix(rtos): <cmsis-plus/rtos/os-decls.h> includes the C declarations again` |
| 37 | `pr/K28` | `pr/K28a` | `b474cf72` | new code | S1 single-core · G-hrclock | `feat(rtos): the high-resolution clock reads the port's hardware counter` |
| 38 | `pr/K29a` | `pr/K28` | `4804b93c` | test | S1 single-core | `test(rtos-apis): a 512 KiB RTOS arena` |
| 39 | `pr/K29b` | `pr/K29a` | `675a698e` | test | S1 single-core | `test(rtos-apis): OS_EXCLUDE_RTOS_APIS_FATFS leaves the FatFs leg out` |
| 40 | `pr/K29c` | `pr/K29b` | `f242e451` | correction | S1 single-core | `fix(test): enable the FPU when the compiler targets one` |
| 41 | `pr/K29d` | `pr/K29c` | `9cb742d0` | docs | S1 single-core | `docs(test): the MPS2 AN385/AN386 flash comment says 128M` |
| 42 | `pr/K30` | `pr/K29d` | `6f51da7a` | new code | S2 SMP core | `feat(port): smp-common -- the SMP declarations a thin port shares` |
| 43 | `pr/K31` | `pr/K30` | `f1894152` | new code | S2 SMP core | `feat(rtos): one current thread per CPU` |
| 44 | `pr/K32` | `pr/K31` | `604321a6` | new code | S2 SMP core | `feat(rtos): thread CPU affinity` |
| 45 | `pr/K33` | `pr/K32` | `ccfc03ec` | new code | S2 SMP core | `feat(rtos): SMP thread picker with affinity and the stack-pointer claim` |
| 46 | `pr/K34` | `pr/K33` | `3764d613` | new code | S2 SMP core | `feat(rtos): wake an eligible CPU with an IPI when a thread is resumed elsewhere` |
| 47 | `pr/K35` | `pr/K34` | `ce44e5b8` | new code | S2 SMP core | `feat(rtos): join() returns only once the thread is off every CPU` |
| 48 | `pr/K36` | `pr/K35` | `1a811b99` | new code | S2 SMP core | `feat(rtos): kill() waits until the thread is off every CPU and unclaimed` |
| 49 | `pr/K37` | `pr/K36` | `a5194f6e` | new code | S2 SMP core | `feat(rtos): the idle reaper leaves a thread that is still live on another CPU` |
| 50 | `pr/K38` | `pr/K37` | `bcab09e7` | new code | S2 SMP core | `feat(rtos): pin the main thread to CPU 0` |
| 51 | `pr/K39` | `pr/K38` | `b4e819eb` | new code | S2 SMP core | `feat(rtos): CMSIS-RTOS v1 threads run on CPU 0` |
| 52 | `pr/K39b` | `pr/K39` | `12882e19` | correction | S2 SMP core | `fix(rtos): the kernel's port_cpu_id() declarations tolerate the port's own` |
| 53 | `pr/K40` | `pr/K39b` | `1f6d219f` | build | S4a harness | `build(cmake): toolchain profiles for arm-none-eabi, aarch64-none-elf and the host` |
| 54 | `pr/K41` | `pr/K40` | `68155aee` | build | S4a harness | `build(cmake): uos_add_app() -- one call declares an application against a port` |
| 55 | `pr/K43a` | `pr/K41` | `0b6d9339` | test | S4a harness | `test: the verdict contract every board shares (hw_result, board contract)` |
| 56 | `pr/K43b` | `pr/K43a` | `a569c214` | test | S4a harness | `test: the host runner for the port test applications` |
| 57 | `pr/K43c` | `pr/K43b` | `4db26232` | test | S4a harness | `test: the QEMU runner for the port test applications` |
| 58 | `pr/K43d` | `pr/K43c` | `0092d31d` | test | S4a harness | `test: the hardware runner and the OpenOCD configs that need no power cycle` |
| 59 | `pr/K42` | `pr/K43d` | `a530fac4` | build | S4a harness · G-harness | `build(cmake): modular kernel targets` |
| 60 | `pr/K44` | `pr/K42` | `2f21e8ca` | test | S4a harness · G-harness | `test(cmake): the library under test is the architecture port, found as a sibling` |
| 61 | `pr/K45` | `pr/K44` | `5fef63ae` | test | S4a harness · G-harness | `test(native): run posix-arch's own test applications` |
| 62 | `pr/K46-m0` | `pr/K45` | `62d55a6e` | test | S4a harness · G-harness | `test(qemu-cortex-m0): build against the cortexm port's generic QEMU core` |
| 63 | `pr/K46-m3` | `pr/K46-m0` | `acc3e284` | test | S4a harness · G-harness | `test(qemu-cortex-m3): build against the cortexm port's generic QEMU core` |
| 64 | `pr/K46-m4f` | `pr/K46-m3` | `b3322cc3` | test | S4a harness · G-harness | `test(qemu-cortex-m4f): build against the cortexm port's generic QEMU core` |
| 65 | `pr/K46-m7f` | `pr/K46-m4f` | `d0edbce3` | test | S4a harness · G-harness | `test(qemu-cortex-m7f): build against the cortexm port's generic QEMU core` |
| 66 | `pr/K47` | `pr/K46-m7f` | `c91f3b6b` | test | S4a harness | `test(qemu): MPS2 AN505/AN521 memory maps and ARMv8-M support in the QEMU device` |
| 67 | `pr/K49` | `pr/K47` | `9a194e45` | test | S4b test suite | `test: fp-switch -- the FPU registers survive a preemptive switch and a core move` |
| 68 | `pr/K50` | `pr/K49` | `8efc3ecb` | test | S4c platform | `test(2xcortex-m33): two Cortex-M33 cores on QEMU mps2-an521` |
| 69 | `pr/K51` | `pr/K50` | `85c38290` | test | S4c platform | `test(pico2-1cpu): the RP2350's Cortex-M33 code at one CPU on QEMU` |
| 70 | `pr/K52` | `pr/K51` | `5af5b8d7` | test | S4c platform | `test(cortexm-pico2): the Pico 2 board's own tests, on QEMU and on the board` |
| 71 | `pr/K53` | `pr/K52` | `41ee57a4` | test | S4c platform | `test(cortexm-pico2-rp2350b-psram): the RP2350B PSRAM board's tests` |
| 72 | `pr/K54` | `pr/K53` | `e5a581a8` | test | S4c platform | `test(cortexm-pico2-pizero): the pico2-pizero board's tests, hardware only` |
| 73 | `pr/K55` | `pr/K54` | `76fd013c` | test | S4c platform | `test(cortexm-nucleof411): the NUCLEO-F411RE board's tests under the SMP scheduler at one CPU` |
| 74 | `pr/K56` | `pr/K55` | `c0772ab8` | test | S4c platform | `test(cortexm-weactf411): the WeAct F411 board's tests` |
| 75 | `pr/K57` | `pr/K56` | `084b6528` | test | S4c platform | `test(cortexm-weactf412): the WeAct F412 board's tests` |
| 76 | `pr/K58` | `pr/K57` | `93faa7da` | test | S4c platform | `test(aarch32-rpi-zero-2w): the Zero 2 W's AArch32 tests on QEMU raspi3b` |
| 77 | `pr/K59` | `pr/K58` | `8f3a1051` | test | S4c platform | `test(aarch32-rpi3b): the Pi 3 B's AArch32 tests on QEMU raspi3b` |
| 78 | `pr/K62` | `pr/K59` | `9ee32a05` | test | S4c platform | `test(aarch32-luckfox-lyra): build the Luckfox Lyra's tests` |
| 79 | `pr/K60` | `pr/K62` | `55841a50` | test | S4c platform | `test(aarch64-rpi-zero-2w): the Zero 2 W's AArch64 tests on QEMU raspi3b` |
| 80 | `pr/K61` | `pr/K60` | `eb23b89a` | test | S4c platform | `test(aarch64-rpi3b): the Pi 3 B's AArch64 tests on QEMU raspi3b` |
| 81 | `pr/K39c` | `pr/K61` | `c329210b` | test | S2 SMP core | `test(validator): the host build uses glibc's ucontext, not libucontext` |
| 82 | `pr/K48-nucleo-f411re` | `pr/K39c` | `a62e6992` | test | S4a harness | `test(nucleo-f411re): label the board tests hwd and link the kernel's modular targets` |
| 83 | `pr/K48-nucleo-f767zi` | `pr/K48-nucleo-f411re` | `0f3d65ad` | test | S4a harness | `test(nucleo-f767zi): label the board tests hwd and link the kernel's modular targets` |
| 84 | `pr/K48-nucleo-h743zi` | `pr/K48-nucleo-f767zi` | `cfa25b4c` | test | S4a harness | `test(nucleo-h743zi): label the board tests hwd and link the kernel's modular targets` |
| 85 | `pr/K48-raspberrypi-pico` | `pr/K48-nucleo-h743zi` | `87be7f54` | test | S4a harness | `test(raspberrypi-pico): label the board tests hwd and link the kernel's modular targets` |
| 86 | `pr/K901` | `pr/K48-raspberrypi-pico` | `eb6fb4d9` | docs | S5 docs/chore | `docs: aarch32-second-board` |
| 87 | `pr/K902` | `pr/K901` | `b8c45608` | docs | S5 docs/chore | `docs: building-aarch32-aarch64` |
| 88 | `pr/K903` | `pr/K902` | `5f899167` | docs | S5 docs/chore | `docs: cortexm-port` |
| 89 | `pr/K904` | `pr/K903` | `8800c1c7` | docs | S5 docs/chore | `docs: posix-arch-port` |
| 90 | `pr/K905` | `pr/K904` | `c3f5b83a` | docs | S5 docs/chore | `docs: smp-integration/agy-review` |
| 91 | `pr/K906` | `pr/K905` | `b2027337` | docs | S5 docs/chore | `docs: smp-integration/DeepSeek-review` |
| 92 | `pr/K907` | `pr/K906` | `c98fcc93` | docs | S5 docs/chore | `docs: smp-integration/diagrams` |
| 93 | `pr/K908` | `pr/K907` | `8ddcb6c6` | docs | S5 docs/chore | `docs: smp-integration/files-modif-by-step` |
| 94 | `pr/K909` | `pr/K908` | `b9695be3` | docs | S5 docs/chore | `docs: smp-integration/GITHUB-PROGRESSIVE-PR-GUIDE` |
| 95 | `pr/K910` | `pr/K909` | `ac125125` | docs | S5 docs/chore | `docs: smp-integration/Implementation-SMP-Integration` |
| 96 | `pr/K911` | `pr/K910` | `75e7e1c3` | docs | S5 docs/chore | `docs: smp-integration/micro-os-plus-iii-project-unification` |
| 97 | `pr/K912` | `pr/K911` | `0e26f6e2` | docs | S5 docs/chore | `docs: smp-integration/MICRO-OS-PLUS-SMP-VS-SINGLECORE-ANALYSIS` |
| 98 | `pr/K913` | `pr/K912` | `371d71b1` | docs | S5 docs/chore | `docs: smp-integration/new-modifications` |
| 99 | `pr/K914` | `pr/K913` | `8930f3c7` | docs | S5 docs/chore | `docs: smp-integration/pull-request` |
| 100 | `pr/K915` | `pr/K914` | `6658ffb3` | docs | S5 docs/chore | `docs: smp-integration/smp-construction` |
| 101 | `pr/K916` | `pr/K915` | `28e2fb7d` | docs | S5 docs/chore | `docs: smp-integration/SMP-UPSTREAM-INTEGRATION-PLAN` |
| 102 | `pr/K917` | `pr/K916` | `a840dec4` | docs | S5 docs/chore | `docs: smp-integration/xpack-dev-smp` |
| 103 | `pr/K918` | `pr/K917` | `8fdb54ca` | docs | S5 docs/chore | `docs: specs` |
| 104 | `pr/K919` | `pr/K918` | `32f6644e` | docs | S5 docs/chore | `docs: STATUS` |
| 105 | `pr/K920` | `pr/K919` | `5e847731` | docs | S5 docs/chore | `docs: tests/AARCH32-RPI-ZERO-2W-TESTS` |
| 106 | `pr/K921` | `pr/K920` | `d925dc2c` | docs | S5 docs/chore | `docs: tests/HARNESS-BOARD-TEST-CHEATSHEET` |
| 107 | `pr/K922` | `pr/K921` | `bc6c523b` | docs | S5 docs/chore | `docs: tests/HARNESS-TESTS-PARADIGM` |
| 108 | `pr/K923` | `pr/K922` | `8c4fbd55` | docs | S5 docs/chore | `docs: tests-in-aarch32-aarch64` |
| 109 | `pr/K924` | `pr/K923` | `646cb078` | docs | S5 docs/chore | `docs: test-smpl` |
| 110 | `pr/K925` | `pr/K924` | `a136e8bd` | docs | S5 docs/chore | `docs: tests/README` |
| 111 | `pr/K926` | `pr/K925` | `20bf4b20` | docs | S5 docs/chore | `docs: tests/README-DEVELOPER` |
| 112 | `pr/K927` | `pr/K926` | `9b8d0fe9` | docs | S5 docs/chore | `docs: tests/README-MAINTAINER` |
| 113 | `pr/K928` | `pr/K927` | `d53e34c7` | docs | S5 docs/chore | `docs: tests/STEPS` |
| 114 | `pr/K929` | `pr/K928` | `3a0b2153` | docs | S5 docs/chore | `docs: tests/test-framework` |
| 115 | `pr/K930` | `pr/K929` | `4815480b` | docs | S5 docs/chore | `docs: tests/TESTS-CATALOG` |
| 116 | `pr/K931` | `pr/K930` | `d142d5a1` | docs | S5 docs/chore | `docs: tests/TESTS-DEVELOPER-GUIDE` |
| 117 | `pr/K932` | `pr/K931` | `c72b7500` | docs | S5 docs/chore | `docs: tests/TESTS-XPACK-SYSTEM` |
| 118 | `pr/K933` | `pr/K932` | `1deca033` | docs | S5 docs/chore | `docs: tests/WORK-SMP-AARCH32-AARCH64-HARNESS-GUIDE` |
| 119 | `pr/K934` | `pr/K933` | `72f5d7a1` | docs | S5 docs/chore | `docs: upstream-CHANGELOG` |
| 120 | `pr/K935` | `pr/K934` | `6e0c1276` | docs | S5 docs/chore | `docs: upstream-package` |
| 121 | `pr/K980` | `pr/K935` | `675652cb` | docs | S5 docs/chore | `docs: README-DEVELOPER updated from the reference smp branch` |
| 122 | `pr/K981` | `pr/K980` | `f6337d83` | docs | S5 docs/chore | `docs(test): tests/README for the 22 platforms, TO-CHECK marked as history` |
| 123 | `pr/K982` | `pr/K981` | `0301394d` | chore | S5 docs/chore | `chore: a .clang-format for the kernel sources` |
| 124 | `pr/K983` | `pr/K982` | `c7541e17` | chore | S5 docs/chore | `chore: ignore every build* directory and the build products` |
| 125 | `pr/K984` | `pr/K983` | `ba3817b5` | docs | S5 docs/chore | `docs(smp): xpack-dev-smp.md Part II -- the commit-only migration procedure` |
| 126 | `pr/K985` | `pr/K984` | `6fb211a9` | docs | S5 docs/chore | `docs(smp): xpack-dev-smp.md Part III -- execution record, step summary, commit list` |
| 127 | `pr/K986-STATUS` | `pr/K985` | `e2a90a42` | docs | S5 docs/chore | `docs: STATUS for the commit-only migration of 2026-10-06` |
| 128 | `pr/K986-aarch32-second-board` | `pr/K986-STATUS` | `7bfb05be` | docs | S5 docs/chore | `docs: aarch32-second-board -- the RK3506 SD driver is in the port` |
| 129 | `pr/K986-building-aarch32-aarch64` | `pr/K986-aarch32-second-board` | `a256bafe` | docs | S5 docs/chore | `docs: building-aarch32-aarch64 without the devices repository` |
| 130 | `pr/K986-posix-arch-port` | `pr/K986-building-aarch32-aarch64` | `6c6a136a` | docs | S5 docs/chore | `docs: posix-arch-port -- drivers and SD back-end are in the port` |
| 131 | `pr/K986-cortexm-port` | `pr/K986-posix-arch-port` | `a9c1ad47` | docs | S5 docs/chore | `docs: cortexm-port -- the SoC directories and the verified results` |
| 132 | `pr/K986-test-smpl` | `pr/K986-cortexm-port` | `c273abb1` | docs | S5 docs/chore | `docs: test-smpl lists the verdict contract and the no-power-cycle configs` |
| 133 | `pr/K986-tests-in-aarch32-aarch64` | `pr/K986-test-smpl` | `0ff357af` | docs | S5 docs/chore | `docs: tests-in-aarch32-aarch64 shows drivers/ and soc/ in the port` |
| 134 | `pr/K986-WORK-SMP-HARNESS-GUIDE` | `pr/K986-tests-in-aarch32-aarch64` | `359b2b73` | docs | S5 docs/chore | `docs(tests): WORK-SMP harness guide -- no devices repository` |
| 135 | `pr/K986-TESTS-XPACK-SYSTEM` | `pr/K986-WORK-SMP-HARNESS-GUIDE` | `982522d7` | docs | S5 docs/chore | `docs(tests): TESTS-XPACK-SYSTEM -- the four ports, devices dissolved` |
| 136 | `pr/K986-HARNESS-TESTS-PARADIGM` | `pr/K986-TESTS-XPACK-SYSTEM` | `a8983cd6` | docs | S5 docs/chore | `docs(tests): HARNESS-TESTS-PARADIGM -- no devices repository` |
| 137 | `pr/K986-HARNESS-BOARD-TEST-CHEATSHEET` | `pr/K986-HARNESS-TESTS-PARADIGM` | `ef3d8096` | docs | S5 docs/chore | `docs(tests): HARNESS-BOARD-TEST-CHEATSHEET -- no devices repository` |
| 138 | `pr/K986-AARCH32-RPI-ZERO-2W-TESTS` | `pr/K986-HARNESS-BOARD-TEST-CHEATSHEET` | `997146ca` | docs | S5 docs/chore | `docs(tests): AARCH32-RPI-ZERO-2W-TESTS -- drivers are in the port` |
| 139 | `pr/K986-STEPS` | `pr/K986-AARCH32-RPI-ZERO-2W-TESTS` | `335b3416` | docs | S5 docs/chore | `docs(tests): STEPS -- a port finds only the kernel as a sibling` |
| 140 | `pr/K986-TESTS-DEVELOPER-GUIDE` | `pr/K986-STEPS` | `3ee23fe2` | docs | S5 docs/chore | `docs(tests): TESTS-DEVELOPER-GUIDE -- the workspace without devices` |
| 141 | `pr/K986-TESTS-CATALOG` | `pr/K986-TESTS-DEVELOPER-GUIDE` | `63f2b822` | docs | S5 docs/chore | `docs(tests): TESTS-CATALOG -- four ports, and the last verified run` |
| 142 | `pr/K986-tests-README-DEVELOPER` | `pr/K986-TESTS-CATALOG` | `d504cbc4` | docs | S5 docs/chore | `docs(tests): README-DEVELOPER -- the current clone layout` |
| 143 | `pr/K986-tests-README-MAINTAINER` | `pr/K986-tests-README-DEVELOPER` | `0ddf9763` | docs | S5 docs/chore | `docs(tests): README-MAINTAINER -- the current clone layout` |
| 144 | `pr/K986-test-framework` | `pr/K986-tests-README-MAINTAINER` | `b60858d1` | docs | S5 docs/chore | `docs(tests): test-framework points to the smp side` |
| 145 | `pr/K986-agy-review` | `pr/K986-test-framework` | `8c3477d2` | docs | S5 docs/chore | `docs(smp): agy-review -- status note, superseded by xpack-dev-smp.md` |
| 146 | `pr/K986-DeepSeek-review` | `pr/K986-agy-review` | `60e4d0ef` | docs | S5 docs/chore | `docs(smp): DeepSeek-review -- status note, superseded by xpack-dev-smp.md` |
| 147 | `pr/K986-files-modif-by-step` | `pr/K986-DeepSeek-review` | `1da601cd` | docs | S5 docs/chore | `docs(smp): files-modif-by-step -- status note, superseded by xpack-dev-smp.md` |
| 148 | `pr/K986-GITHUB-PROGRESSIVE-PR-GUIDE` | `pr/K986-files-modif-by-step` | `66ef2fa5` | docs | S5 docs/chore | `docs(smp): GITHUB-PROGRESSIVE-PR-GUIDE -- status note, superseded by xpack-dev-smp.md` |
| 149 | `pr/K986-Implementation-SMP-Integration` | `pr/K986-GITHUB-PROGRESSIVE-PR-GUIDE` | `440716ba` | docs | S5 docs/chore | `docs(smp): Implementation-SMP-Integration -- status note, superseded by xpack-dev-smp.md` |
| 150 | `pr/K986-micro-os-plus-iii-project-unification` | `pr/K986-Implementation-SMP-Integration` | `c6c7eebe` | docs | S5 docs/chore | `docs(smp): project-unification -- status note` |
| 151 | `pr/K986-MICRO-OS-PLUS-SMP-VS-SINGLECORE-ANALYSIS` | `pr/K986-micro-os-plus-iii-project-unification` | `df0f0ed9` | docs | S5 docs/chore | `docs(smp): SMP-VS-SINGLECORE-ANALYSIS -- status note` |
| 152 | `pr/K986-new-modifications` | `pr/K986-MICRO-OS-PLUS-SMP-VS-SINGLECORE-ANALYSIS` | `2be02079` | docs | S5 docs/chore | `docs(smp): new-modifications -- status note` |
| 153 | `pr/K986-pull-request` | `pr/K986-new-modifications` | `0e1416d3` | docs | S5 docs/chore | `docs(smp): pull-request -- status note, superseded by xpack-dev-smp.md` |
| 154 | `pr/K986-smp-construction` | `pr/K986-pull-request` | `02e62612` | docs | S5 docs/chore | `docs(smp): smp-construction -- status note` |
| 155 | `pr/K986-SMP-UPSTREAM-INTEGRATION-PLAN` | `pr/K986-smp-construction` | `21d772ad` | docs | S5 docs/chore | `docs(smp): SMP-UPSTREAM-INTEGRATION-PLAN -- status note, superseded by xpack-dev-smp.md` |
| 156 | `pr/K986-2026-09-20-micro-os-plus-iii-smp-unification-design` | `pr/K986-SMP-UPSTREAM-INTEGRATION-PLAN` | `039c42c6` | docs | S5 docs/chore | `docs(specs): smp-unification-design -- status note` |
| 157 | `pr/K987` | `pr/K986-2026-09-20-micro-os-plus-iii-smp-unification-design` | `646a4904` | docs | S5 docs/chore | `docs(smp): xpack-dev-smp.md lists the documentation updates` |
| 158 | `pr/K988` | `pr/K987` | `ec40386b` | docs | S5 docs/chore | `docs(smp): xpack-dev-smp.md -- the pull requests of every repository` |
| 159 | `pr/K989` | `pr/K988` | (this commit) | docs | S5 docs/chore | `docs(smp): xpack-dev-smp.md -- the verification replay from golden` |

#### micro-os-plus-iii-posix-arch -- 24 pull requests (github.com/dan-maio/micro-os-plus-iii-posix-arch)

| PR | Head branch (Commit-ID) | Base branch | SHA | Category | Stage / theme | Subject |
|---:|---|---|---|---|---|---|
| 1 | `pr/P01` | `xpack-development` | `26a120bf` | new code | S0 devices | `feat(drivers): import the neutral SD, flatfs, USB and FatFs drivers` |
| 2 | `pr/P02` | `pr/P01` | `b8e8b4ad` | new code | S0 devices | `feat(soc): import the native host-file SD backend` |
| 3 | `pr/P03` | `pr/P02` | `9c5914ed` | build | S0 devices | `build(cmake): define the dissolved devices targets locally` |
| 4 | `pr/P04` | `pr/P03` | `5a1a255a` | new code | S1 hrclock · G-hrclock | `feat(port): clock_highres reads CLOCK_MONOTONIC` |
| 5 | `pr/P05` | `pr/P04` | `9be889da` | new code | S2 host SMP | `feat(port): the host is a multi-core machine -- one host thread per CPU` |
| 6 | `pr/P06` | `pr/P05` | `22f54df7` | new code | S2 host SMP | `feat(port): the board verdict contract on the host` |
| 7 | `pr/P20` | `pr/P06` | `e4f6c62f` | build | S4 harness · G-harness | `build(cmake): the port selects its board, and builds its own tests` |
| 8 | `pr/P21` | `pr/P20` | `305de44c` | test | S4 test | `test(native): rtos-apis at OS_NCPU = 1` |
| 9 | `pr/P22` | `pr/P21` | `e080ea6a` | test | S4 test | `test(native): mutex-stress` |
| 10 | `pr/P23` | `pr/P22` | `76c72864` | test | S4 test | `test(native): flatfs-test -- append to a file created empty` |
| 11 | `pr/P24` | `pr/P23` | `e648c634` | test | S4 test | `test(native): mutex-ceiling-test -- a refused protect lock leaves nothing behind` |
| 12 | `pr/P25` | `pr/P24` | `f0820dd5` | test | S4 test | `test(native): smp_test0 -- bring-up on one active CPU` |
| 13 | `pr/P26` | `pr/P25` | `c249804c` | test | S4 test | `test(native): smp_test1 -- semaphore ping-pong across CPUs` |
| 14 | `pr/P27` | `pr/P26` | `4f1eee6b` | test | S4 test | `test(native): smp_test2 -- kernel lock coherency on every CPU` |
| 15 | `pr/P28` | `pr/P27` | `c26ff0fe` | test | S4 test | `test(native): smp_test3 -- message queue producer/consumer across CPUs` |
| 16 | `pr/P29` | `pr/P28` | `b67adcae` | test | S4 test | `test(native): smp_test4 -- load balancing without affinity` |
| 17 | `pr/P30` | `pr/P29` | `75a487c7` | test | S4 test | `test(native): smp-num-test -- concurrent workers and console I/O` |
| 18 | `pr/P31` | `pr/P30` | `9fe414ca` | test | S4 test | `test(native): smp-mat-test -- parallel block solver (N=500, B=50)` |
| 19 | `pr/P32` | `pr/P31` | `e60f2f2c` | test | S4 test | `test(native): smp-pipeline-test -- multi-stage pipeline across CPUs` |
| 20 | `pr/P33` | `pr/P32` | `e614e825` | test | S4 test | `test(native): smp-pro-cons-test -- producers and consumers over every kernel object` |
| 21 | `pr/P34` | `pr/P33` | `c4f5f652` | test | S4 test | `test(native): smp-mutex-stress -- the SMP leg of mutex-stress, with per-core checks` |
| 22 | `pr/P35` | `pr/P34` | `6aec9d4c` | test | S4 test | `test(native): smp-rtos-apis -- the SMP leg of rtos-apis` |
| 23 | `pr/P14` | `pr/P35` | `e156e975` | tool | tool | `tools: a probe showing why TSan fiber annotations cannot work here` |
| 24 | `pr/P36` | `pr/P14` | `93c42239` | chore | chore | `chore: ignore every build* directory and the build products` |

#### micro-os-plus-iii-cortexm -- 86 pull requests (github.com/dan-maio/micro-os-plus-iii-cortexm)

| PR | Head branch (Commit-ID) | Base branch | SHA | Category | Stage / theme | Subject |
|---:|---|---|---|---|---|---|
| 1 | `pr/C01` | `xpack-development` | `b2bdd12c` | new code | S0 devices | `feat(soc): import the STM32F4xx SoC support` |
| 2 | `pr/C02` | `pr/C01` | `2310c355` | new code | S0 devices | `feat(soc): import the RP2350 SoC support` |
| 3 | `pr/C03` | `pr/C02` | `f64c09a4` | build | S0 devices | `build(cmake): define the dissolved SoC targets locally` |
| 4 | `pr/C04` | `pr/C03` | `736010e8` | new code | S1 hrclock · G-hrclock | `feat(port): clock_highres declares it has no hardware counter` |
| 5 | `pr/C04b` | `pr/C04` | `31b04065` | correction | S1 hrclock | `fix(port): cycles_since_tick() reads the SysTick pending flag from ICSR` |
| 6 | `pr/C05` | `pr/C04b` | `dfbfda56` | new code | S2 Cortex-M SMP | `feat(port): the SMP port contract on the generic Cortex-M core` |
| 7 | `pr/C06` | `pr/C05` | `cc6412ab` | new code | S2 Cortex-M SMP | `feat(port): the generic Cortex-M core runs the SMP scheduler on one CPU` |
| 8 | `pr/C07` | `pr/C06` | `c9b5c630` | new code | S2 Cortex-M SMP | `feat(libc): a _getentropy() stub for the QEMU images` |
| 9 | `pr/C08` | `pr/C07` | `597bdda8` | new code | S2 Cortex-M SMP | `feat: _Exit() reports the test verdict through semihosting` |
| 10 | `pr/C09` | `pr/C08` | `ba9ef5ee` | new code | S3 new silicon | `feat(port): a generic Cortex-M33 (SSE-200) dual-core port for QEMU` |
| 11 | `pr/C10` | `pr/C09` | `0071da04` | new code | S3 new silicon | `feat(port): the RP2350 dual-core port` |
| 12 | `pr/C20a` | `pr/C10` | `591b070e` | test | S4 board/harness | `test(nucleof411): the NUCLEO-F411RE board` |
| 13 | `pr/C20b` | `pr/C20a` | `3629ead6` | build | S4 board/harness · G-harness | `build(cmake): the port selects its board, builds its tests, and exports the QEMU cores` |
| 14 | `pr/C21` | `pr/C20b` | `2187bd34` | test | S4 board/harness | `test(pico2): the Raspberry Pi Pico 2 board (RP2350, two Cortex-M33)` |
| 15 | `pr/C21b` | `pr/C21` | `fbd44d24` | test | S4 board/harness | `test(pico2): vendor the TinyUSB device stack for the RP2350` |
| 16 | `pr/C21c` | `pr/C21b` | `e82f3f7e` | test | S4 board/harness | `test(pico2): a minimal pico-sdk shim for TinyUSB` |
| 17 | `pr/C21d` | `pr/C21c` | `9e62cb6b` | test | S4 board/harness | `test(pico2): CDC-ACM and HID device configurations` |
| 18 | `pr/C22-rtos-apis` | `pr/C21d` | `13e72795` | test | S4 test | `test(pico2): rtos-apis` |
| 19 | `pr/C22-cmsis-os-validator-ram` | `pr/C22-rtos-apis` | `094d7daf` | test | S4 test | `test(pico2): cmsis-os-validator-ram` |
| 20 | `pr/C22-cmsis-os-validator` | `pr/C22-cmsis-os-validator-ram` | `e58e7663` | test | S4 test | `test(pico2): cmsis-os-validator` |
| 21 | `pr/C22-exc-test` | `pr/C22-cmsis-os-validator` | `49e47089` | test | S4 test | `test(pico2): exc-test` |
| 22 | `pr/C22-fp-switch` | `pr/C22-exc-test` | `3cbb8aff` | test | S4 test | `test(pico2): fp-switch` |
| 23 | `pr/C22-mutex-stress-ram` | `pr/C22-fp-switch` | `88bd02ad` | test | S4 test | `test(pico2): mutex-stress-ram` |
| 24 | `pr/C22-mutex-stress` | `pr/C22-mutex-stress-ram` | `c8fbb351` | test | S4 test | `test(pico2): mutex-stress` |
| 25 | `pr/C22-rtos-apis-ram` | `pr/C22-mutex-stress` | `0a2e9b77` | test | S4 test | `test(pico2): rtos-apis-ram` |
| 26 | `pr/C22-sc-test-ko` | `pr/C22-rtos-apis-ram` | `89a5454d` | test | S4 test | `test(pico2): sc-test-ko` |
| 27 | `pr/C22-smp-mat-test` | `pr/C22-sc-test-ko` | `57149d31` | test | S4 test | `test(pico2): smp-mat-test` |
| 28 | `pr/C22-smp-mat-test-ram` | `pr/C22-smp-mat-test` | `d3bd1bff` | test | S4 test | `test(pico2): smp-mat-test-ram` |
| 29 | `pr/C22-smp-test-ko` | `pr/C22-smp-mat-test-ram` | `d4fb4e67` | test | S4 test | `test(pico2): smp-test-ko` |
| 30 | `pr/C22-smp-test-usb-cdc-acm` | `pr/C22-smp-test-ko` | `6156aa38` | test | S4 test | `test(pico2): smp-test-usb-cdc-acm` |
| 31 | `pr/C22-smp-test-usb-hid` | `pr/C22-smp-test-usb-cdc-acm` | `385cb24c` | test | S4 test | `test(pico2): smp-test-usb-hid` |
| 32 | `pr/C22-smp-test0` | `pr/C22-smp-test-usb-hid` | `e7546968` | test | S4 test | `test(pico2): smp-test0` |
| 33 | `pr/C22-smp-test1` | `pr/C22-smp-test0` | `a8263f0d` | test | S4 test | `test(pico2): smp-test1` |
| 34 | `pr/C22-smp-test2` | `pr/C22-smp-test1` | `137a1cb1` | test | S4 test | `test(pico2): smp-test2` |
| 35 | `pr/C22-smp-test3` | `pr/C22-smp-test2` | `802c05fd` | test | S4 test | `test(pico2): smp-test3` |
| 36 | `pr/C22-smp-test4` | `pr/C22-smp-test3` | `30d31e49` | test | S4 test | `test(pico2): smp-test4` |
| 37 | `pr/C22-smp-test5` | `pr/C22-smp-test4` | `9367c2fa` | test | S4 test | `test(pico2): smp-test5` |
| 38 | `pr/C23` | `pr/C22-smp-test5` | `1cffd384` | test | S4 board/harness | `test(pico2-rp2350b-psram): the RP2350B board with 16 MiB flash and PSRAM` |
| 39 | `pr/C23-exc-test` | `pr/C23` | `ecbfb0b0` | test | S4 test | `test(pico2-rp2350b-psram): exc-test` |
| 40 | `pr/C23-fp-switch` | `pr/C23-exc-test` | `f2708769` | test | S4 test | `test(pico2-rp2350b-psram): fp-switch` |
| 41 | `pr/C23-sc-test-ko` | `pr/C23-fp-switch` | `9767e0dc` | test | S4 test | `test(pico2-rp2350b-psram): sc-test-ko` |
| 42 | `pr/C23-smp-mat-test` | `pr/C23-sc-test-ko` | `5a78743c` | test | S4 test | `test(pico2-rp2350b-psram): smp-mat-test` |
| 43 | `pr/C23-smp-test-ko` | `pr/C23-smp-mat-test` | `eb888556` | test | S4 test | `test(pico2-rp2350b-psram): smp-test-ko` |
| 44 | `pr/C23-smp-test-nested-clock` | `pr/C23-smp-test-ko` | `1c50c6c1` | test | S4 test | `test(pico2-rp2350b-psram): smp-test-nested-clock` |
| 45 | `pr/C23-smp-test-nested-clock_200` | `pr/C23-smp-test-nested-clock` | `dcc8fdf3` | test | S4 test | `test(pico2-rp2350b-psram): smp-test-nested-clock_200` |
| 46 | `pr/C23-smp-test-nested-clock_250` | `pr/C23-smp-test-nested-clock_200` | `53e7990b` | test | S4 test | `test(pico2-rp2350b-psram): smp-test-nested-clock_250` |
| 47 | `pr/C23-smp-test-nested` | `pr/C23-smp-test-nested-clock_250` | `03462dd0` | test | S4 test | `test(pico2-rp2350b-psram): smp-test-nested` |
| 48 | `pr/C23-smp-test0` | `pr/C23-smp-test-nested` | `4fddd1a6` | test | S4 test | `test(pico2-rp2350b-psram): smp-test0` |
| 49 | `pr/C23-smp-test1` | `pr/C23-smp-test0` | `38f862a7` | test | S4 test | `test(pico2-rp2350b-psram): smp-test1` |
| 50 | `pr/C23-smp-test2` | `pr/C23-smp-test1` | `792ee80b` | test | S4 test | `test(pico2-rp2350b-psram): smp-test2` |
| 51 | `pr/C23-smp-test3` | `pr/C23-smp-test2` | `fdcd879c` | test | S4 test | `test(pico2-rp2350b-psram): smp-test3` |
| 52 | `pr/C23-smp-test4` | `pr/C23-smp-test3` | `0b2d5838` | test | S4 test | `test(pico2-rp2350b-psram): smp-test4` |
| 53 | `pr/C23-smp-test5` | `pr/C23-smp-test4` | `15867310` | test | S4 test | `test(pico2-rp2350b-psram): smp-test5` |
| 54 | `pr/C24` | `pr/C23-smp-test5` | `994cb864` | test | S4 board/harness | `test(pico2-pizero): the RP2350 on a Pi Zero form-factor carrier` |
| 55 | `pr/C24-exc-test` | `pr/C24` | `e450aaff` | test | S4 test | `test(pico2-pizero): exc-test` |
| 56 | `pr/C24-psram-exec` | `pr/C24-exc-test` | `ab90bf91` | test | S4 test | `test(pico2-pizero): psram-exec` |
| 57 | `pr/C24-psram-mat-test-250` | `pr/C24-psram-exec` | `76a2d22f` | test | S4 test | `test(pico2-pizero): psram-mat-test-250` |
| 58 | `pr/C24-sc-test-ko` | `pr/C24-psram-mat-test-250` | `25cb812e` | test | S4 test | `test(pico2-pizero): sc-test-ko` |
| 59 | `pr/C24-smp-mat-test` | `pr/C24-sc-test-ko` | `43d09f78` | test | S4 test | `test(pico2-pizero): smp-mat-test` |
| 60 | `pr/C24-smp-test-ko` | `pr/C24-smp-mat-test` | `395b0d10` | test | S4 test | `test(pico2-pizero): smp-test-ko` |
| 61 | `pr/C24-smp-test-usb-cdc-acm` | `pr/C24-smp-test-ko` | `038509f6` | test | S4 test | `test(pico2-pizero): smp-test-usb-cdc-acm` |
| 62 | `pr/C24-smp-test-usb-hid` | `pr/C24-smp-test-usb-cdc-acm` | `1eea852d` | test | S4 test | `test(pico2-pizero): smp-test-usb-hid` |
| 63 | `pr/C24-smp-test0` | `pr/C24-smp-test-usb-hid` | `044c5bde` | test | S4 test | `test(pico2-pizero): smp-test0` |
| 64 | `pr/C24-smp-test1` | `pr/C24-smp-test0` | `12570a64` | test | S4 test | `test(pico2-pizero): smp-test1` |
| 65 | `pr/C24-smp-test2` | `pr/C24-smp-test1` | `924b36a0` | test | S4 test | `test(pico2-pizero): smp-test2` |
| 66 | `pr/C24-smp-test3` | `pr/C24-smp-test2` | `807afed1` | test | S4 test | `test(pico2-pizero): smp-test3` |
| 67 | `pr/C24-smp-test4` | `pr/C24-smp-test3` | `cb72fb3e` | test | S4 test | `test(pico2-pizero): smp-test4` |
| 68 | `pr/C24-smp-test5` | `pr/C24-smp-test4` | `b6459bcb` | test | S4 test | `test(pico2-pizero): smp-test5` |
| 69 | `pr/C25-cmsis-os-validator` | `pr/C24-smp-test5` | `14bba6b7` | test | S4 test | `test(nucleof411): cmsis-os-validator` |
| 70 | `pr/C25-mos-test1` | `pr/C25-cmsis-os-validator` | `82c09863` | test | S4 test | `test(nucleof411): mos-test1` |
| 71 | `pr/C25-mutex-stress` | `pr/C25-mos-test1` | `5a3c8ec6` | test | S4 test | `test(nucleof411): mutex-stress` |
| 72 | `pr/C25-rtos-apis` | `pr/C25-mutex-stress` | `904bc935` | test | S4 test | `test(nucleof411): rtos-apis` |
| 73 | `pr/C26` | `pr/C25-rtos-apis` | `b695919a` | test | S4 board/harness | `test(weactf411): the WeAct Black Pill F411 board` |
| 74 | `pr/C26-cmsis-os-validator` | `pr/C26` | `3edc06c0` | test | S4 test | `test(weactf411): cmsis-os-validator` |
| 75 | `pr/C26-mos-test1` | `pr/C26-cmsis-os-validator` | `900c9402` | test | S4 test | `test(weactf411): mos-test1` |
| 76 | `pr/C26-mutex-stress` | `pr/C26-mos-test1` | `7b9526bb` | test | S4 test | `test(weactf411): mutex-stress` |
| 77 | `pr/C26-rtos-apis` | `pr/C26-mutex-stress` | `c8d67d58` | test | S4 test | `test(weactf411): rtos-apis` |
| 78 | `pr/C26-spi-pipeline` | `pr/C26-rtos-apis` | `6935c185` | test | S4 test | `test(weactf411): spi-pipeline` |
| 79 | `pr/C27` | `pr/C26-spi-pipeline` | `dc22fcdb` | test | S4 board/harness | `test(weactf412): the WeAct F412 board` |
| 80 | `pr/C27-cmsis-os-validator` | `pr/C27` | `a5f805b5` | test | S4 test | `test(weactf412): cmsis-os-validator` |
| 81 | `pr/C27-mos-test1` | `pr/C27-cmsis-os-validator` | `f2f0695c` | test | S4 test | `test(weactf412): mos-test1` |
| 82 | `pr/C27-mutex-stress` | `pr/C27-mos-test1` | `efa2b9a7` | test | S4 test | `test(weactf412): mutex-stress` |
| 83 | `pr/C27-rtos-apis` | `pr/C27-mutex-stress` | `bc32b726` | test | S4 test | `test(weactf412): rtos-apis` |
| 84 | `pr/C27-uart-test1` | `pr/C27-rtos-apis` | `efd8432c` | test | S4 test | `test(weactf412): uart-test1` |
| 85 | `pr/C28` | `pr/C27-uart-test1` | `72149579` | chore | S5 docs/chore | `chore: ignore every build* directory, the build products and the USB host tool` |
| 86 | `pr/C29` | `pr/C28` | `c5a71fbc` | docs | S5 docs/chore | `docs: README for the six boards and the generic QEMU cores` |

#### micro-os-plus-iii-aarch32 -- 64 pull requests (github.com/dan-maio/micro-os-plus-iii-aarch32)

| PR | Head branch (Commit-ID) | Base branch | SHA | Category | Stage / theme | Subject |
|---:|---|---|---|---|---|---|
| 1 | `pr/A32-01` | `xpack-development` | `03a0cfc1` | new code | S0 devices | `feat(drivers): import the neutral SD, flatfs, USB and FatFs drivers` |
| 2 | `pr/A32-02` | `pr/A32-01` | `c318b741` | new code | S0 devices | `feat(soc): import the BCM2837 (Raspberry Pi 3 B / Zero 2 W) SoC support` |
| 3 | `pr/A32-03` | `pr/A32-02` | `58cff47a` | new code | S0 devices | `feat(soc): import the RK3506 (Luckfox Lyra) SoC support` |
| 4 | `pr/A32-04` | `pr/A32-03` | `a8662d6e` | chore | S3 port | `chore: ignore every build* directory` |
| 5 | `pr/A32-05` | `pr/A32-04` | `b0eb0ed7` | new code | S3 port | `feat(port): AArch32 port declarations, application config and device header` |
| 6 | `pr/A32-06` | `pr/A32-05` | `81d97c4d` | new code | S3 port | `feat(port): ARMv7-A MMU bring-up` |
| 7 | `pr/A32-07` | `pr/A32-06` | `583aa440` | new code | S3 port | `feat(port): AArch32 exception vectors, IRQ dispatch and fault dump` |
| 8 | `pr/A32-08` | `pr/A32-07` | `4d9e3c1b` | new code | S3 port | `feat(port): ARM generic timer, and the high-resolution counter from CNTPCT` |
| 9 | `pr/A32-09` | `pr/A32-08` | `e510bd9f` | new code | S3 port | `feat(port): AArch32 context switch and the port half of the SMP scheduler` |
| 10 | `pr/A32-10` | `pr/A32-09` | `37b944cf` | new code | S3 port | `feat(port): secondary-core entry` |
| 11 | `pr/A32-11` | `pr/A32-10` | `6eb8c2aa` | new code | S3 port | `feat(port): semihosting console and a strong _Exit()` |
| 12 | `pr/A32-20` | `pr/A32-11` | `8cac0c56` | test | S4 board/harness | `test(rpi-zero-2w): the Raspberry Pi Zero 2 W board (BCM2837, 4x Cortex-A53, AArch32)` |
| 13 | `pr/A32-21` | `pr/A32-20` | `576597f0` | build | S4 board/harness | `build(cmake): the AArch32 port project, its board model and its test builder` |
| 14 | `pr/A32-T-smp_test0` | `pr/A32-21` | `0308bd45` | test | S4 test | `test(rpi-zero-2w): smp_test0` |
| 15 | `pr/A32-T-smp-mat-test` | `pr/A32-T-smp_test0` | `3f8b9a64` | test | S4 test | `test(rpi-zero-2w): smp-mat-test` |
| 16 | `pr/A32-T-cmsis-os-validator` | `pr/A32-T-smp-mat-test` | `8bccb4ee` | test | S4 test | `test(rpi-zero-2w): cmsis-os-validator` |
| 17 | `pr/A32-T-mutex-stress` | `pr/A32-T-cmsis-os-validator` | `cc8d43bb` | test | S4 test | `test(rpi-zero-2w): mutex-stress` |
| 18 | `pr/A32-T-rtos-apis` | `pr/A32-T-mutex-stress` | `f53d5e9e` | test | S4 test | `test(rpi-zero-2w): rtos-apis` |
| 19 | `pr/A32-T-sd_test` | `pr/A32-T-rtos-apis` | `286da73d` | test | S4 test | `test(rpi-zero-2w): sd_test` |
| 20 | `pr/A32-T-smp-mat-sdcard-test` | `pr/A32-T-sd_test` | `2bd8db32` | test | S4 test | `test(rpi-zero-2w): smp-mat-sdcard-test` |
| 21 | `pr/A32-T-smp-num-test` | `pr/A32-T-smp-mat-sdcard-test` | `4127ec3c` | test | S4 test | `test(rpi-zero-2w): smp-num-test` |
| 22 | `pr/A32-T-smp-pipeline-test` | `pr/A32-T-smp-num-test` | `89a1b78c` | test | S4 test | `test(rpi-zero-2w): smp-pipeline-test` |
| 23 | `pr/A32-T-smp-pro-cons-test` | `pr/A32-T-smp-pipeline-test` | `87ca7814` | test | S4 test | `test(rpi-zero-2w): smp-pro-cons-test` |
| 24 | `pr/A32-T-smp_test1` | `pr/A32-T-smp-pro-cons-test` | `98efc7ea` | test | S4 test | `test(rpi-zero-2w): smp_test1` |
| 25 | `pr/A32-T-smp_test2` | `pr/A32-T-smp_test1` | `3f4148c8` | test | S4 test | `test(rpi-zero-2w): smp_test2` |
| 26 | `pr/A32-T-smp_test3` | `pr/A32-T-smp_test2` | `d4443aca` | test | S4 test | `test(rpi-zero-2w): smp_test3` |
| 27 | `pr/A32-T-smp_test4` | `pr/A32-T-smp_test3` | `bd38979a` | test | S4 test | `test(rpi-zero-2w): smp_test4` |
| 28 | `pr/A32-T-usb_test` | `pr/A32-T-smp_test4` | `aa7fae53` | test | S4 test | `test(rpi-zero-2w): usb_test` |
| 29 | `pr/A32-R3` | `pr/A32-T-usb_test` | `aa0b83c0` | test | S4 board/harness | `test(rpi3b): the Raspberry Pi 3 B board (AArch32), sharing the Zero 2 W sources` |
| 30 | `pr/A32-R3-smp_test0` | `pr/A32-R3` | `22010a2c` | test | S4 test | `test(rpi3b): smp_test0` |
| 31 | `pr/A32-R3-cmsis-os-validator` | `pr/A32-R3-smp_test0` | `e0df39c7` | test | S4 test | `test(rpi3b): cmsis-os-validator` |
| 32 | `pr/A32-R3-mutex-stress` | `pr/A32-R3-cmsis-os-validator` | `b3666f39` | test | S4 test | `test(rpi3b): mutex-stress` |
| 33 | `pr/A32-R3-rtos-apis` | `pr/A32-R3-mutex-stress` | `832c71ae` | test | S4 test | `test(rpi3b): rtos-apis` |
| 34 | `pr/A32-R3-sd_test` | `pr/A32-R3-rtos-apis` | `8de31552` | test | S4 test | `test(rpi3b): sd_test` |
| 35 | `pr/A32-R3-smp-mat-sdcard-test` | `pr/A32-R3-sd_test` | `465e7d4a` | test | S4 test | `test(rpi3b): smp-mat-sdcard-test` |
| 36 | `pr/A32-R3-smp-mat-test` | `pr/A32-R3-smp-mat-sdcard-test` | `c80191d9` | test | S4 test | `test(rpi3b): smp-mat-test` |
| 37 | `pr/A32-R3-smp-num-test` | `pr/A32-R3-smp-mat-test` | `4359e4ce` | test | S4 test | `test(rpi3b): smp-num-test` |
| 38 | `pr/A32-R3-smp-pipeline-test` | `pr/A32-R3-smp-num-test` | `385f0938` | test | S4 test | `test(rpi3b): smp-pipeline-test` |
| 39 | `pr/A32-R3-smp-pro-cons-test` | `pr/A32-R3-smp-pipeline-test` | `b5235187` | test | S4 test | `test(rpi3b): smp-pro-cons-test` |
| 40 | `pr/A32-R3-smp_test1` | `pr/A32-R3-smp-pro-cons-test` | `436d38c9` | test | S4 test | `test(rpi3b): smp_test1` |
| 41 | `pr/A32-R3-smp_test2` | `pr/A32-R3-smp_test1` | `a121a4ca` | test | S4 test | `test(rpi3b): smp_test2` |
| 42 | `pr/A32-R3-smp_test3` | `pr/A32-R3-smp_test2` | `6b56b17f` | test | S4 test | `test(rpi3b): smp_test3` |
| 43 | `pr/A32-R3-smp_test4` | `pr/A32-R3-smp_test3` | `bd4569eb` | test | S4 test | `test(rpi3b): smp_test4` |
| 44 | `pr/A32-R3-usb_test` | `pr/A32-R3-smp_test4` | `a33a5cc0` | test | S4 test | `test(rpi3b): usb_test` |
| 45 | `pr/A32-LL` | `pr/A32-R3-usb_test` | `b468cbba` | test | S4 board/harness | `test(luckfox-lyra): the Luckfox Lyra B board (RK3506, 3x Cortex-A7, hardware only)` |
| 46 | `pr/A32-LL-smp_test0` | `pr/A32-LL` | `e617e017` | test | S4 test | `test(luckfox-lyra): smp_test0` |
| 47 | `pr/A32-LL-smp_test_int5` | `pr/A32-LL-smp_test0` | `067f4a19` | test | S4 test | `test(luckfox-lyra): smp_test_int5` |
| 48 | `pr/A32-LL-sd_test` | `pr/A32-LL-smp_test_int5` | `79eca794` | test | S4 test | `test(luckfox-lyra): sd_test` |
| 49 | `pr/A32-LL-smp-mat-sdcard-test` | `pr/A32-LL-sd_test` | `aa5a77ac` | test | S4 test | `test(luckfox-lyra): smp-mat-sdcard-test` |
| 50 | `pr/A32-LL-smp-mat-test` | `pr/A32-LL-smp-mat-sdcard-test` | `fcaeda34` | test | S4 test | `test(luckfox-lyra): smp-mat-test` |
| 51 | `pr/A32-LL-smp-num-test` | `pr/A32-LL-smp-mat-test` | `3f2f7a29` | test | S4 test | `test(luckfox-lyra): smp-num-test` |
| 52 | `pr/A32-LL-smp-pipeline-test` | `pr/A32-LL-smp-num-test` | `7c9a0205` | test | S4 test | `test(luckfox-lyra): smp-pipeline-test` |
| 53 | `pr/A32-LL-smp-pro-cons-test` | `pr/A32-LL-smp-pipeline-test` | `b42eaf86` | test | S4 test | `test(luckfox-lyra): smp-pro-cons-test` |
| 54 | `pr/A32-LL-smp_test1` | `pr/A32-LL-smp-pro-cons-test` | `bd934140` | test | S4 test | `test(luckfox-lyra): smp_test1` |
| 55 | `pr/A32-LL-smp_test2` | `pr/A32-LL-smp_test1` | `09b7ce26` | test | S4 test | `test(luckfox-lyra): smp_test2` |
| 56 | `pr/A32-LL-smp_test3` | `pr/A32-LL-smp_test2` | `0b58a238` | test | S4 test | `test(luckfox-lyra): smp_test3` |
| 57 | `pr/A32-LL-smp_test4` | `pr/A32-LL-smp_test3` | `9a0a34a0` | test | S4 test | `test(luckfox-lyra): smp_test4` |
| 58 | `pr/A32-LL-smp_test5` | `pr/A32-LL-smp_test4` | `979865e4` | test | S4 test | `test(luckfox-lyra): smp_test5` |
| 59 | `pr/A32-LL-smp_test6` | `pr/A32-LL-smp_test5` | `1cdf9eb1` | test | S4 test | `test(luckfox-lyra): smp_test6` |
| 60 | `pr/A32-LL-smp_test7` | `pr/A32-LL-smp_test6` | `0a1f7b1e` | test | S4 test | `test(luckfox-lyra): smp_test7` |
| 61 | `pr/A32-LL-smp_test_int` | `pr/A32-LL-smp_test7` | `3ce4a94a` | test | S4 test | `test(luckfox-lyra): smp_test_int` |
| 62 | `pr/A32-LL-smp_test_int2` | `pr/A32-LL-smp_test_int` | `d3f74a0f` | test | S4 test | `test(luckfox-lyra): smp_test_int2` |
| 63 | `pr/A32-LL-smp_test_int3` | `pr/A32-LL-smp_test_int2` | `d254ad93` | test | S4 test | `test(luckfox-lyra): smp_test_int3` |
| 64 | `pr/A32-LL-smp_test_int4` | `pr/A32-LL-smp_test_int3` | `0aa86aed` | test | S4 test | `test(luckfox-lyra): smp_test_int4` |

#### micro-os-plus-iii-aarch64 -- 43 pull requests (github.com/dan-maio/micro-os-plus-iii-aarch64)

| PR | Head branch (Commit-ID) | Base branch | SHA | Category | Stage / theme | Subject |
|---:|---|---|---|---|---|---|
| 1 | `pr/A64-01` | `xpack-development` | `b764bc98` | new code | S0 devices | `feat(drivers): import the neutral SD, flatfs, USB and FatFs drivers` |
| 2 | `pr/A64-02` | `pr/A64-01` | `fe04ec15` | new code | S0 devices | `feat(soc): import the BCM2837 (Raspberry Pi 3 B / Zero 2 W) SoC support` |
| 3 | `pr/A64-03` | `pr/A64-02` | `30822be2` | chore | S3 port | `chore: ignore every build* directory` |
| 4 | `pr/A64-04` | `pr/A64-03` | `f04d5ef5` | new code | S3 port | `feat(port): AArch64 port declarations, application config and device header` |
| 5 | `pr/A64-05` | `pr/A64-04` | `522cf173` | new code | S3 port | `feat(port): AArch64 MMU bring-up` |
| 6 | `pr/A64-06` | `pr/A64-05` | `265ce322` | new code | S3 port | `feat(port): AArch64 exception reporting and the static constructor runners` |
| 7 | `pr/A64-07` | `pr/A64-06` | `f5359a25` | new code | S3 port | `feat(port): ARM generic timer accessors (CNTFRQ_EL0, CNTPCT_EL0)` |
| 8 | `pr/A64-08` | `pr/A64-07` | `e04efa95` | new code | S3 port | `feat(port): AArch64 context frame and the port half of the SMP scheduler` |
| 9 | `pr/A64-09` | `pr/A64-08` | `ba24acc6` | new code | S3 port | `feat(port): secondary-core entry` |
| 10 | `pr/A64-10` | `pr/A64-09` | `7e796801` | new code | S3 port | `feat(port): semihosting console` |
| 11 | `pr/A64-20` | `pr/A64-10` | `9cafe2de` | test | S4 board/harness | `test(rpi-zero-2w): the Raspberry Pi Zero 2 W board (BCM2837, 4x Cortex-A53, AArch64)` |
| 12 | `pr/A64-21` | `pr/A64-20` | `475d0604` | build | S4 board/harness | `build(cmake): the AArch64 port project, its board model and its test builder` |
| 13 | `pr/A64-T-smp_test0` | `pr/A64-21` | `cca66872` | test | S4 test | `test(rpi-zero-2w): smp_test0` |
| 14 | `pr/A64-T-smp-mat-test` | `pr/A64-T-smp_test0` | `07d27cd6` | test | S4 test | `test(rpi-zero-2w): smp-mat-test` |
| 15 | `pr/A64-T-cmsis-os-validator` | `pr/A64-T-smp-mat-test` | `bc32bcd8` | test | S4 test | `test(rpi-zero-2w): cmsis-os-validator` |
| 16 | `pr/A64-T-mutex-stress` | `pr/A64-T-cmsis-os-validator` | `d87cebb7` | test | S4 test | `test(rpi-zero-2w): mutex-stress` |
| 17 | `pr/A64-T-rtos-apis` | `pr/A64-T-mutex-stress` | `99c5a5bf` | test | S4 test | `test(rpi-zero-2w): rtos-apis` |
| 18 | `pr/A64-T-sd_test` | `pr/A64-T-rtos-apis` | `d666d390` | test | S4 test | `test(rpi-zero-2w): sd_test` |
| 19 | `pr/A64-T-smp-mat-sdcard-test` | `pr/A64-T-sd_test` | `1731d0b1` | test | S4 test | `test(rpi-zero-2w): smp-mat-sdcard-test` |
| 20 | `pr/A64-T-smp-num-test` | `pr/A64-T-smp-mat-sdcard-test` | `edf06551` | test | S4 test | `test(rpi-zero-2w): smp-num-test` |
| 21 | `pr/A64-T-smp-pipeline-test` | `pr/A64-T-smp-num-test` | `8750df6e` | test | S4 test | `test(rpi-zero-2w): smp-pipeline-test` |
| 22 | `pr/A64-T-smp-pro-cons-test` | `pr/A64-T-smp-pipeline-test` | `5e0e5a65` | test | S4 test | `test(rpi-zero-2w): smp-pro-cons-test` |
| 23 | `pr/A64-T-smp_test1` | `pr/A64-T-smp-pro-cons-test` | `ed02a26b` | test | S4 test | `test(rpi-zero-2w): smp_test1` |
| 24 | `pr/A64-T-smp_test2` | `pr/A64-T-smp_test1` | `12c23d59` | test | S4 test | `test(rpi-zero-2w): smp_test2` |
| 25 | `pr/A64-T-smp_test3` | `pr/A64-T-smp_test2` | `216918dd` | test | S4 test | `test(rpi-zero-2w): smp_test3` |
| 26 | `pr/A64-T-smp_test4` | `pr/A64-T-smp_test3` | `87d619e3` | test | S4 test | `test(rpi-zero-2w): smp_test4` |
| 27 | `pr/A64-T-usb_test` | `pr/A64-T-smp_test4` | `5da24f9a` | test | S4 test | `test(rpi-zero-2w): usb_test` |
| 28 | `pr/A64-R3` | `pr/A64-T-usb_test` | `c84b8e00` | test | S4 board/harness | `test(rpi3b): the Raspberry Pi 3 B board (AArch64), sharing the Zero 2 W sources` |
| 29 | `pr/A64-R3-smp_test0` | `pr/A64-R3` | `b3fc5a12` | test | S4 test | `test(rpi3b): smp_test0` |
| 30 | `pr/A64-R3-cmsis-os-validator` | `pr/A64-R3-smp_test0` | `031d8f52` | test | S4 test | `test(rpi3b): cmsis-os-validator` |
| 31 | `pr/A64-R3-mutex-stress` | `pr/A64-R3-cmsis-os-validator` | `3ae3d571` | test | S4 test | `test(rpi3b): mutex-stress` |
| 32 | `pr/A64-R3-rtos-apis` | `pr/A64-R3-mutex-stress` | `e7bc6bc7` | test | S4 test | `test(rpi3b): rtos-apis` |
| 33 | `pr/A64-R3-sd_test` | `pr/A64-R3-rtos-apis` | `3e9f6e5a` | test | S4 test | `test(rpi3b): sd_test` |
| 34 | `pr/A64-R3-smp-mat-sdcard-test` | `pr/A64-R3-sd_test` | `ea725894` | test | S4 test | `test(rpi3b): smp-mat-sdcard-test` |
| 35 | `pr/A64-R3-smp-mat-test` | `pr/A64-R3-smp-mat-sdcard-test` | `0cce173e` | test | S4 test | `test(rpi3b): smp-mat-test` |
| 36 | `pr/A64-R3-smp-num-test` | `pr/A64-R3-smp-mat-test` | `d4f629c3` | test | S4 test | `test(rpi3b): smp-num-test` |
| 37 | `pr/A64-R3-smp-pipeline-test` | `pr/A64-R3-smp-num-test` | `a8082ca9` | test | S4 test | `test(rpi3b): smp-pipeline-test` |
| 38 | `pr/A64-R3-smp-pro-cons-test` | `pr/A64-R3-smp-pipeline-test` | `1ace669b` | test | S4 test | `test(rpi3b): smp-pro-cons-test` |
| 39 | `pr/A64-R3-smp_test1` | `pr/A64-R3-smp-pro-cons-test` | `84bceba9` | test | S4 test | `test(rpi3b): smp_test1` |
| 40 | `pr/A64-R3-smp_test2` | `pr/A64-R3-smp_test1` | `c045d19b` | test | S4 test | `test(rpi3b): smp_test2` |
| 41 | `pr/A64-R3-smp_test3` | `pr/A64-R3-smp_test2` | `fe5a5489` | test | S4 test | `test(rpi3b): smp_test3` |
| 42 | `pr/A64-R3-smp_test4` | `pr/A64-R3-smp_test3` | `ebf7dce3` | test | S4 test | `test(rpi3b): smp_test4` |
| 43 | `pr/A64-R3-usb_test` | `pr/A64-R3-smp_test4` | `a723ecc1` | test | S4 test | `test(rpi3b): usb_test` |


#### micro-os-plus-iii-devices -- 1 pull request (github.com/dan-maio/micro-os-plus-iii-devices)

| PR | Head branch (Commit-ID) | Base branch | SHA | Category | Stage / theme | Subject |
|---:|---|---|---|---|---|---|
| 1 | `pr/D01` | `smp` | (bundle) | docs | S0 devices | `docs: retire the repository -- its contents moved to the architecture ports` |

D01 is kept in `devices-retired.bundle` (the local clone was deleted after S0, §14.2). After it is merged, the repository is archived on GitHub.

### 22.4 Documentation updates after the migration (kernel PRs 126–159)
Made after the full test run, so that every document in `docs/` describes the executed state: Part III itself (K985); one commit per document (K986-*), which corrects stale facts in the reference documents (no `micro-os-plus-iii-devices`, no `UOS_DEVICES_DIR`, the current clone layout and the verified results) and adds a *Status 2026-10-06* note to the historical plans and reviews (their PDFs regenerated); the two commits that complete this section (K987, K988); and the verification record of §21.6 (K989). The upstream documents that do not concern the migration (`HISTORY`, `NOTES`, `TODO`, `posix-io-*`, `other-posix-systems`, `upstream-*`) are unchanged.

## 23. Regeneration of 2026-10-07: from the clone to the last `pr/` commit

The `smp` branches of all repositories were regenerated once more from `xpack-development`, in an empty `/tmp`. This section records how, the branches that resulted, and the test run.

### 23.1 Summary of the generation
| Step | What was done | Result |
|---:|---|---|
| 1 | **Clone** (§12.1): the six repositories from `github.com/dan-maio`; in the five code repositories the read-only `golden` remote (`~/Work2/micro-os-plus/<repo>`) and `git fetch golden smp`. | rc 0 |
| 2 | **Branch** `smp` from `origin/xpack-development`. In `micro-os-plus-iii` and `micro-os-plus-iii-posix-arch` the GitHub default branch is `smp`, so the clone already has a local `smp`; there `git switch -C smp origin/xpack-development` replaces `git switch -c`. | bases as §20.1 (table 23.2) |
| 3 | **aarch64 base check**: `git log --oneline 366c957...fe904c0` gives one commit, `fe904c0 package.json update`; `fe904c0` is used, as in §20.1. | — |
| 4 | **Install** (§13.3): `xpm install && xpm link` in posix-arch and cortexm, `xpm run install-all` in `micro-os-plus-iii/tests`; aarch32 and aarch64 `xpm install && xpm link` before the test run. | rc 0 for all |
| 5 | **Commits**: the commits of §22.3 were applied in §22.3 order with `git cherry-pick`, from the recorded branches of the 2026-10-06 replay (§21.6). Each new commit was compared with its recorded commit: the tree is identical at every commit, and Commit-ID, subject and order match §22.3 (376 rows; K989's SHA column reads "(this commit)"). | 376 commits, 0 tree differences |
| 6 | **Branches**: one local branch `pr/<Commit-ID>` per commit (table 23.3). | 376 branches |
| 7 | **Devices** (§14.2): D01 applied to the fresh devices clone, branch `pr/D01`, kept in `devices-retired-2026-10-07.bundle`; then the local devices clone was deleted. | — |
| 8 | **Full test run** (latest compilers, `ctest -LE hwd`): table 23.4. | all green |

Only the SHAs differ from §22.3, because the commit dates differ. Nothing was pushed.

### 23.2 Bases and results
| Repository | Base (`origin/xpack-development`) | Commits on `smp` | First PR branch | Last PR branch (`smp` tip) |
|---|---|---:|---|---|
| `micro-os-plus-iii` | `7f1ce5ca` | 159 | `pr/K01` `deb7dba1` | `pr/K989` `ccf87e89` |
| `micro-os-plus-iii-posix-arch` | `86a6a1f` | 24 | `pr/P01` `a2455e0a` | `pr/P36` `4ed05ad9` |
| `micro-os-plus-iii-cortexm` | `687e975` | 86 | `pr/C01` `995592d4` | `pr/C29` `71e98ff7` |
| `micro-os-plus-iii-aarch32` | `307c62f` | 64 | `pr/A32-01` `fba3b274` | `pr/A32-LL-smp_test_int4` `e721deab` |
| `micro-os-plus-iii-aarch64` | `fe904c0` | 43 | `pr/A64-01` `fd554718` | `pr/A64-R3-usb_test` `8151c26a` |
| `micro-os-plus-iii-devices` | `e8e39d5` (`smp`) | 1 | `pr/D01` (bundle) | `pr/D01` (bundle) |

This section is one more kernel commit after K989, `K990` (`pr/K990`), so the kernel `smp` tip is K990.

### 23.3 The `pr/` branches
- **One branch per commit.** Every commit of `smp` has a local branch `pr/<Commit-ID>`, where `<Commit-ID>` is the ID in the commit trailer `Commit-ID: <ID> (xpack-dev-smp.md Part II)`. Checked in each repository: number of `pr/*` branches = number of commits, no commit without a branch, no two branches on the same commit.
- **Stacked.** `pr/<ID>` points at its commit, whose parent is the previous commit, i.e. the previous `pr/` branch. The first branch of a repository sits on `xpack-development`; the last one is the `smp` tip.
- **One branch = one PR.** The PR for `pr/<ID>` has the previous `pr/` branch as its base (the first one has `xpack-development`); after a merge, the next PR is retargeted (§12.5). The cross-repository merge order is §22.2.
- **Local only.** The branches exist in each `/tmp/<repository>` clone; they are pushed to `github.com/dan-maio/<repository>` only when the PRs are opened.
- **This run's SHAs.** §22.3 lists the SHAs of the 2026-10-06 replay. The SHAs of this run are listed in each clone with:

```bash
git for-each-ref --sort=committerdate --format='%(refname:short) %(objectname:short=8) %(subject)' 'refs/heads/pr/*'
```

### 23.4 Full test run (µOS++ test framework, `ctest -LE hwd`)
Compilers: host gcc 16.2.1 for `native-cmake-sys`; xPack `arm-none-eabi-gcc` and `aarch64-none-elf-gcc` 15.2.1 for the cross builds.

| Action (in `micro-os-plus-iii/tests`) | Debug | Release |
|---|---|---|
| `xpm run test-native-cmake-sys` | 16/16 | 16/16 |
| `xpm run test-cortex-cmake` (qemu-cortex-m0, m3, m4f, m7f) | 3/3 each | 3/3 each |
| `test-aarch32-rpi-zero-2w-cmake` | 15/15 | 15/15 |
| `test-aarch32-rpi3b-cmake` | 15/15 | 15/15 |
| `test-aarch64-rpi-zero-2w-cmake` | 15/15 | 15/15 |
| `test-aarch64-rpi3b-cmake` | 15/15 | 15/15 (see below) |
| `test-2xcortex-m33-cmake` | 4/4 | 4/4 |
| `test-pico2-1cpu-cmake` | 4/4 | 4/4 |
| `test-cortexm-pico2-cmake` | 6/6 | 6/6 |
| `test-cortexm-pico2-rp2350b-psram-cmake` | 3/3 | 3/3 |

In the `xpm run test-smp-cmake` pass, `aarch64-rpi3b-smp-pipeline-test-qemu` (release) stopped after 5.5 s: QEMU exited with rc 1 after the `t= 4347 ms` progress line, without a `RESULT` line, and the action stopped there. Re-run alone, unchanged, it passed (35.6 s). The four remaining platforms were then run with their own `xpm run test-<platform>-cmake` actions, all rc 0. Like the stall recorded in §21.6, this is an intermittent behaviour of the SMP pipeline test under QEMU, to be investigated separately.
