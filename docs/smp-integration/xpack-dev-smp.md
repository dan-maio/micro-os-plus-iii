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

### 19.4 Size of the series (for planning)
| Repository | Commits (approx.) | Of which tests |
|---|---|---|
| micro-os-plus-iii | 29 + 10 + 13 + 1 + 14 + ~45 docs ≈ 110 | 1 suite + 13 platforms |
| posix-arch | 3 + 1 + 10 + 16 ≈ 30 | 16 |
| cortexm | 3 + 1 + 3 + 5 + 7 + 69 ≈ 88 | 69 |
| aarch32 | 3 + 9 + 4 + 36 + 19 ≈ 71 | 55 |
| aarch64 | 2 + 9 + 3 + 36 ≈ 50 | 36 |
| devices | 1 (retirement) | — |

Every row is one pull request. Tests and documents are small and add-only, so they review fast and can be merged in bulk once their builder or platform commit has landed.
