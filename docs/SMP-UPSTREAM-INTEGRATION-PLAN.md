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
for c in native-cmake-gcc11 native-cmake-gcc12 native-cmake-gcc13 native-cmake-gcc14 \
         native-cmake-clang16 native-cmake-clang17 native-cmake-clang18 native-cmake-clang19 \
         qemu-cortex-m0-cmake-gcc qemu-cortex-m3-cmake-gcc \
         qemu-cortex-m4f-cmake-gcc qemu-cortex-m7f-cmake-gcc; do
  for t in debug release; do xpm run link-deps --config $c-$t; done
done
xpm run test-all          # 72 / 72
```

**Do not use `xpm run link-deps-all` for this.** Its list in
`tests/package.json` of `xpack-development` names `native-cmake-gcc13-debug`
twice and **leaves out `native-cmake-gcc14-debug`**, so that build would keep
testing the downloaded posix-arch v1.0.1. The loop above names exactly the 24
builds of `test-all`.

To be sure a build really uses the local port, look where its folder points
after the loop:

```sh
ls -l tests/build/native-cmake-gcc14-debug/xpacks/@micro-os-plus/
# micro-os-plus-iii-posix-arch -> ~/Work/micro-os-plus/micro-os-plus-iii-posix-arch
```

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

The table has one row per fix. The column **"why"** says what goes wrong
today on `xpack-development`, and whether it is a **bug** (wrong result,
crash, hang, memory corruption), a **build** problem (does not compile or
link in some configuration), or an **improvement** (nothing is wrong, but it
is better with the change). Unless the row says otherwise, the files are in
the kernel (**K**); **C** is `cortexm`, **P** is `posix-arch`.

| step | where | why (what is wrong today) | the fix |
|---|---|---|---|
| 1 | K `posix/dirent.h` | **Build.** `typedef struct { ; } DIR;` is an empty struct, which ISO C does not allow, and the lone `;` is an extra-semicolon warning. | Give the struct one member, `int reserved;`. |
| 1 | K `libc/stdlib/timegm.c` | **Build.** The file always declares `timegm()`. When the C library also declares it (glibc with `_GNU_SOURCE`/`_DEFAULT_SOURCE`, Apple), `-Wredundant-decls` turns that into an error. `smp` removed it on glibc, which breaks the official PC build (**reason 2**). | Declare it only when the library does not (snippet below). |
| 1 | K `posix-io/c-syscalls-aliases-standard.h` | **Build.** `read()`/`write()` are declared returning `ssize_t`, but newlib uses its own `_READ_WRITE_RETURN_TYPE`, which is `int` on `aarch64-none-elf`: "conflicting types" on 64-bit ARM. | Use `_READ_WRITE_RETURN_TYPE` when newlib defines it. |
| 1 | K `utils/lists.h` | **Build (hidden).** The iterator's `operator++(int)` and both `operator--` use `node_->next` / `node_->prev` as data, but they are functions. A template compiles only what is used, so this fails the first time someone writes `it++` or `--it`. | Call `next()` / `prev()`. |
| 1 | K `rtos/os-thread.cpp` | **Build (link).** `this_thread::suspend()` is defined `inline` in a `.cpp` file, so no normal copy is produced. `os_this_thread_suspend()` in the C wrapper calls it: "undefined reference", unless `--gc-sections` happens to remove the caller. | Remove `inline`. |
| 1 | K `rtos/os-decls.h` | **Improvement.** The C declarations (`os_thread_t`, ...) are not visible through `<cmsis-plus/rtos/os.h>`; our new ports and `os_systick_handler()` rely on them. Nothing fails on `xpack-development` today. | `#include <cmsis-plus/rtos/os-c-decls.h>`. |
| 2 | K `rtos/os-memory.h` | **Bug.** `align_size (size, align)` computes `size + align - 1`; for a huge `size` this wraps around to a small number, so a huge request becomes a tiny one. | Return `SIZE_MAX` when it would wrap. |
| 2 | K `memory/first-fit-top.cpp`, `memory/lifo.cpp` | **Bug.** `do_allocate()` adds padding and header sizes to the request with no limit; the sum can wrap, and a request bigger than the whole heap is still searched for. | Return `nullptr` when the request is larger than the heap, before and after each addition. |
| 2 | K `memory/lifo.cpp` | **Bug (memory corruption).** When the first free chunk is smaller than the request, the pointer to it is kept, and the too-small chunk is given to `internal_align_()`, which writes past its end. | Clear the pointer, so the allocator reports "out of memory". |
| 2 | K `memory/block-pool.cpp` | **Bug.** `if (res != nullptr) { assert (res != nullptr); }`: the test is the wrong way round, so the check never fires when `std::align()` fails. | `if (res == nullptr)`. |
| 2 | K `libc/stdlib/malloc.cpp` `calloc()` | **Bug (memory corruption).** `nelem * elbytes` can overflow; for example on 32-bit, `calloc (0x10001, 0x10000)` asks for 0 bytes, returns a tiny block, and the caller then writes a 4 GB array into it. | If the product would overflow: `errno = ENOMEM`, return `nullptr`. |
| 2 | K `libc/stdlib/malloc.cpp` `realloc()`, `rtos/os-memory.h/.cpp`, `memory/first-fit-top.h/.cpp` | **Bug.** When a block grows, `realloc()` copies the **new** size from the **old** block, so it reads past the end of the old block every time: garbage in the new block, or a fault. | New `memory_resource::usable_size()` (default 0; `first_fit_top` knows the real size); copy the smaller of old and new. Warnings silenced in `do_usable_size()` (**reason 3**). |
| 3 | K `libcpp/new.cpp` | **Bug.** C++17 calls `operator new (size, std::align_val_t)` for types aligned more than normal (for example `alignas (64)`). The kernel does not provide it, so the toolchain's version is used: it bypasses the RTOS memory and its lock. | The 10 aligned operators (4 `new`, 6 `delete`), on the RTOS memory, with the requested alignment. |
| 3 | K `libcpp/system-error.cpp` | **Bug (dangling pointer).** `std::error_code (ev, system_error_category ())` is built from a **temporary** category. `error_code` keeps a pointer to it, and the thrown `system_error` outlives the temporary, so reading the error later reads freed stack. | Use one `static` category object (a function-local static), warning silenced (**reason 4**). |
| 3 | K `estd/memory_resource` | **Not a bug — do not take.** `smp` changes `polymorphic_allocator::select_on_container_copy_construction()` to return `*this`, saying C++17 requires it. The C++17 standard says the opposite: it returns `polymorphic_allocator()`, the default one ([mem.poly.allocator.mem]). The current code is correct. | Leave it as on `xpack-development`, and put it back on `smp` too. |
| 3 | K `libcpp/chrono.cpp` | **Bug.** The high-resolution clock computes `cycles * 1000000000` in 64 bits. That overflows after about 1.8·10¹⁰ CPU cycles, which is minutes at typical clock rates, and time jumps backwards. | Split into seconds and remainder before multiplying. |
| 4 | K `rtos/os-c-wrapper.cpp` `os_timer_create()`, `os_timer_new()` | **Bug.** With `attr == NULL` the C API makes a **periodic** timer, while the C++ API and CMSIS default to **one-shot**. A C program expecting one call gets called forever. | Default to `timer::once_initializer`. |
| 4 | K `rtos/os-c-wrapper.cpp` `os_mutex_delete()`, `os_semaphore_delete()` | **Bug (undefined behaviour).** A recursive mutex (or a binary/counting semaphore) is deleted through the base class pointer, and the base destructor is not virtual. | Look at the object's real type, and delete through that type. |
| 4 | K `rtos/os-c-wrapper.cpp` (10 CMSIS v1 calls) | **Bug.** `(uint64_t)(millisec * 1000u)` multiplies in 32 bits first, **then** widens. Above 4 294 967 ms (about 71.6 minutes) the timeout wraps to a short one. | `(uint64_t) millisec * 1000u`: widen first. |
| 5 | K `posix-io/file-descriptors-manager.cpp` | **Bug (race).** `allocate()` looks for a free slot, then fills it, with no lock. A thread switch between the two (even on one core) gives **two open files the same number**, and one is lost. `deallocate()`, `io()`, `valid()`, `socket()`, `used()` have the same problem. | Each function works under `interrupts::critical_section`; warning silenced (**reason 5**). |
| 5 | K `posix-io/file-descriptors-manager.cpp` | **Bug (crash).** `deallocate()` and `socket()` use the slot without checking that it holds a file: closing a free file number dereferences `nullptr`. `valid()` says "valid" for a free slot. | Check the slot is not empty. |
| 5 | K `posix-io/file-system.h`, `posix-io/net-stack.h` | **Bug (race).** Closed files, folders and sockets are kept in lists for reuse; `link()` / `unlink_head()` on these lists run with no lock, so a thread switch in the middle of an `open()`/`close()` can corrupt the list. | Each list operation under `interrupts::critical_section`; `new` / `delete` stay outside it. |
| 5 | K `posix-io/block-device.cpp` | **Bug.** The three size requests (logical sector, physical sector, device size) test `size != 0` instead of `size == 0`: they fail with `EINVAL` exactly when the device is valid, and answer 0 when it is not. | `== 0`. |
| 6 | K `arm/semihosting.h`, `cortexm/exception-handlers.h`, `startup/exception-handlers.c` | **Improvement (new processor).** ARMv8-M (Cortex-M33) is missing from the lists of Thumb-only processors: semihosting would use `svc` instead of `bkpt`, and the fault handlers, `VTOR` setup and debug checks are left out. No change for M0/M3/M4/M7. | Add `__ARM_ARCH_8M_MAIN__` (and `8M_BASE` for semihosting) next to 7M/7EM; `SecureFault_Handler`. |
| 6 | K `arm/semihosting.h` | **Improvement.** Some debug probes need the `HLT` trap instead of `SVC` on 32-bit ARM. | Optional `SEMIHOST_TRAP_HLT`. |
| 6 | K `semihosting/c-syscalls-semihosting.cpp` `fstat()` | **Bug.** It always adds `S_IFCHR` to `st_mode`, even when a file type is already set; a regular file then has two types. | Add `S_IFCHR` only when no type is set. |
| 6 | K `semihosting/c-syscalls-semihosting.cpp` `__posix_write()` | **Improvement.** A board with a real UART console cannot see `printf()` output there. | A weak hook, `os_board_console_mirror()`; empty by default. |
| 7 | K `rtos/internal/os-lists.cpp` `check_timestamp()` | **Bug.** The timer callback (user code) runs **inside** the interrupts critical section: interrupts stay masked for as long as the user function takes, and a callback that blocks can never be woken. | Take the expired entry off the list under the lock, then call it after the lock is released. |
| 7 | K `rtos/os-timer.cpp` | **Bug.** A periodic timer re-arms at `timestamp + period`. If the callback or the tick was late by more than one period, the new time is already past, and the timer fires again at once, several times in a row. | If the next time is already past, re-arm at `now + period`. The re-link is now done under the lock, because the callback no longer runs inside it. |
| 7 | K `rtos/os-thread.h` `this_thread::__errno()` | **Bug (crash).** A timer callback runs in the tick interrupt; a C library call there (for example `printf()`) writes `errno`, which asks for the current thread, and that asserts in handler mode. | In handler mode, return a scratch `int`. |
| 8 | K `rtos/os-mutex.cpp` `internal_try_lock_()` | **Bug.** With the priority-ceiling protocol, a thread above the ceiling first **took** the mutex (listed it among its mutexes, counted it), then gave up with `EINVAL`, leaving it listed and counted. | Check the ceiling before taking the mutex. |
| 8 | K `rtos/os-mutex.cpp` `internal_try_lock_()` | **Bug (priority inversion).** With priority inheritance, each new waiter **sets** the boost to its own priority, so a low-priority waiter arriving after a high one lowers the owner's priority again. | Keep the highest priority. |
| 8 | K `rtos/os-mutex.cpp` `internal_unlock_()` | **Bug.** To recompute the old owner's inherited priority, the code stores the highest boost of the owner's **other** mutexes in `boosted_prio_` of the mutex being **released**. That value stays in the released mutex and belongs to nobody. With the "keep the highest" fix above, the next owner would inherit it. | Compute the owner's new inherited priority in a local variable (none if it holds no other boosted mutex), apply it, and clear the released mutex's `boosted_prio_`. |
| 8 | K `rtos/os-mutex.cpp` `internal_try_lock_()` | **Bug (crash).** Inside the "uncritical section" (lock released to boost the owner), the owner can unlock; the code then reads `owner_`, which is now `nullptr`. Rare on one core, frequent on several (21 of 25 runs on four CPUs). | Keep a copy of the owner pointer; if the mutex was released meanwhile, try to take it again. |
| 9 | K `rtos/os-thread.cpp` `kill()`, `rtos/os-idle.cpp`, `rtos/os-c-decls.h`, `rtos/os-thread.h`, `rtos/os-c-wrapper.cpp` | **Bug (double free).** A finished thread can be destroyed twice: by the idle thread (which takes it off the "finished" list, then destroys it outside the lock) and by `kill()`, if a thread switch falls between the two. | New state `destroying` (value 7): whoever sets it first destroys the thread; the other waits or skips it. |
| 9 | K `rtos/os-thread.cpp` `join()`, `internal_destroy_()` | **Bug (hang).** `join()` checks "is it finished?", records itself as the joiner, then sleeps, in three separate steps. If the thread finishes between them, the wake-up is lost and `join()` sleeps forever. Also, the joiner was woken after the lock was released, when it might already have freed the object. | Check, record and sleep under one lock; wake the joiner under the same lock. |
| 9 | K `rtos/os-thread.cpp` `detach()` | **Bug.** `detach()` is empty (`// TODO: implement`): the thread stays a child of its parent. | Unlink it from the parent, move it to the top-level list; `EINVAL` if already destroyed. |
| 9 | K `rtos/os-thread.cpp` `resume()` | **Bug.** Any thread not in the ready list is put in it, also a thread that is running or finished, which corrupts its state. | Only a `suspended` or `initializing` thread. |
| 9 | K `rtos/os-thread.cpp` `priority()`, `priority_inherited()` | **Bug (race).** "Is it ready?" is checked outside the lock, then the thread is moved in the ready list inside it; a switch between the two moves a thread that is no longer there. | Check and move under one lock, and only if the thread is really in the list. |
| 10 | K `rtos/os-condvar.cpp` `wait()` | **Bug.** `wait()` unlocks the mutex, adds itself to the waiting list, then just locks the mutex again. It never really waits for `signal()`: it returns almost at once, so callers that loop on a condition spin and burn the CPU. A `signal()` between the unlock and the list add is also lost. | Add to the list and unlock as one step (scheduler locked), then sleep until signalled; remove from the list; lock the mutex. |
| 10 | K `rtos/os-condvar.cpp` `timed_wait()`, `rtos/os-condvar.h`, `rtos/os-c-decls.h` | **Bug.** The timeout was used as the timeout for **re-locking the mutex**, not for waiting for a signal, and the clock given in the attributes was ignored. | Wait on the list and on the attribute's clock (default `sysclock`); `ETIMEDOUT` when the time is up. The C struct gains the matching `clock` member (sizes checked by `static_assert`). |
| 10 | K `estd/condition_variable` `wait_for()` | **Bug.** It decides "timeout or not" by measuring elapsed wall time, so a thread that was signalled but then delayed is told "timeout". | Use the kernel's answer (`ok` or `ETIMEDOUT`). |
| 10 | K `diag/instrumentation.h` | **Improvement.** Tracing tools cannot tell "waiting on a condition variable" apart from other waits. | `OS_INTEGER_INSTRUMENTATION_SUSPEND_CAUSE_CONDVAR` (12). |
| 11 | K `libcpp/thread-cpp.h` `std::thread::join()` | **Bug.** `join()` does not wait: it deletes the system thread and its arguments at once, while the thread may still be running. | Wait for the system thread (`join()`), then delete. |
| 11 | K `estd/thread_internal.h`, `libcpp/thread-cpp.h` | **Bug (leak).** The function object with the thread's arguments is freed using the kernel's `func_args_`, which the kernel clears when the thread ends, so it is never freed for a thread that already finished (the common case). | Keep our own pointer to it (`function_object_`). |
| 12 | K `rtos/os-mqueue.cpp` (6 places) | **Improvement (latency).** When a send wakes a waiting receiver (or a receive wakes a sender), nothing asks the scheduler to switch; on posix-arch the woken thread waits up to 1 ms for the next tick. The ARM ports already switch at the end of the critical section. | `port::scheduler::reschedule()` after the lock is released. |
| 13 | K `rtos/os-decls.h`, `rtos/os-clocks.cpp`; C `os-inlines.h`; P `os-inlines.h` | **Improvement.** `clock_highres::now()` adds the tick count to the cycles since the last tick. A port with a real free-running counter (the PC's `CLOCK_MONOTONIC`) can give an exact time that never goes backwards. The kernel's call is **reason 1**. | K: `now()` uses `has_hardware_counter()` / `hardware_counter()`. C: both return `false` / `0`, so nothing changes on Cortex-M. P: both read `CLOCK_MONOTONIC` (smp commit `53eacf4`). |
| 13 | C `os-inlines.h` `clock_highres::cycles_since_tick()` | **Bug.** It tests the "tick pending" bit in `SysTick->CTRL`, but that bit (`PENDSTSET`, bit 26) is in `SCB->ICSR`; in `CTRL` bit 26 does not exist, so the test is always false. When a tick is pending but not yet counted, the time is one tick too small, so the high-resolution time can jump backwards. | Test `SCB->ICSR`. |

Step 13 no longer needs an `#if` in the kernel: the ports bring the two
functions **in the same step**.

The snippet for step 1, `timegm.c`, which is **different from `smp`**:

```c
// newlib has no timegm(). glibc's <time.h> declares it only under
// `__USE_MISC || __GLIBC_USE (ISOC23)`; the official PC builds use
// _POSIX_C_SOURCE / _XOPEN_SOURCE and C11, so there it is NOT declared.
// Apple's libc always declares it. __GLIBC_USE is a glibc macro, so it is
// tested only inside the glibc branch.
#if defined(__GLIBC__)
#if !(defined(__USE_MISC) || __GLIBC_USE (ISOC23))
time_t
timegm (struct tm* tim_p);
#endif
#elif !defined(__APPLE__)
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

That also means the official tests **do not compile** these snippets. The
multi-core pieces only work together: for example, cortexm's
`switch_stacks()` multi-core branch needs the kernel lock (step 16), the
per-CPU current thread (step 18) and the saved-context rule (step 21) at the
same time. So a multi-core build is not expected to compile in the middle of
Part B. Instead there is **one extra check at the end of Part B** (after step
23), outside the gate: build and run our own `smp` multi-core tests (the
native multi-core build and `2xcortex-m33`) against the three step branches.
If it fails, the missing snippet is found and added to its step before the
PRs are merged.

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
| 14 | **how many CPUs, and which one am I** | `os-core.cpp` and `os-thread.cpp`: `extern "C" unsigned port_cpu_id (void);` | `os-inlines.h`: `port_cpu_id()` returns 0. `os-core.cpp`: the `extern "C" port_cpu_id()` wrapper; `static_assert (OS_NCPU == 1)`. | `os-decls.h`: `OS_NCPU` defaults to 1. `os-core.cpp`: `thread_local _this_cpu`; `extern "C" port_cpu_id()`, `noinline`, with the compiler barrier (the clang 16–18 fix, smp commit `3159a57`). |
| 15 | **one scheduler lock state per CPU** | — | `os-decls.h`: `lock_state[OS_NCPU]`, `lock_primask[OS_NCPU]`. `os-inlines.h`: `locked()` reads `lock_state[port_cpu_id()]`. `os-core.cpp`: the array; `scheduler::locked (state_t)` and `start()` index it. | `os-decls.h`: `volatile lock_state[OS_NCPU]`. `os-core.cpp`: `locked (state_t)` blocks the tick before reading the CPU id (smp commit `191f89d`). |
| 16 | **the kernel lock** | — | `os-c-decls.h`: `SMP_NO_OWNER`. `os-decls.h`: `struct smp_klock_t`, `_smp_klock`. `os-inlines.h`: `_smp_klock_enter()` / `_smp_klock_exit()`; called from `critical_section::enter()` / `exit()`. `os-core.cpp`: the definition. | `os-decls.h`: `SMP_NO_OWNER`, the same struct and names. `os-core.cpp` / `os-inlines.h`: the recursive lock and its enter/exit in the critical section. |
| 17 | **interrupts are per CPU** | — | — (one CPU) | `os-decls.h`: `#if` multi-core `irq_set`, `_in_isr[OS_NCPU]`, `signal_nesting`; `#else` the v1.0.1 `clock_set` (on `smp`, `irq_set` **replaced** `clock_set`). `os-inlines.h`: `in_handler_mode()` reads `_in_isr[port_cpu_id()]` or `signal_nesting` (smp commit `cd1a728`); the critical section blocks `irq_set`. |
| 18 | **one current thread per CPU** | `os-sched.h`, `os-core.cpp`: `current_thread_[OS_NCPU]`; the two statistics lines use `[port_cpu_id()]`. `os-thread.cpp`: `current_thread_[port_cpu_id()] = this`. `os-thread.h`: `this_thread::thread()` reads it with interrupts masked (smp commit `3008ed64`). | `os-core.cpp` `start()`: `current_thread_[0] = pth`. | `os-core.cpp` `start()`: `current_thread_[cpu]`. |
| 19 | **one idle thread per CPU** | `os-core.cpp`: `os_idle_thread_core[OS_NCPU]`. | `os-core.cpp` `start()`: `os_idle_thread_core[0] = ::os_idle_thread`. | `os-core.cpp` `start()`: the same for CPU 0. |
| 20 | **which CPUs a thread may run on** | `os-c-decls.h`: `th_cpu_affinity`, `cpu_affinity`. `os-thread.h`: the attribute, `cpu_affinity()` get/set, the member (default `0xFFFFFFFF`). `os-thread.cpp`: the three initialisations and the get/set. `os-core.cpp`: `is_thread_allowed_on_cpu()`. `os-main.cpp`: main pinned to CPU 0. `os-c-wrapper.cpp`: CMSIS-RTOS v1 threads pinned to CPU 0 (2 places). | — | — |
| 21 | **"this context is saved, another CPU may take it"** | `os-thread.h`: `os_rtos_idle_actions()` becomes a `friend`. `os-idle.cpp`: the reaper skips a thread that is still live (`stack_ptr == nullptr` or current on a CPU). `os-thread.cpp`: `join()` and `kill()` wait until the thread is off every CPU. | `os-core.cpp` `switch_stacks()`: its whole multi-core branch (kernel lock, `current_thread_[cpu]`, store the old SP, clear the new one's `stack_ptr`). | `os-c-decls.h`: `stack_ptr` first in `os_port_thread_context_t`. `os-core.cpp` `switch_stacks()`: the deferred publish. |
| 22 | **the multi-core picker** | `os-thread.h`: `internal_switch_threads()` becomes a `friend`. `os-core.cpp` `internal_switch_threads()`: the affinity-aware pick from the ready list, falling back to the CPU's idle thread. | — | — |
| 23 | **more than one CPU on the PC** | `os-thread.cpp`: the weak, empty `port_smp_ipi()`. | — (one CPU on the generic Cortex-M) | `src/host_cpu.cpp`, `include/host_cpu.hpp`: a host thread per CPU, its tick timer, the IPI signal, starting the other CPUs, and the strong `port_smp_ipi()`. These are **new files**; their whole content is inside `#if defined(OS_USE_SMP_SCHEDULER)`, and one line adds `src/host_cpu.cpp` to the `target_sources` list in the port's `CMakeLists.txt`. |

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
| 25 | **new cores and board support** | cortexm: `include-m33/`, `include-rp2350/`, `src/rtos/os-core-m33.cpp`, `src/rtos/os-core-rp2350.cpp`, `src/libc/getentropy.c`, `src/semihosting-exit.cpp`. posix-arch: `board-contract.cpp`, `exception_handler.{hpp,cpp}`, `free-store.cpp`, `hw_result.hpp` (used only by the new test harness). New files, and new targets in the ports' `CMakeLists.txt`; the existing targets are not changed. Kernel: the wake-up IPI in `thread::resume()` (the `OS_INTEGER_RTOS_PORT_NCPU > 1` block). Only the RP2350 defines `OS_INTEGER_RTOS_PORT_NCPU`, so this snippet comes with it. |
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
| A build still uses the downloaded port (section 3). | Use the explicit `link-deps` loop, not `link-deps-all` (which skips `native-cmake-gcc14-debug`), and check the `xpacks/@micro-os-plus/` link. |
| A Part B snippet is missing, so the multi-core build fails at the end of Part B. | The official tests cannot see it; the extra multi-core check after step 23 finds it. Add it to its step before the PRs are merged. |
| Liviu changes `xpack-development` while steps are open. | Update each open branch with his version (`git merge origin/xpack-development`). |
| A QEMU test takes too long on a slow computer (timeout). | Run that one test alone before calling it a failure. Never run several QEMU tests at the same time. |

## 11. Summary in one sentence

**Bring in small snippets of kernel and port code together — first the bug
fixes that help one core, then the multi-core pieces one idea at a time, each
hidden behind `OS_USE_SMP_SCHEDULER` — checking the 72 existing tests after
every step without changing them; at the end, release the ports and add the
new cores, tests and boards as new files only.**
