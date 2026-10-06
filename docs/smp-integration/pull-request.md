# Progressive Pull Request — SMP integration into `xpack-development`

*What to change, why, in which file, and with which code — step by step, from the
corrections to the SMP integration.*

This document turns the internal integration runbook
([`Implementation-SMP-Integration.md`](Implementation-SMP-Integration.md)) and the
per-file inventory ([`files-modif-by-step.md`](files-modif-by-step.md)) into a
**progressive pull request**: one reviewable change after another, starting with
the single-core corrections and ending with the multi-core (SMP) integration.

Everything below refers to the same model:

* **`smp`** — the branch that already contains the finished work (source of truth,
  never modified).
* **`xpack-development`** — the destination branch the work is rebuilt onto, one
  cohesive step at a time.
* Every step is **one commit** (tagged `step-NN-green`) and leaves the tree
  **green**: the frozen 72-test suite still passes, and for the SMP part the
  single-core projection is byte-identical to the previous step.

> **Table key.** `Repo`: **K** = `micro-os-plus-iii` (kernel) · **C** =
> `micro-os-plus-iii-cortexm` · **P** = `micro-os-plus-iii-posix-arch`. **How**:
> *whole* = `git checkout origin/smp -- <file>`; *projection* =
> `git show origin/smp:<file> | scripts/smp/sc-project.py > <file>` (strips the
> `OS_USE_SMP_SCHEDULER` / `NCPU>1` blocks); *surgical* = insert only the named
> hunk with `scripts/smp/chunks/_edit.py`. The executable form of every row is
> `scripts/smp/chunks/stepNN.sh`.

> **Synchronised with the branches.** This plan was checked against the actual
> `smp` and `xpack-development` trees and the recipes in `scripts/smp/chunks/`:
> every file listed appears in the `xpack-development..smp` diff, and the lift
> method matches the recipe (whole / `sc-project.py` / `_edit.py`). Three runbook
> realities are reflected: Part B is **collapsed into a single `step/14` commit**
> (steps 15–23 never get their own branch); `tests/smp-support/`, `native-smp` and
> the `test-smp-all` action are **created by the integration**, not present on
> `smp`; and the `src/libc/stdlib/timegm.c` change is deliberately **not** lifted
> (the baseline version is kept).

---

## 1. The pull request at a glance

| Field | Value |
|---|---|
| **Title** | SMP multi-core integration (progressive, bisectable series) |
| **Repositories** | `micro-os-plus-iii` · `-cortexm` · `-posix-arch` (and the add-only arch repos) |
| **Base branch** | `xpack-development` |
| **Head branch** | `step/30` (or the stacked `step/NN` chain) |
| **Source branch** | `smp` (read-only) |
| **Scope** | Part 0 → Part A (corrections) → Part B (SMP) → Part C (targets) → Part D (docs) |
| **Commits** | one per step (Part B is one collapsed `step/14` commit), each tagged `step-NN-green` |
| **Acceptance gate** | pristine check + 72/72 tests + `unifdef` invariant (Part B) + `test-smp-all` (Part C) |
| **Push policy** | nothing is pushed until the PR is opened by hand |

### 1.1 How the progressive PR is ordered

The order is **corrections → SMP evolution → SMP tests → new targets/tests →
final integration**, with the two infrastructure items (the `devices`
dissolution and the port releases) placed where their dependencies actually are,
not first.

| PR | Contents | Steps | Repos | Depends on |
|---|---|---|---|---|
| **#1** | Corrections (single-core correctness) | Part A (1–13) | K, +C+P at 13 | — |
| **#2** | SMP evolution (collapsed `step/14`) **+ the genuine `native-smp` dual-core platform, its configs and `test-native-smp`** | Part B (14–23) | K, C, P | #1 |
| **#3** | Port releases: `posix-arch v1.1.0`, `cortexm v1.2.0` | 24 | P, C | #2 |
| **#4** | Dissolve the `devices` repository | Part 0 | P, C, A32, A64 | #3 |
| **#5** | New cores/boards + modular CMake | 25–26 | K, C, P, arch | #2, #4 |
| **#6** | New test sources + add-only platforms (+ `test-smp-all`) | 27–28 | K, C, P, arch | #5 |
| **#7** | Documentation + final merge | 29–30 | all | #1–#6 |

PR head branches: `step/13` → `step/14` → `step/24` → `step/26` → `step/28` →
`step/30` (the intermediate `step/25` and `step/27` are commits inside PRs #5 and
#6). Part 0 (#4) is **out of band** on the port and architecture repos only — it
never touches the kernel — so it is applied on its own `part0-devices` branch
before #5 and is not in the kernel's linear chain. Part B is collapsed, so
`step/15`…`step/23` do not exist.

Two equivalent ways to use this:

* **One progressive PR** (recommended for a single reviewer): open #1, and add
  the later parts as new commits on the same head as they are accepted.
* **Stacked PRs** (recommended for a large review): open #1, then #2 against
  `step/13`, and so on; each merges into the one below it.

### 1.2 Order verification — is this optimal?

The phase order is forced by the dependency graph. Each claim below was checked
against the code, not by analogy.

| Question | Evidence | Verdict |
|---|---|---|
| Must the corrections come first? | Part B's Steps 9/10/13 build on Part A's `destroying` state, condvar `clock` and highres-clock port sync; Part A is valuable on its own and shrinks the SMP diff. | **Yes — first.** |
| Does Part B need Part 0 (dissolve `devices`)? | Neither port's `xpack-development` `CMakeLists.txt` references `devices`, and `part-b.sh` fix C deliberately does **not** apply `smp`'s `UOS_DEVICES_DIR` CMake. | **No.** Part 0 only unblocks the new boards, so it moves after Part B. |
| Does Part B have its own test? | `verify-step.sh` Stage 4 is only the NCPU=2 smoke, which the runbook documents as **fake** (a CMake cache variable never becomes a compile definition); the real `native-smp`/`2xcortex-m33` tests only arrive in Part C. | **No — the real gap.** Ship `native-smp` with Part B. |
| Do the new cores/boards need Part B? | The M33/RP2350 cores implement the SMP port contract introduced in Part B. | **Yes — after Part B.** |
| Do the new boards need Part 0? | `soc/rp2350`, `soc/stm32f4xx`, `soc/bcm2837` and the shared drivers come from `devices`. | **Yes — Part 0 before the new boards.** |
| Do the tests need the new cores/boards? | `2xcortex-m33` needs the M33 port (Step 25) and the modular CMake (Step 26). | **Yes — tests after evolutions.** |
| Is the final merge last? | Step 30 reconciles with `xpack-development` and restores `.github/**`. | **Yes — last.** |

The original packaging had three non-optimal points, now corrected: Part 0 was
first (it is independent of Part A/B), the port releases were buried inside the
tests PR (they publish the SMP evolution), and **Part B shipped without a genuine
dual-core test** (its only SMP check was the documented-fake smoke). The new
`native-smp` leg fixes the last one by landing the real dual-core test with the
code it tests.

### 1.3 Is each step self-contained?

Short answer: **each PR is self-contained; each individual step is a
self-contained *delta*, not a self-contained *feature*.** A step is green given
all the steps before it, but it is not meant to be applied to the baseline on its
own. Two forces break standalone independence — **atomic cross-repo/definition
steps** and **sequential in-file dependencies** — and Part B is not separable at
all.

| Unit | Self-contained? | Why (evidence) |
|---|---|---|
| Each **PR** (#1–#7) | **Yes**, given its base | `verify-step.sh` / `full-verify.sh` gate it; it builds and passes on the branch it targets. |
| Part A Steps 1–12 | Delta only | Applied in order; a later step may use an earlier symbol (e.g. Step 9's `destroying` state). |
| Step 13 | Delta **+ atomic across K, C, P** | K declares `has_hardware_counter()`, C/P define it; landing only the kernel breaks the link (the runbook's `qemu-cortex-m7f-release` failure). |
| Part B (14–23) | **Not separable** | One interwoven `#if defined(OS_USE_SMP_SCHEDULER)` blob; `part-b.sh` states "not per-step bisectable by design"; collapsed into one `step/14` commit. |
| Step 24 | Yes, given Part B | Version-only change (`package.json` `version`). |
| Step 25 | Yes, given Part B + Part 0 | New port files; atomic across C/P. |
| Step 26 | **Needs 25** | The M33 platform links the M33 port target. |
| Step 27 | **Needs 26** | The new suites are wired into the new M33 platform. |
| Step 28 | **Needs 26–27** | The AArch platforms use the harness and tests added before. |
| Part 0 | Yes (port/arch only) | Independent of the kernel; its gate is "boards that linked `devices` still build". |

Why some steps cannot stand alone:

* **Atomic definition + declaration.** Step 13 adds `port::clock_highres::
  has_hardware_counter()` in the kernel and its definition in the two ports; the
  two halves must be committed together or the link fails. Part B (Step 14) and
  Step 25 are the same: the kernel's `port_cpu_id()` and the port's definition,
  or the M33 core and its CMake target, travel together.
* **In-file chaining.** `os-c-wrapper.cpp` is touched by Steps 4, 9 and 20;
  `os-thread.{h,cpp}` by 1, 7, 9, 14 and 20; `os-c-decls.h` by 9, 10 and 16;
  `os-core.cpp` by 14–22. The recipes use **whole / projection / surgical**
  lifting so each step carries only *its* hunks — but it still assumes the
  earlier steps are already in place (see §11.2).
* **Deliberate coupling.** Step 4 strips the Step-9 `destroying` `static_assert`
  because it does not compile yet; Step 7 keeps Step-9/20 content out to avoid
  `-Werror=switch-enum`. The steps are curated to *avoid* pulling the future in,
  not to make each one buildable from the baseline.

The rule the recipes enforce: a step may lift a **partial file**, but never a
**partial dependency** — a declaration and its definition, or a test and the
platform it runs on, always travel in the same step (or PR).

---

## 2. Phase 0 — Dissolve the `devices` repository (PR #4 · Part 0)

**Why the whole part.** `xpack-development` has six components; `smp` adds a
seventh, `micro-os-plus-iii-devices`. Upstream has no such repo and nowhere to
put one. Folding its code (history-preserving `git subtree`) into the
architecture repos that already own it lets the rest of the integration proceed
with the six repos upstream has.

| Repo | What | Why | File / path | How (code) |
|---|---|---|---|---|
| P | Move the native SoC | host SD-image backend belongs to the host port | `soc/native/` | `git subtree add -P soc/native <devices> split/soc_native` |
| P | Move the shared drivers | block/FatFs/USB drivers are portable C++, used by boards | `drivers/include/`, `drivers/src/`, `drivers/fatfs/` | `git subtree add -P drivers/... <devices> split/...` |
| P | Carry driver fixes | atomic-spinlock mailbox; flatfs append-to-empty allocates an extent | `src/.../mailbox`, `fatfs` | part of the subtree move |
| C | Move the STM32F4xx SoC | Cortex-M silicon owned by the Cortex-M port | `soc/stm32f4xx/` | `git subtree add -P soc/stm32f4xx <devices> split/soc_stm32f4xx` |
| C | Move the RP2350 SoC | Pico 2 headers + `system_rp2350.c` | `soc/rp2350/` | `git subtree add -P soc/rp2350 <devices> split/soc_rp2350` |
| A32/A64 | Move drivers + `bcm2837` | each arch repo must be self-contained (no cross-repo dep) | `drivers/`, `soc/bcm2837/` | `git subtree add ...` |
| P, C, A32, A64 | Re-declare the old CMake target names | so every board that linked `micro-os-plus::devices` keeps working | `CMakeLists.txt` (shim) | `add_library(... INTERFACE)` + `add_library(micro-os-plus::devices ALIAS ...)` |

**Gate for PR #4:** every board that linked a `devices` target still configures
and builds; the standalone `devices` repo is no longer a dependency.

---

## 3. Phase A — Corrections: single-core correctness (PR #1 · Steps 1–13)

**Why the whole part.** These fixes are correct and valuable **without** SMP.
Landing them first keeps each step bisectable and makes Part B a pure SMP diff.

### 3.1 Steps

| Step | What | Why | File | Code / how | Gate |
|---|---|---|---|---|---|
| **1** | ISO C conformance, list iterators, exported suspend, newlib return type | host glibc double-declares `DIR`; intrusive-list iterators must conform; the C wrapper must resolve `thread::suspend`; newlib's `read`/`write` return type must match the weak alias | `include/cmsis-plus/posix/dirent.h`, `include/cmsis-plus/utils/lists.h`, `include/cmsis-plus/posix-io/c-syscalls-aliases-standard.h`, `src/rtos/os-thread.cpp` | whole for the three headers — `c-syscalls-aliases-standard.h` defines `CMSIS_PLUS_POSIX_IO_RW_RETURN_TYPE` as newlib's `_READ_WRITE_RETURN_TYPE` (or `ssize_t`); surgical: remove `inline` from `this_thread::suspend` in `os-thread.cpp`. **Keep baseline** `src/libc/stdlib/timegm.c` | 72/72 |
| **2** | Memory: overflow, usable size, calloc/realloc, block-pool | header decl + base definition + override must land together or `memory_resource::do_usable_size` is undefined; overflow guards | `include/cmsis-plus/rtos/os-memory.h`, `include/cmsis-plus/memory/first-fit-top.h`, `src/rtos/os-memory.cpp`, `src/memory/first-fit-top.cpp`, `src/memory/lifo.cpp`, `src/memory/block-pool.cpp`, `src/libc/stdlib/malloc.cpp` | whole (7 files); add `-Wcast-align`/`-Wunsafe-buffer-usage` pragma wrap in `first-fit-top.cpp`; calloc guard `if (nelem != 0 && elbytes > (SIZE_MAX / nelem)) { errno = ENOMEM; return nullptr; }` | 72/72; `mutex-stress` + allocator paths |
| **3** | C++17 aligned new/delete, static error category, chrono | aligned allocation; exit-time-destructor warning; 64-bit overflow | `src/libcpp/new.cpp`, `src/libcpp/system-error.cpp`, `src/libcpp/chrono.cpp` | whole; add clang `-Wexit-time-destructors` suppression for the two Meyers-singleton categories; `(cyc/f)*1e9 + (cyc%f)*1e9/f` | 72/72 |
| **4** | C wrapper: one-shot timer, polymorphic delete, 64-bit timeouts | correct timer default; delete the right type; cast to 64-bit before `* 1000u` | `src/rtos/os-c-wrapper.cpp` | whole, then **strip** Step-9 `destroying` static_assert and Step-20 SMP affinity blocks | 72/72 |
| **5** | POSIX I/O thread-safety | descriptor-table race; free-list race; inverted size check | `src/posix-io/file-descriptors-manager.cpp`, `include/cmsis-plus/posix-io/file-system.h`, `include/cmsis-plus/posix-io/net-stack.h`, `src/posix-io/block-device.cpp` | whole; add `-Wunsafe-buffer-usage` suppression in the fd manager; `if (size == 0) return EINVAL;` | 72/72 |
| **6** | ARMv8-M guards, SecureFault, semihosting fstat | M33 build; fault handler; `S_IFCHR` only when no type set | `include/cmsis-plus/arm/semihosting.h`, `src/startup/exception-handlers.c`, `src/semihosting/c-syscalls-semihosting.cpp` | whole; add `__ARM_ARCH_8M_MAIN__`/`__ARM_ARCH_8M_BASE__` guards + `SecureFault_Handler`; add weak `os_board_console_mirror()` | 72/72 |
| **7** | Timer callback outside the critical section | avoid running user code while the lock is held; periodic catch-up re-arm | `src/rtos/internal/os-lists.cpp`, `src/rtos/os-timer.cpp`, `include/cmsis-plus/rtos/os-thread.h` | whole for the two sources; **surgical** errno-scratch hunk into `os-thread.h` (keep Step-9/20 out) | 72/72 |
| **8** | Mutex priority ceiling | set ceiling before ownership; boost to max waiter; recompute owner priority on unlock | `src/rtos/os-mutex.cpp` | whole | 72/72 |
| **9** | Thread lifecycle: `state::destroying`, atomic join, detach, reaper | race-free destruction/join; single-lock register/suspend | `include/cmsis-plus/rtos/os-thread.h`, `src/rtos/os-thread.cpp`, `src/rtos/os-idle.cpp`, `include/cmsis-plus/rtos/os-c-decls.h` | **projection** for the three (`os-thread.cpp` has ~37 SMP hunks); **surgical** `destroying = 7` into `os-c-decls.h` (keep Step-10 `void* clock` out) | 72/72 |
| **10** | Condition-variable atomicity | link-then-unlock-then-suspend; bind `timed_wait` to the attribute clock | `src/rtos/os-condvar.cpp`, `include/cmsis-plus/rtos/os-condvar.h`, `include/cmsis-plus/diag/instrumentation.h`, `include/cmsis-plus/rtos/os-c-decls.h` | whole for the three; **surgical**: uncomment only `os_condvar_t`'s `void* clock`; add `OS_INTEGER_INSTRUMENTATION_SUSPEND_CAUSE_CONDVAR (12)` | 72/72 |
| **11** | `std::thread` functor lifetime & join | join the native handle before delete; deterministic free | `src/libcpp/thread-cpp.h`, `include/cmsis-plus/estd/thread_internal.h` | whole | 72/72 |
| **12** | Message-queue reschedule | preempt after a send/receive wakes a higher-priority thread | `src/rtos/os-mqueue.cpp` | whole; `port::scheduler::reschedule()` after the critical section in all 6 paths | 72/72 |
| **13** | High-resolution clock port sync (**first cross-repo step: K + C + P**) | declare/call `has_hardware_counter()`; fix SysTick pending test; read `CLOCK_MONOTONIC` | K: `include/cmsis-plus/rtos/os-decls.h`, `src/rtos/os-clocks.cpp`; C: `include/cmsis-plus/rtos/port/os-inlines.h`; P: same file | K whole; C **projection** (`has_hardware_counter()→false`, `hardware_counter()→0`); P **surgical** insert of only the `clock_highres` block | 72/72 |

> **Step 1 completeness note.** The runbook's detailed Step-1 table also lists
> `include/cmsis-plus/posix-io/c-syscalls-aliases-standard.h`; the current
> `chunks/step01.sh` lifts only `dirent.h`, `lists.h` and the surgical
> `os-thread.cpp` edit. Include the aliases header when building this PR to cover
> the newlib `_READ_WRITE_RETURN_TYPE` fix (it is a real `xpack-development..smp`
> change).

### 3.2 The one code fix that is easy to get wrong (Step 13)

```cpp
// C: include/cmsis-plus/rtos/port/os-inlines.h
inline clock_highres::timestamp_t clock_highres::cycles_since_tick (void) {
  uint32_t load = SysTick->LOAD, val = SysTick->VAL;
  if ((SCB->ICSR & SCB_ICSR_PENDSTSET_Msk) && (val > (load / 2)))
    return (load - val) + load;
  return load - val;
}
```

---

## 4. Phase B — SMP infrastructure (PR #2 · Step 14 / Steps 14–23 collapsed)

**Why one blob.** Unlike Part A, all ten steps' SMP code is interleaved inside the
same `#if defined(OS_USE_SMP_SCHEDULER)` blocks in the same files. The whole set
lands as **one commit** (`step/14`, recipe `chunks/part-b.sh`) across the three
repos, then the hardening fixes A–J are applied. **Every** change is inside the
`OS_USE_SMP_SCHEDULER` guard, so the single-core binary is unchanged (proved by
`unifdef`). The ten rows below are the conceptual sub-steps of that one commit;
steps 15–23 do not exist as separate branches.

### 4.1 The SMP steps

| Step | What | Why | File | Code / how |
|---|---|---|---|---|
| **14** | `port_cpu_id()` | identify the current core; TLS on the host, constant 0 on single-core Cortex-M | K: `src/rtos/os-core.cpp`, `os-thread.cpp`; C: `os-inlines.h`; P: `src/rtos/os-core.cpp` | P: `thread_local unsigned _this_cpu = 0; extern "C" __attribute__((noinline)) unsigned port_cpu_id(void){ asm volatile("":::"memory"); return _this_cpu; }` |
| **15** | Per-CPU scheduler lock `lock_state[OS_NCPU]` | one scheduler lock per core | K+P+C `src/rtos/os-core.cpp` | scalar → array; in P mask `SIGALRM` before reading `port_cpu_id()` |
| **16** | Recursive kernel lock `_smp_klock` | serialize kernel entry/exit across cores | `include/cmsis-plus/rtos/port/os-decls.h`, `os-c-decls.h` | `struct smp_klock_t { atomic lock; owner; count; }`; `_smp_klock_enter/exit`; clear owner **before** the release store; `SMP_NO_OWNER 0xFFFFFFFFU` |
| **17** | Per-CPU interrupt tracking | know if the current core is in handler mode | P `os-decls.h` | `irq_set` + `_in_isr[OS_NCPU]`; `in_handler_mode()` reads `_in_isr[port_cpu_id()]` |
| **18** | Per-CPU current thread `current_thread_[OS_NCPU]` | each core has its own running thread | `os-sched.h` | array; `this_thread::thread()` reads `[port_cpu_id()]` with local IRQs masked |
| **19** | Per-CPU idle threads `os_idle_thread_core[OS_NCPU]` | every core needs an idle context | K+C+P `os-idle.cpp` | each core registers its private idle context at boot |
| **20** | CPU affinity mask | pin threads to cores; main thread to core 0 | `os-thread.cpp` | `th_cpu_affinity` (default `0xFFFFFFFF`), `cpu_affinity()` API, main pinned to `1U<<0` |
| **21** | 5-stage deferred publish/claim | hand a thread between cores without losing the stack pointer | K+C+P | claim (`to->stack_ptr=nullptr`) → spill → SP switch → publish (`from->stack_ptr=sp`, release) → restore; picker gate `state_ != running && stack_ptr != nullptr` |
| **22** | SMP ready-list picker | choose the highest-priority runnable thread for this core | `os-core.cpp` `internal_switch_threads` | `(affinity & (1<<cpu))` and published stack; else `os_idle_thread_core[cpu]` |
| **23** | POSIX host multiprocessing / IPI | model cores as pthreads; wake a core by signal | P `src/host_cpu.cpp`, `include/host_cpu.hpp`; K weak `port_smp_ipi` | spawn `OS_NCPU` pthreads; per-CPU `timer_create(SIGEV_THREAD_ID)`; IPI via `pthread_kill(.., SIGRTMIN+1)` |

### 4.2 The files lifted for Part B

| Repo | Files (whole, SMP versions) |
|---|---|
| **K** | `include/cmsis-plus/rtos/os-c-decls.h`, `os-sched.h`, `os-thread.h`; `src/rtos/os-c-wrapper.cpp`, `os-core.cpp`, `os-idle.cpp`, `os-main.cpp`, `os-thread.cpp` |
| **C** | `include/cmsis-plus/rtos/port/os-c-decls.h`, `os-decls.h`, `os-inlines.h`; `src/rtos/os-core.cpp` |
| **P** | `include/cmsis-plus/rtos/port/os-c-decls.h`, `os-decls.h`, `os-inlines.h`; `include/host_cpu.hpp`, `exception_handler.hpp`, `hw_result.hpp`; `src/host_cpu.cpp`, `free-store.cpp`, `board-contract.cpp`, `exception_handler.cpp`, `src/rtos/os-core.cpp` |

### 4.3 The lift-time corrections (fixes A–J)

| Fix | What | Why | File | Code |
|---|---|---|---|---|
| **A/B** | `struct timespec tp;` → `timespec tp;` | baseline gate is `-Werror=redundant-tags` | P `os-inlines.h` | drop the `struct` tag |
| **C** | Register new SMP sources **additively** | keep the xpack INTERFACE model, not smp's standalone `UOS_SMP_DIR` | P `CMakeLists.txt` | append to `target_sources(... INTERFACE)`; do **not** build `board-contract.cpp` here |
| **D** | Register `host_cpu.cpp`, `free-store.cpp`, `exception_handler.cpp` | the refactored always-compiled `os-core.cpp` delegates to them | P `CMakeLists.txt` | `target_sources(... INTERFACE src/host_cpu.cpp src/free-store.cpp src/exception_handler.cpp)` |
| **E** | Drop redundant `port_cpu_id` decl; declare `port_smp_ipi` | `-Werror=missing-declarations` | P `host_cpu.cpp` | remove dup decl; add prior prototype for the strong override |
| **F/G** | Remove redundant `port_cpu_id` decl; weak `g_core_stage[]` | `-Werror=redundant-decls`; symbol only defined by the SMP test board | P `exception_handler.cpp` | add a port-side weak definition of `g_core_stage[OS_NCPU]` |
| **H** | Wrap kernel `port_cpu_id` redundant decls | `-Werror=redundant-decls` only under a true SMP compile | K `os-core.cpp`, `os-thread.cpp` | `#pragma GCC diagnostic ignored "-Wredundant-decls"` |
| **I/J** | clang `-Weverything` hardening | destination is stricter than `smp` | P port headers + SMP `.cpp` | add `-Wc++98-compat-pedantic` / `-Wreserved-identifier` / `-Wunsafe-buffer-usage`; suppression block before includes |

### 4.4 The dual-core test that must ship with Part B (`native-smp`)

Part B's own gate (`verify-step.sh` Stage 4) is only a smoke build, and the
runbook records that the original NCPU=2 command-line build was **fake** — the
`-D` values became CMake cache variables, not compile definitions, so the code
built single-core and the "SMP" run proved nothing. The only way SMP is truly on
is a platform that sets the defines via `target_compile_definitions`. The
`native-smp` platform does exactly that, so it belongs in PR #2:

| What | Why | File | Code |
|---|---|---|---|
| Add the `native-smp` platform | a genuine dual-core host platform is the only real SMP test for Part B | `tests/platforms/native-smp/` (mirrors `native`; links `micro-os-plus::iii-posix-arch` + libucontext) | `target_compile_definitions(... PRIVATE OS_INTEGER_RTOS_PORT_NCPU=2 OS_USE_SMP_SCHEDULER=1)` |
| Add its configs and actions | run it from xpm | `tests/package.json` (append-only) | `native-smp-cmake-gcc14-debug/release`; `test-native-smp`; introduce `test-smp-all` with this leg |
| Wire it into the harness | select the platform | `tests/cmake/tests-main.cmake` (additive) | platform chosen by `PLATFORM_NAME` |

This is the change that surfaced kernel fix **H** (the `port_cpu_id`
redundant-decl clash under a real SMP compile), already in `part-b.sh`.
`2xcortex-m33` stays in PR #6 because it also needs the M33 port (Step 25) and
the modular CMake (Step 26).

**Gate for PR #2:** pristine check + `unifdef -UOS_USE_SMP_SCHEDULER` single-core
delta = 0 + 72/72 + the genuine `native-smp` dual-core suite (`rtos-apis-test`,
`mutex-stress-test`, `cmsis-os-validator-test`).

---

## 5. Phase C1 — Port releases (PR #3 · Step 24)

**Why now.** The releases publish the SMP port model that Part B just landed;
they depend only on Part B, not on the new boards or tests, so they are their own
small PR rather than being buried in the tests PR.

| Step | What | Why | File / path | How |
|---|---|---|---|---|
| **24** | Port releases | publish the SMP port model (`posix-arch v1.1.0`, `cortexm v1.2.0`) | P/C `package.json` (`version` only) | `release-port.sh` edits `version` in Python and tags by hand — **never** `npm version`, which runs `postversion` and pushes |

**Gate for PR #3:** the release commits touch only the `version` line; both tags
exist locally only; the port branches still build.

---

## 6. Phase C2 — New cores/boards + modular CMake (PR #5 · Steps 25–26)

**Why here.** These are **evolutions**: the M33 and RP2350 cores and the additive
CMake that lets a new platform link the fat `::iii` without touching the existing
targets. They need Part B (the SMP port contract) and Part 0 (the SoC code), and
they unblock the tests in PR #6.

| Step | What | Why | File / path | How |
|---|---|---|---|---|
| **25** | New cores/boards | M33 and RP2350 support | C `include-m33/`, `include-rp2350/`, `os-core-m33.cpp`, `os-core-rp2350.cpp`; P `board-contract.cpp`, `free-store.cpp`, `exception_handler.*`; K IPI in `thread::resume()` | add-only from `origin/smp` |
| **26** | Modular CMake (integrated, add-only) | build the new M33 target without breaking the fat `::iii` | C `CMakeLists.txt` (additive `micro-os-plus::cortexm-qemu-m33`); K `CMakeLists.txt` (additive harness sub-targets `micro-os-plus::iii-core`, `::iii-posix-io`, `::port-smp-decls`, `::test-support` + re-inclusion guard); `tests/platforms/2xcortex-m33/`; `tests/device-qemu-cortexm-m33/`; `tests/package.json` config + action | append the port target; new platform links the **fat** `::iii`; self-contained device; `mps2-an521 --cpu cortex-m33 --smp 2` |

**Gate for PR #5:** the original `xpm run test-all` (72) still green; the new M33
platform configures and builds.

---

## 7. Phase C3 — New test sources + add-only platforms (PR #6 · Steps 27–28)

**Why here.** These are the **tests**: existing, proven `smp` suites promoted
add-only, plus the AArch platforms. They need the cores/boards from PR #5.

| Step | What | Why | File / path | How |
|---|---|---|---|---|
| **27** | New test sources | prove SMP on the new architectures | `tests/sources/fp-switch/`; `tests/smp-support/` (dissolved `test_smpl/`); smp tests 0–5; AN505/AN521 linker scripts | `absorb-test-smpl.sh`; append `set(ENABLE_FP_SWITCH_TEST true)` to `global-definitions.cmake` |
| **28** | Add-only platforms and harness wiring | run the suites on new targets | `tests/platforms/2xcortex-m33`, `cortexm-pico2`, `aarch32-rpi3b`, `aarch64-rpi3b` (the `native-smp` leg already landed in PR #2); `tests/cmake/tests-main.cmake` (additive); `tests/package.json` | `integrate-aarch-harness.sh` wires AArch32/64 platforms and dev-linked `aarch*-actions` in `package.json` (auto `xpm link` in `install`, `link-deps`, `link-deps-all`); extend `test-smp-all` with M33/aarch legs |

**Gate for PR #6:** the original `xpm run test-all` (72) still green **and**
`xpm run test-smp-all` green.

---

## 8. Phase D — Documentation and final merge (PR #7 · Steps 29–30)

| Step | What | Why | File | Code |
|---|---|---|---|---|
| **29** | Documentation | keep the runbook/PDF in step with the code | `docs/*.md`, `docs/*.pdf`, `docs/render-pdfs.sh` | `cd docs && ./render-pdfs.sh Implementation-SMP-Integration` |
| **30** | Final merge (local) | reconcile with upstream and drop dev tooling | all repos; remove `scripts/smp/` | merge `origin/xpack-development`; restore `.github/`, `README`, `LICENSE`; `finalize.sh`; run both gates |

**Gate for PR #7:** clean doc build; full ecosystem `test-all` + `test-smp-all`;
`.github`/`README`/`LICENSE` byte-identical to baseline.

---

## 9. Per-step commands (the progressive loop)

One step = four commands. Nothing is pushed.

| # | Command | What it does |
|---|---|---|
| 1 | `scripts/smp/new-step.sh NN` | fork `step/NN` from the most recent existing step branch (or the repo's `xpack-development`) |
| 2 | `scripts/smp/chunks/stepNN.sh` (or `chunks/part-b.sh` for the collapsed `step/14`) | apply the exact files + corrections for the step |
| 3 | `scripts/smp/verify-step.sh NN` | pristine check → `unifdef` (Part B / `step/14`) → link ports → 72/72 tests |
| 4 | `scripts/smp/advance-step.sh NN "message"` | commit the touched repos and tag `step-NN-green` |

Drive Part A and the collapsed Part B with `scripts/smp/run-loop.sh 1 14`, then
Part C with `scripts/smp/run-loop.sh 24 30`; finish with `full-verify.sh`
(mandatory), then `finalize.sh`.

---

## 10. Opening the pull request (manual, by hand)

Nothing is automated up to this point. When the series is green locally, open the
progressive PR yourself:

```sh
git -C "$WORK/micro-os-plus-iii" push origin step/30

gh pr create --repo micro-os-plus/micro-os-plus-iii \
  --base xpack-development --head step/30 \
  --title "SMP multi-core integration (progressive, bisectable series)" \
  --body-file docs/smp-integration/pull-request.md
```

For the stacked variant, open each against the previous head: #2
`--base step/13`, #3 `--base step/14`, #5 `--base step/24`, #6 `--base step/26`,
#7 `--base step/28`. #4 (`part0-devices`) bases on the port branch from #3; it is
out of band, so #5's port side is rebased on it before review.

---

## 11. Review and bisect guide

| Reviewer question | Where to look | What proves it |
|---|---|---|
| Did the test framework stay frozen? | `scripts/smp/check-pristine.sh` | existing `package.json`/`tests/**`/`.github/**` entries never modified or deleted |
| Is the single-core binary unchanged in Part B? | `verify-step.sh` Stage 1 | `unifdef -UOS_USE_SMP_SCHEDULER` projection is identical to the previous step |
| Does every step build and pass? | `verify-step.sh NN` | 72/72 (24 builds × 3 tests) with `-Werror` |
| Which commit introduced a regression? | `git bisect` over `step-NN-green` tags | each tag is a labelled green checkpoint |
| Is the full ecosystem green? | `full-verify.sh` | real `xpm install → link-deps → prepare → build → test` per config |

### 11.1 Pass criteria per part

| Part | Steps | Pristine rule | Extra gate |
|---|---|---|---|
| Part A | 1–13 | total freeze | 72/72 |
| Part B | 14–23 | total freeze | 72/72 **+** `unifdef` invariant **+** `native-smp` dual-core suite |
| Part C | 24–28 | append-only | 72/72 **+** `test-smp-all` |
| Part D | 29–30 | not gated (restores `.github/**`) | doc build + both suites |

### 11.2 Files that carry several steps (lift carefully)

| File | Steps | Watch for |
|---|---|---|
| `src/rtos/os-c-wrapper.cpp` | 4, 9, 20 | `os_thread_state_destroying`, SMP affinity `#if` |
| `src/rtos/os-thread.cpp` | 1, 9, 14, 20 | exported symbol (1), destroying/join (9), `port_cpu_id`/affinity (14, 20) |
| `include/cmsis-plus/rtos/os-thread.h` | 1, 7, 9, 14, 20 | errno hunk (7), destroying enum (9), affinity (14, 20) |
| `include/cmsis-plus/rtos/os-c-decls.h` | 9, 10, 16 | `destroying = 7` (9), `os_condvar_t` `void* clock` (10), `smp_klock` (16) |
| `src/rtos/os-core.cpp` | 14, 15, 16, 18, 19, 22 | almost entirely Part B, all under `#if` |

---

## 12. Quick reference — what / why / file / code

| Phase | What | Why | Files | Code (representative) |
|---|---|---|---|---|
| Part 0 | Fold `devices` into arch repos | upstream has no seventh repo | `soc/*`, `drivers/*`, CMake shims | `git subtree add -P <path> <devices> split/<sub>` |
| Part A | 13 single-core fixes | correct and valuable without SMP; keep Part B pure | `include/**`, `src/**`, ports | `git checkout origin/smp -- <files>` / `sc-project.py` / `_edit.py` |
| Part B | SMP scheduler, locks, IPI | multi-core support | `os-core.cpp`, `os-sched.h`, port headers, `host_cpu.cpp` | inside `#if defined(OS_USE_SMP_SCHEDULER)`; `_smp_klock`, `current_thread_[OS_NCPU]` |
| Part C | New targets and tests | add-only coverage for M33/RP2350/AArch | `tests/platforms/**`, `tests/sources/**` | append `test-smp-all`; `target_compile_definitions(... OS_USE_SMP_SCHEDULER=1)` |
| Part D | Docs + final merge | land the series cleanly | `docs/**`, `.github/**` | `finalize.sh`; open PR by hand |

---

## 13. Appendix — Dedicated Raspberry Pi Pico 2 (`cortexm-pico2`) Hardware Platform Wiring (PR #8 · Step 31)

**Why:** Configures complete standalone hardware testing infrastructure for physical Raspberry Pi Pico 2 silicon (RP2350 dual ARM Cortex-M33).

| Step | What | Why | File / path | How |
|---|---|---|---|---|
| **31** | Dedicated Pico 2 hardware platform | Hardware testing on physical RP2350 silicon; secondary core SIO boot mailbox handshake | C `src/rtos/os-core-rp2350.cpp`, `test/boards/pico2/`, `test/pico2/`; K `tests/platforms/cortexm-pico2/` | standalone hardware SWD / OpenOCD configuration; SIO FIFO wake-up sequence |

> **The one rule that keeps the series trustworthy:** never define
> `OS_USE_SMP_SCHEDULER` on the `cmake`/`xpm` command line (a cache variable does
> not become a compile flag). It must come from a platform's
> `target_compile_definitions`, and you must see it on the real compile line
> (`cmake --build <dir> -v`). Otherwise the "SMP" build is silently single-core.

