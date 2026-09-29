# How to bring `smp` into `xpack-development`, step by step

## 1. The situation

There are two versions of the same project, in
`github.com/dan-maio/micro-os-plus-iii`:

| branch | what it is | last commit |
|---|---|---|
| `xpack-development` | Liviu's official version. The kernel runs on **one CPU core**. Its tests must always pass. | `3a22a06b` (2026-09-20) |
| `smp` | Our version. It adds **multi-core support** (several CPU cores run threads at the same time), plus many bug fixes, new tests, new boards and documents. | `1a728371` (2026-09-29) |

The kernel does not work alone. Every build uses a **port**, the part that
knows the processor. The official tests use two ports:

| port repository | used by | official version | our `smp` branch |
|---|---|---|---|
| `micro-os-plus-iii-posix-arch` | the 16 builds on the PC | v1.0.1 | +18 commits |
| `micro-os-plus-iii-cortexm` | the 8 builds in QEMU | v1.1.0 | +53 commits |

**Goal:** move everything from `smp` (kernel **and** ports) into
`xpack-development`, **without ever breaking the official tests**.

How far apart the kernel branches are:

- `smp` has **143 commits** that `xpack-development` does not have.
- `xpack-development` has **6 commits** that `smp` does not have. These are
  small changes by Liviu to `README-DEVELOPER.md` and `tests/package.json`.
- **317 files** are different. **43** of them are kernel code in `include/`
  and `src/`. All 43 are changes to existing files: `smp` adds no new kernel
  source file.

## 2. The rules

1. **A step is a few snippets of code, not whole files.** A snippet is one
   small piece: a few lines in one function, or one declaration.
2. **A step takes its snippets from the kernel and from the two ports
   together.** If the kernel needs something from the port, the same step
   brings it, in `posix-arch` and in `cortexm`.
3. **The steps follow the single-core / multi-core differences, one idea at
   a time**: first the bug fixes that also help one core, then the multi-core
   pieces one by one (per-CPU lock state, per-CPU current thread, kernel lock,
   ...).
4. **After every step, all existing tests of `xpack-development` must pass**:
   `xpm run test-all`, 72 tests, on the PC (posix-arch) and in QEMU
   (cortexm).
5. **The test procedure is never modified.** The existing test files,
   platforms and `package.json` actions stay as they are.
6. **New tests come at the end**, and they are only **added**: new files, new
   entries in CMake files, new configurations in `tests/package.json`.

## 3. The official tests (the gate for every step)

The official tests are in `tests/package.json` of `xpack-development`:

```sh
cd tests
npm install
xpm run install-all     # downloads compilers, QEMU, and the ports
xpm run test-all        # builds and runs every test
```

`test-all` builds the kernel in **24 ways**:

- **16 on the PC (Linux)**: gcc 11, 12, 13, 14 and clang 16, 17, 18, 19, each
  in debug and release, with the port **posix-arch**.
- **8 in QEMU**: Cortex-M0, M3, M4F and M7, each in debug and release, with
  the port **cortexm**.

Each build runs **3 tests**: `rtos-apis`, `mutex-stress`,
`cmsis-os-validator`. **A step is accepted only when all 72 pass.**

**Important:** the official build treats **every warning as an error**
(`-Werror`), with many more warnings than our `smp` builds. Code that is
clean on `smp` can fail here.

### How the tests use our ports, without changing the tests

`install-all` downloads the **released** ports (posix-arch v1.0.1, cortexm
v1.1.0). But a step also changes the ports. Upstream already has the
official way to test local port sources: **`xpm link`**. It is described in
`README-DEVELOPER.md` ("Use development writable packages"), and the actions
are already in `tests/package.json`. No test file changes.

```sh
# once: register our two port folders, checked out on the step's branch
cd ~/Work/micro-os-plus/micro-os-plus-iii-posix-arch && git switch step/NN && xpm link
cd ~/Work/micro-os-plus/micro-os-plus-iii-cortexm    && git switch step/NN && xpm link

# in the kernel's tests: use the linked ports instead of the downloaded ones
cd ~/Work/micro-os-plus/micro-os-plus-iii/tests
xpm run install-all
xpm run link-deps-all     # every configuration now uses the local ports
xpm run test-all          # 72 / 72
```

**Check this once, before step 1.** In `tests/package.json` the PC builds
depend on the name `@micro-os-plus/posix-arch`, but the `link-deps` action
links `@micro-os-plus/micro-os-plus-iii-posix-arch`, which is the name in the
port's own `package.json`. Make sure `link-deps` really replaces the
downloaded port. If it does not, the PC builds silently keep using v1.0.1.
Look at where `tests/build/native-cmake-gcc14-debug/xpacks/@micro-os-plus/`
points after `link-deps`.

## 4. What happens if we copy all the kernel code at once

On 2026-09-29 we tried it, in a temporary copy that has since been deleted,
with the **released** ports:

1. `xpack-development` as it is, 8 of the 24 builds: **all 8 passed**.
2. With the kernel code from `smp` (`include/` and `src/`) on top: **all 8
   failed to compile**. No test even ran.

There are exactly **5 reasons**:

| # | where | what goes wrong | which step fixes it |
|---|---|---|---|
| 1 | `src/rtos/os-clocks.cpp`, `include/cmsis-plus/rtos/os-decls.h` | The kernel calls `port::clock_highres::has_hardware_counter()`. The released ports do not have it: "used but never defined". | Step 13 brings the kernel snippet **and** the port snippets together. |
| 2 | `src/libc/stdlib/timegm.c` | On `smp` the declaration of `timegm()` was removed on Linux, but the official Linux build needs it (`-Wmissing-prototypes`). | Step 1 |
| 3 | `src/memory/first-fit-top.cpp`, `do_usable_size()` | A `char*` cast to a bigger type (32-bit ARM, `-Wcast-align`); pointer arithmetic (clang, `-Wunsafe-buffer-usage`). | Step 2 |
| 4 | `src/libcpp/system-error.cpp` | Two `static` objects that live until exit (clang, `-Wexit-time-destructors`). | Step 3 |
| 5 | `src/posix-io/file-descriptors-manager.cpp` | The new `descriptors_array__[fildes] == nullptr` tests (clang, `-Wunsafe-buffer-usage`). | Step 5 |

This is the main reason to go in small steps: each piece is polished for the
stricter official build, one at a time.

## 5. How the code is organised, and why the order matters

### In the kernel

Almost all the multi-core code is already inside
`#if defined(OS_USE_SMP_SCHEDULER)`. The official builds do not define it, so
the compiler **removes** that code. We checked it with the tool `unifdef`:
removing every multi-core block from both branches leaves about **1 300
changed lines in 40 files**. These are the **bug fixes**. They change what
one core does, so the existing tests really run them.

### In cortexm

The files the QEMU builds compile are `include/cmsis-plus/rtos/port/*.h` and
`src/rtos/os-core.cpp`. There, only **two** snippets change what one core
does:

- `clock_highres::has_hardware_counter()` and `hardware_counter()` (returning
  `false` and `0`), which the kernel needs (reason 1);
- a real bug fix in `clock_highres::cycles_since_tick()`: it read the
  "tick pending" bit from `SysTick->CTRL` instead of `SCB->ICSR`.

Everything else in these files is inside `#if defined(OS_USE_SMP_SCHEDULER)`.

The Cortex-M33 and RP2350 code is in **new** files (`include-m33/`,
`include-rp2350/`, `src/rtos/os-core-m33.cpp`, `src/rtos/os-core-rp2350.cpp`).
The QEMU builds do not use them, so they come at the end with the new boards.

### In posix-arch — the hard part

On `smp`, posix-arch was **rewritten** around one idea: *a host thread is a
CPU*. Only **4** blocks are inside `#if defined(OS_USE_SMP_SCHEDULER)`. The
rest is always on: `lock_state[OS_NCPU]`, `_in_isr[OS_NCPU]`, a `stack_ptr`
field added to the thread context, the new file `src/host_cpu.cpp`, and a new
`switch_stacks()`.

The 16 PC builds use posix-arch, so these changes **do** affect the existing
tests. So in the steps below, every posix-arch multi-core snippet gets the
guard that the `smp` code does not have:

```cpp
#if defined(OS_USE_SMP_SCHEDULER)
  // the smp snippet
#else
  // the code exactly as in posix-arch v1.0.1
#endif
```

The single-core path stays the released code, which the 16 PC builds keep
testing. The multi-core path grows step by step.

## 6. How to make one step

A step has **one branch with the same name** in each of the three
repositories, all made from their `xpack-development`:

```sh
for r in micro-os-plus-iii micro-os-plus-iii-posix-arch micro-os-plus-iii-cortexm; do
  git -C ~/Work/micro-os-plus/$r fetch origin
  git -C ~/Work/micro-os-plus/$r switch -c step/04-lock-state origin/xpack-development
done
```

Take **only the snippets of this step**, not the whole file:

```sh
cd ~/Work/micro-os-plus/micro-os-plus-iii-cortexm
git diff origin/xpack-development smp -- include/cmsis-plus/rtos/port/os-decls.h > /tmp/s.patch
#   edit /tmp/s.patch: keep only the lock_state hunk
git apply --index /tmp/s.patch
git commit -m "feat(smp): per-CPU scheduler lock state"
```

Then run the gate of section 3 (`xpm link` both ports, `link-deps-all`,
`test-all`), which must show **72 / 72**.

Then open **one PR per repository**, each saying in its description which
PRs in the other repositories belong to the same step. **They are merged
together**: the port PRs first, then the kernel PR.

After each step is merged, the `smp` branches are updated with the new
`xpack-development` (`git merge origin/xpack-development`), so the
difference gets smaller after every step.

## 7. The steps

In the tables, **K** is the kernel (`micro-os-plus-iii`), **C** is
`cortexm`, **P** is `posix-arch`. "—" means that repository has nothing in
this step.

### Part A — bug fixes that also help one core (steps 1 to 13)

The existing tests run this code, so these steps are really tested.

| step | idea | K (kernel snippets) | C | P |
|---|---|---|---|---|
| 1 | build fixes | `posix/dirent.h`: empty `struct DIR` gets a member. `timegm.c`: declare `timegm()` unless glibc declares it (**reason 2**, see below). `c-syscalls-aliases-standard.h`: `read()`/`write()` return type from newlib. `utils/lists.h`: iterator calls `next()`/`prev()`. `os-thread.cpp`: `this_thread::suspend()` not `inline`. `os-decls.h`: `#include <cmsis-plus/rtos/os-c-decls.h>`. | — | — |
| 2 | memory | `os-memory.h`: `align_size()` overflow; new `usable_size()` / `do_usable_size()`. `os-memory.cpp`: default `do_usable_size()` returns 0. `first-fit-top.cpp`: size checks in `do_allocate()`; `do_usable_size()` with the warnings silenced (**reason 3**). `lifo.cpp`: size checks; a too-small head chunk. `block-pool.cpp`: the inverted `if`. `malloc.cpp`: `calloc()` overflow; `realloc()` copies min(old, new). | — | — |
| 3 | C++ library | `new.cpp`: the 8 `align_val_t` operators. `system-error.cpp`: static categories, warning silenced (**reason 4**). `estd/memory_resource`: `select_on_container_copy_construction()` returns `*this`. `chrono.cpp`: seconds + remainder. | — | — |
| 4 | C / CMSIS API | `os-c-wrapper.cpp`: `os_timer_create()` / `os_timer_new()` default to one-shot; `os_mutex_delete()` / `os_semaphore_delete()` delete the concrete type; `(uint64_t) millisec * 1000u` (9 places). | — | — |
| 5 | files | `file-system.h`, `net-stack.h`: deferred lists under `interrupts::critical_section`. `file-descriptors-manager.cpp`: every function under the lock, null checks, warning silenced (**reason 5**). `block-device.cpp`: the three `!= 0` → `== 0`. | — | — |
| 6 | semihosting, ARMv8-M | `arm/semihosting.h`: ARMv8-M uses `bkpt`; `SEMIHOST_TRAP_HLT`. `c-syscalls-semihosting.cpp`: `fstat()` keeps the type; weak `os_board_console_mirror()`. `cortexm/exception-handlers.h`, `startup/exception-handlers.c`: `__ARM_ARCH_8M_MAIN__` next to 7M/7EM. | — | — |
| 7 | timers | `os-lists.cpp` `check_timestamp()`: unlink under the lock, call `action()` after. `os-timer.cpp` `internal_interrupt_service_routine()`: no burst; link under the lock. `os-thread.h` `__errno()`: a scratch `int` in handler mode. | — | — |
| 8 | mutex | `os-mutex.cpp`: `internal_try_lock_()` ceiling check before owning; inherit keeps the maximum; the owner captured before the uncritical section. `internal_unlock_()`: recompute the inherited priority. | — | — |
| 9 | thread life cycle | `os-c-decls.h`, `os-thread.h`: state `destroying = 7`. `os-thread.cpp`: `resume()` only from suspended/initializing; the two priority relinks under one lock; `detach()`; `join()` under one lock; `internal_destroy_()` wakes the joiner under the lock; `kill()` claims the thread once. `os-idle.cpp`: skip `destroying`/`destroyed`. `os-c-wrapper.cpp`: its `static_assert`. | — | — |
| 10 | condition variable | `os-condvar.h`, `os-c-decls.h`: the `clock` member. `os-condvar.cpp`: `wait()` / `timed_wait()` link and unlock in one step. `instrumentation.h`: `SUSPEND_CAUSE_CONDVAR`. `estd/condition_variable`: `wait_for()` trusts the kernel's result. | — | — |
| 11 | `std::thread` | `estd/thread_internal.h`: remember `function_object_`. `thread-cpp.h`: `join()` waits, then frees. | — | — |
| 12 | message queue | `os-mqueue.cpp`: `port::scheduler::reschedule()` after a send/receive that woke a waiter (6 places). | — | — |
| 13 | hardware counter | `os-decls.h`: declare `has_hardware_counter()` and `hardware_counter()`. `os-clocks.cpp` `clock_highres::now()`: use it when the port has one (**reason 1**). | `os-inlines.h`: both functions, returning `false` / `0`. Plus the `cycles_since_tick()` fix: `SCB->ICSR`, not `SysTick->CTRL`. | `os-inlines.h` / `os-core.cpp`: both functions, reading `CLOCK_MONOTONIC` (smp commit `53eacf4`, "monotonic hrclock"). |

Step 13 no longer needs an `#if` in the kernel: the ports bring the two
functions **in the same step**.

The snippet for step 1, `timegm.c`, which is **different from `smp`**:

```c
// newlib has no timegm(); glibc declares it only under __USE_MISC
// (_DEFAULT_SOURCE / _GNU_SOURCE); Apple's libc always does.
#if !(defined(__GLIBC__) && defined(__USE_MISC)) && !defined(__APPLE__)
time_t
timegm (struct tm* tim_p);
#endif
```

The warning snippets for steps 2, 3 and 5 use the pattern the files already
use elsewhere:

```cpp
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wcast-align"          // step 2 only
#if defined(__clang__)
#pragma clang diagnostic ignored "-Wunsafe-buffer-usage"  // steps 2 and 5
// #pragma clang diagnostic ignored "-Wexit-time-destructors"  // step 3
#endif
    // ... the smp code, unchanged ...
#pragma GCC diagnostic pop
```

Every one of these snippets is also put on `smp`, so the branches stay the
same.

Order: step 1 first. Step 9 after step 7. Steps 10 and 11 after step 9. The
others can go in any order.

### Part B — the multi-core pieces, one idea at a time (steps 14 to 23)

Every snippet here is inside `#if defined(OS_USE_SMP_SCHEDULER)` (for
posix-arch, with the `#else` keeping the v1.0.1 code, see section 5). The
official builds do not define it, so the 72 tests must stay green, and they
prove that **nothing changed for one core**.

That also means the official tests **do not compile** these snippets. So
every step in Part B adds one more check, which is not part of the gate:
**build the step once with `OS_USE_SMP_SCHEDULER` defined**, with our own
`smp` harness (the native SMP build and `2xcortex-m33`), to be sure the
snippets compile together.

**The single-core proof for every Part B step:**

```sh
for f in $(git diff --name-only origin/xpack-development HEAD); do
  git show origin/xpack-development:$f | unifdef -UOS_USE_SMP_SCHEDULER > /tmp/old
  git show HEAD:$f                     | unifdef -UOS_USE_SMP_SCHEDULER > /tmp/new
  diff /tmp/old /tmp/new      # must print nothing
done
```

| step | idea | K (kernel snippets) | C (cortexm snippets) | P (posix-arch snippets) |
|---|---|---|---|---|
| 14 | **how many CPUs, and which one am I** | `os-core.cpp`: `extern "C" unsigned port_cpu_id (void);` | `os-inlines.h`: `port_cpu_id()` returns 0. `os-core.cpp`: the `extern "C" port_cpu_id()` wrapper; `static_assert (OS_NCPU == 1)`. | `os-decls.h`: `OS_NCPU` defaults to 1. `os-core.cpp`: `thread_local _this_cpu`; `extern "C" port_cpu_id()`, `noinline`, with the compiler barrier (the clang 16–18 fix, smp commit `3159a57`). |
| 15 | **one scheduler lock state per CPU** | — | `os-decls.h`: `lock_state[OS_NCPU]`. `os-inlines.h`: `locked()` reads `lock_state[port_cpu_id()]`. `os-core.cpp`: the array; `scheduler::locked (state_t)` and `start()` index it. | `os-decls.h`: `volatile lock_state[OS_NCPU]`. `os-core.cpp`: `locked (state_t)` blocks the tick before reading the CPU id (smp commit `191f89d`). |
| 16 | **the kernel lock** | — | `os-c-decls.h`: `SMP_NO_OWNER`. `os-decls.h`: `struct smp_klock_t`, `_smp_klock`. `os-inlines.h`: `_smp_klock_enter()` / `_smp_klock_exit()`; called from `critical_section::enter()` / `exit()`. `os-core.cpp`: the definition. | `os-decls.h`: the same struct and names. `os-core.cpp` / `os-inlines.h`: the recursive lock and its enter/exit in the critical section. |
| 17 | **interrupts are per CPU** | — | — (one CPU) | `os-decls.h`: `irq_set` next to `clock_set`, `_in_isr[OS_NCPU]`, `signal_nesting`. `os-inlines.h`: `in_handler_mode()` reads `_in_isr[port_cpu_id()]`; the critical section blocks `irq_set`. |
| 18 | **one current thread per CPU** | `os-sched.h`, `os-core.cpp`: `current_thread_[OS_NCPU]`; the two statistics lines use `[port_cpu_id()]`. `os-thread.h`: `this_thread::thread()` reads it with interrupts masked (smp commit `3008ed64`). | `os-core.cpp` `start()`: `current_thread_[0] = pth`; `switch_stacks()` uses `[cpu]`. | `os-core.cpp` `start()` and the switch use `current_thread_[cpu]`. |
| 19 | **one idle thread per CPU** | `os-core.cpp`: `os_idle_thread_core[OS_NCPU]`. `os-main.cpp`: main's `th_cpu_affinity = 1` and `cpu_affinity (1u << 0)`. | `os-core.cpp` `start()`: `os_idle_thread_core[0] = ::os_idle_thread`. | `os-core.cpp` `start()`: the same for CPU 0. |
| 20 | **which CPUs a thread may run on** | `os-c-decls.h`: `th_cpu_affinity`, `cpu_affinity`. `os-thread.h`, `os-thread.cpp`: the attribute, `cpu_affinity()` get/set, default `0xFFFFFFFF`. `os-core.cpp`: `is_thread_allowed_on_cpu()`. | — | — |
| 21 | **"this context is saved, another CPU may take it"** | `os-idle.cpp`: the reaper skips a thread that is still live (`stack_ptr == nullptr` or current on a CPU). | `os-core.cpp` `switch_stacks()`: store the old SP, clear the new one's `stack_ptr` (the whole SMP branch of the function). | `os-c-decls.h`: `stack_ptr` first in `os_port_thread_context_t`. `os-core.cpp` `switch_stacks()`: the deferred publish. |
| 22 | **the multi-core picker** | `os-core.cpp` `internal_switch_threads()`: the affinity-aware pick from the ready list, falling back to the CPU's idle thread. | — | — |
| 23 | **more than one CPU on the PC** | `os-thread.cpp` `resume()`: the wake-up IPI to another CPU (the `OS_INTEGER_RTOS_PORT_NCPU > 1` block). | — (one CPU on the generic Cortex-M) | `src/host_cpu.cpp`, `include/host_cpu.hpp`: a host thread per CPU, its tick timer, the IPI signal, starting the other CPUs, `port_smp_ipi()`. These are **new files**; their whole content is inside `#if defined(OS_USE_SMP_SCHEDULER)`, and they are added to the port's `CMakeLists.txt` source list. |

After step 23, `include/` and `src/` of the kernel are **the same** on both
branches, and so are the generic `cortexm` files and `posix-arch`, apart from
the `#else` single-core code, which `smp` gets back in its own update.

### Part C — at the end: new cores, new tests, new boards (steps 24 to 28)

Only now are new tests added, and only **added**: the existing tests,
platforms and actions do not change. The gate is: **the 72 old tests still
pass**, and the new tests of the step pass too.

| step | what | how it stays add-only |
|---|---|---|
| 24 | **release the ports** | Tag `posix-arch` v1.1.0 and `cortexm` v1.2.0. Create `micro-os-plus-iii-devices` upstream (it does not exist in `micro-os-plus` yet) and tag v1.0.0. Bring `aarch32` and `aarch64` in the same way (Liviu has 6 and 7 newer commits there; take them first). The old configurations keep asking for posix-arch v1.0.1 and cortexm v1.1.0. |
| 25 | **new Cortex-M cores** | cortexm: `include-m33/`, `include-rp2350/`, `src/rtos/os-core-m33.cpp`, `src/rtos/os-core-rp2350.cpp`, `src/libc/getentropy.c`, `src/semihosting-exit.cpp`. New files, and new targets in the port's `CMakeLists.txt`; the existing target is not changed. |
| 26 | **build files** | Kernel: `cmake/toolchains/`, `cmake/uos-app.cmake`, `port/smp-common/`, `tools/`: new files. The smaller kernel targets (`micro-os-plus::iii-posix-io`, `micro-os-plus::iii-drivers`, ...) as **new** names; `micro-os-plus::iii` keeps meaning "all kernel files". |
| 27 | **new test sources and runners** | `tests/sources/fp-switch/`, `test_smpl/`, `tests/device-qemu-cortexm/linker-scripts/mem-mps2-an505.ld` and `mem-mps2-an521.ld`: new files. |
| 28 | **new test platforms** | New folders `tests/platforms/<name>/`, one platform per commit: `pico2-1cpu`, `2xcortex-m33`, `aarch32-rpi3b`, `aarch32-rpi-zero-2w`, `aarch64-rpi3b`, `aarch64-rpi-zero-2w`, `cortexm-pico2`, a native multi-core platform; and the hardware ones (marked `hwd`, never run by `xpm run test`). `tests/cmake/tests-main.cmake`: **add** one `elseif` per new name; the last `else` stays the old code, so `native` and `qemu-cortex-*` build exactly as before. `tests/package.json`: **add** the new configurations and new actions (for example `test-smp-all`); `test-all` does not change. |

Then:

- **Step 29, documents:** `docs/tests/`, `docs/STATUS.md`, the port
  documents, and their PDFs (new files). Ask Liviu whether he wants the
  review reports (`docs/DeepSeek-review.*`, `docs/agy-review.*`).
- **Step 30, the final merge.** See section 8.

## 8. The final merge, and what stays as `xpack-development` has it

Before the final merge, `smp` itself is made to agree with the rules:

1. Take Liviu's 6 newer commits: `git merge origin/xpack-development`.
2. Take back Liviu's version of everything in the tables below.
3. Stop tracking the local links in `tests/xpacks/`.
4. Run the `smp` tests (the new platforms) once more.

Then `git diff --stat origin/xpack-development smp` must show **nothing**
(or only things we chose to keep on `smp`). If anything else shows up, it was
forgotten: make a small step for it first. Then:

```sh
gh pr create --repo dan-maio/micro-os-plus-iii --base xpack-development \
  --head smp --title "Integrate smp"
```

and run the 72 old tests and all the new tests one last time.

**Files `smp` deleted or renamed, which Liviu needs:**

| on `smp` | why it stays |
|---|---|
| `.github/workflows/ci.yml` is **deleted** | Liviu's automatic test on GitHub. |
| `README.md` is **deleted** | The front page of the project. |
| `LICENSE` is **renamed** to `LICENSE-micro-os-plus-iii` | GitHub looks for `LICENSE`. |
| `doxygen/`, `inspiration/`, `templates/` are **deleted** | Liviu's reference manual and material. |
| `docs/HISTORY.md`, `docs/NOTES.md`, `docs/TODO.md` and 3 more are **deleted** | Liviu's documents. |
| `.vscode/`, `.settings/` | Editor settings. |

**Existing test files `smp` changed** (the rules say: do not modify the test
procedure):

| on `smp` | what `smp` changed |
|---|---|
| `tests/platforms/native/`, `tests/platforms/qemu-cortex-m{0,3,4f,7f}/` | rewritten to build through the new ports |
| `tests/platforms/{nucleo-*,raspberrypi-pico}/` | small additions |
| `tests/CMakeLists.txt` | the project name includes the platform |
| `tests/cmake/tests-main.cmake` | `native` and `qemu-cortex-*` go through the new ports (in step 28 only new names do) |
| `tests/sources/rtos-apis/`, `tests/sources/cmsis-os-validator/` | bigger heap, no libucontext, a switch to skip FatFs |
| `tests/device-qemu-cortexm/` (existing files) | FLASH size of an385/an386, M33 vectors |
| `tests/package.json` (existing entries) | changed actions and configurations |
| `tests/xpacks/*` | links to `/home/dan/.local/xPacks/...`, only valid on our PC |

If a new platform needs one of these changes, it gets it through **its own
new files** (for example its own `os-app-config.h` in its own folder).

**Decision for you:** the an385/an386 FLASH size (8 MB → 128 MB) is a real bug
fix, but it is in an existing test file. Either send it as a separate,
clearly labelled PR that Liviu can accept or refuse, or leave it out.

## 9. One thing to know about GitHub

Our repositories (`dan-maio/...`) are **not forks** of Liviu's
(`micro-os-plus/...`) on GitHub.

- We **can** open PRs inside our own repositories (into their
  `xpack-development` branches) right now.
- To send them to **Liviu**, we must first create real forks of his
  repositories, and push the step branches there.

## 10. What can go wrong, and what to do

| problem | what to do |
|---|---|
| A step fails a test because it contains a snippet of another step. | Compare with `git diff` (and `unifdef` in Part B) and move the snippet. |
| A kernel fix needs a test change to pass. | Not allowed. The fix is wrong for one core, or it belongs behind `#if defined(OS_USE_SMP_SCHEDULER)`; change the fix, not the test. |
| The kernel PR of a step is merged but a port PR is not. | Never merge them apart: ports first, then the kernel, in the same session. |
| `link-deps` does not replace the downloaded port (section 3). | Fix that first; otherwise the PC builds test posix-arch v1.0.1, not the step. |
| A Part B snippet does not compile with `OS_USE_SMP_SCHEDULER` defined. | The official tests cannot see it; the extra SMP build of each Part B step is there to catch it. |
| Liviu changes `xpack-development` while steps are open. | Update each open branch with his version (`git merge origin/xpack-development`). |
| A QEMU test takes too long on a slow computer (timeout). | Run that one test alone before calling it a failure. Never run several QEMU tests at the same time. |

## 11. Summary in one sentence

**Bring in small snippets of kernel and port code together — first the bug
fixes that help one core, then the multi-core pieces one idea at a time, each
hidden behind `OS_USE_SMP_SCHEDULER` — checking the 72 existing tests after
every step without changing them; at the end, release the ports and add the
new cores, tests and boards as new files only.**
