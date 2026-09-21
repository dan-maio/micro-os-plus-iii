# Migration status

**Updated:** 2026-09-20 · **Phase:** step 2 — **complete**. Builds, QEMU
suites and hardware all green on both ARM ports.

This file is the cold-start entry point. Read it, then
`docs/specs/2026-09-20-micro-os-plus-iii-smp-unification-design.md` for the
full design and the measurements behind it.

---

## Where things stand

**Steps 1 and 2 are complete.** Six repositories exist; both ARM architecture
projects build all 24 of their targets from a single copy of every test, and
all twelve tests pass on a Raspberry Pi Zero 2 W on **both** ports — each
measured on that port, neither inferred from the other.

**Step 3 is in progress.** The AArch32 port now carries a second board, the
Luckfox Lyra B (RK3506, 3× Cortex-A7): 19 targets build, and both ports still
pass their QEMU suites (11/1/0 each) after the restructure it required. What
that second board changed, and the seven portability defects it exposed in
shared code, are written up in
[`aarch32-second-board.md`](aarch32-second-board.md).

**The Lyra is a hardware-only board**, decided and closed. QEMU models none of
the RK3506's own blocks, so an emulated Lyra would be a generic Cortex-A7
wearing the name — and the DWC2 gadget, the SD host and the Cortex-M0 mailbox,
which are what make this board worth having, are exactly the parts not
modelled. Its `board.cmake` sets no `UOS_BOARD_LINKER_QEMU`, so it builds one
image per test rather than two, and `test/qemu.sh` says so if asked. This is
not a gap to close later; do not reopen it.

```
TMP7/
├── micro-os-plus-iii-smp/        kernel + shared build rules + test runners
│   ├── src/ include/             the kernel, upstream path-for-path
│   ├── port/smp-common/          os-decls.h, shared by both ARM ports
│   ├── test_smpl/                the two runners -- see test-smpl.md
│   │   ├── run-qemu.sh           the shared QEMU suite runner
│   │   └── run-hw.sh             the shared hardware session runner
│   ├── cmake/                    toolchains + uos_add_app
│   └── tools/verify-kernel-compiles.sh
├── micro-os-plus-iii-devices/    flatfs, FatFs; SD per SoC (BCM2837, RK3506)
├── micro-os-plus-iii-aarch64/    ARMv8-A port
│   ├── src/ include/             ARMv8-A, every board
│   └── test/                     everything board- or test-specific
│       ├── CMakeLists.txt        one loop over test/<board>/*/
│       ├── hw.sh  qemu.sh        dispatchers; BOARD picks the directory
│       ├── boards/{rpi-zero-2w,rpi3b}/   board.cmake, include/, src/,
│       │                                 linker, OpenOCD, hw.sh, qemu.sh
│       ├── rpi-zero-2w/ rpi3b/   each board's test applications
│       └── build*/               the build trees
├── micro-os-plus-iii-aarch32/    ARMv7-A port
│   ├── src/ include/             ARMv7-A, every board — incl. the scheduler
│   └── test/                     same shape
│       ├── boards/{rpi-zero-2w,rpi3b,luckfox-lyra}/  BCM2837 · BCM2837 · RK3506
│       └── rpi-zero-2w/ rpi3b/ luckfox-lyra/         12 · 12 · 13 applications
└── micro-os-plus-iii-smp-old/    READ ONLY — the migration source

Outside `src/` and `include/` — which are the ISA and nothing else — an
architecture project is all `test/`: the boards, their tests and their build
trees. How that is laid out and how to run it is
[`tests-in-aarch32-aarch64.md`](tests-in-aarch32-aarch64.md).
```

| | |
|---|---|
| Migration source (read-only) | `TMP7/micro-os-plus-iii-smp-old` |
| Remotes | `GIT/micro-os-plus-iii-{smp,devices,aarch32,aarch64}.git` |
| Old remote | `GIT/micro-os-plus-iii-smp-old.git` |

An architecture project holds **no copy** of the kernel or the devices repo.
CMake resolves both as sibling directories, overridable with `-DUOS_SMP_DIR=`
and `-DUOS_DEVICES_DIR=`. Whoever builds one clones what it needs. One working
copy of the kernel serves every architecture project on the machine, so an
edit to it is visible to all of them at once. The dependency runs one way:
neither the kernel nor the devices repo knows an architecture project exists.

## Done

1. **Remotes reorganised**, old tree analysed and measured, design spec
   written. Every figure in the spec came from the tree, not estimation.
2. **Step 1 — skeleton and kernel.** Kernel vendored once, flattened to the
   repository root so it matches upstream path-for-path. Three toolchains share
   one preamble. `uos_add_app` replaces 214 Makefiles.
3. **Devices split out** (`micro-os-plus-iii-devices`). All seven sources
   compile for armv7-a *and* armv8-a from one copy; ~12,000 duplicated lines
   collapse to one copy.
4. **Step 2a — the twelve test applications unified.** 15,507 lines of
   application C++ become 7,610. Nothing ISA-specific is left in a test.
5. **Step 2b — both ARM architecture projects.** Each builds every board's
   tests from one loop over `test/${BOARD}/*/`, in two variants. No
   test name and no board name appears in either port's build files.
   24 targets per Pi board, 26 for the Lyra.
6. **QEMU suites green.** `11 passed, 1 skipped, 0 failed` on both, with
   gcc 15 and one suite at a time. `usb_test` skips by design — QEMU emulates
   no USB device mode — as the predecessor suite also recorded.
7. **Documentation.** `docs/smp-construction.md` (the port contract, the
   division of labour, and the defines per folder) and
   `docs/building-aarch32-aarch64.md`, both with PDFs, rendered by a single
   `docs/md2pdf.py` that replaces three near-identical copies.
8. **Hardware green on both ports.** All twelve pass on a Zero 2 W over a
   J-Link, `usb_test` included — the one QEMU can never run.
   `test_smpl/run-hw.sh` plus a ~40-line `test/hw.sh` per port replace the
   predecessor's 48 per-test runner scripts.

## What hardware found that QEMU could not

Five real defects, all in paths the emulator does not reach:

| Defect | Fix |
|---|---|
| Every blinking test drove **GPIO16**, so nothing lit | `LED_PIN` is a board fact now, 29 on the Zero 2 W, set once for every test. Only `usb_test` had ever set it — and the predecessor Makefiles had the same hole. |
| `usb_test` answered a PUT **after** streaming its hexdump and listing | `send_reply` moved to immediately after the store. A completed store looked like a hang. |
| Console posts **blocked** the USB service thread, so bulk OUT was not re-armed | `try_send`, with `console_dropped` in the tally. Diagnostics must never throttle the protocol. |
| `LIST` compared file names case-sensitively | FatFs on a boot card has no long names and returns `XFER.BIN`; flatfs under QEMU keeps the name as sent. |
| **`kOutChunkMax` overflowed `PKTCNT`** — a 1 MiB transfer stored 61440 bytes, silently truncated | `D{I,O}EPTSIZ` is bounded by two fields. `GHWCFG3 = 0x0ff000e8`: XFRSIZ 19 bits but PKTCNT **10 bits = 1023 packets**, so 65472 bytes at full speed. The chunk derives from the packet limit now, with `static_assert`s on both fields. |

## What made the test deduplication possible

The ISA seam in the applications turned out to be tiny, and mostly not a seam:

| what the two copies disagreed on | resolution |
|---|---|
| `dsb` vs `dsb sy`, `dmb` vs `dmb ish` | not a difference — the explicit forms assemble on ARMv7-A too. Verified with both assemblers. |
| `cpsie i` vs `msr daifclr, #2` | already a kernel API: `interrupts::uncritical_section::enter()`, implemented by every port |
| `mrrc p15…c14` vs `mrs cntpct_el0` | already in the port's `timer_arm.hpp`; the tests were re-reading the register themselves |
| `"(AArch64)"` in banners | `PORT_BANNER_ISA` / `PORT_BANNER_CPU`, beside the existing `PORT_BANNER_LONG`/`SHORT` |

Two pieces of per-application boilerplate were also collected:
`test-smp-boot` (idle stacks, idle body, `smp_install_boot_threads()`, in ten
of twelve tests) and `test-console` (the mutex-guarded print helpers, in
three). The shared boot helper generates thread names from `OS_NCPU` instead
of listing four, so it no longer assumes a four-core BCM2837.

## Two defects found and fixed on the way

- **The kernel exported all 63 sources as one target**, but the proven rpi
  builds compiled exactly 37. Linking the rest breaks the build:
  `posix-io/c-syscalls-posix.cpp` declares `read`/`write` returning `ssize_t`,
  newlib declares them returning `int`. `micro-os-plus::iii` is now that
  measured 37-source core; posix-io, drivers, generic startup, newlib-reent,
  semihosting and the three trace backends are opt-in targets. Two entries were
  headers listed as sources and are gone — which is why 63 entries were always
  61 compiled files.
- **The Cortex-A7 port's `os-decls.h` was missing `volatile`** on
  `lock_state[]`, which several cores read and write. The shared copy in
  `port/smp-common/` is the correct one, so adopting it fixes that port rather
  than merely deduplicating it.

## Decisions — all resolved

Spec Section 11 has the table; nothing is open. Revision 2 set the shape:
architecture-specific ports (not target-specific), six repositories,
architecture projects independent and *outside* the main repo, devices in
their own repo, `cortexm` and `posix-arch` both to become SMP.

## Next step

**Step 2 is done.** *Gate:* all 24 targets build **(met, both ports)**; QEMU
suites pass **(met, 11/1/0 both ports)**; hardware tests pass on the Pi
**(met, 12/12 both ports)**; no device or test source exists in more than one
repo **(met)**.

Step 3 (`aarch32` gains the RK3506) is **under way**. *Gate:*
`exception_handler.cpp` shared unmodified by both boards **(met)**; the board
builds **(met, 19 targets)**; neither existing port regressed **(met, QEMU
11/1/0 on each)**. Open: running the RK3506-specific tests, which are hardware
only — the six carried over from the predecessor (the USB gadget pair, the SD
pair, the interrupt pair and the Cortex-M0) have never been run, and
`smp_test4` is reported not to work.

Emulating the Lyra is **not** open. It was considered and closed: see above.

Then: step 4 (`cortexm` —
pico2's dual-core SMP core merged with the STM32 boards at `OS_NCPU=1`, 129
apps), step 5 (`posix-arch` — a new SMP implementation, one host thread per
CPU).

## Things a fresh session should not rediscover

- The four patched kernel copies are **byte-identical** (`diff -rq`).
- The kernel differs from pristine upstream in exactly **6 files**, all under
  `rtos/`. That is the entire SMP delta.
- **Upstream fork point**, preserved because the spec drops `BASE`:
  `micro-os-plus-iii` @ `c47f806b57f8b9b870ec7b89ded663dec354df96`
  (branch `xpack-development`), `micro-os-plus-iii-cortexm` @
  `687e975caa298519cb214d4b5a9774c48f784816`.
- **`src/rtos/os-core.cpp` exists twice on purpose.** The kernel's is the
  portable SMP scheduler; each port has its own at the same relative path with
  the bring-up, the kernel lock and the context-switch hooks. Both are
  compiled, exactly as the old Makefiles did. They do not collide.
- **A port needs its machine flags at link time too**, not just compile time.
  Without them the driver picks the wrong multilib and every AArch32 link fails
  with "uses VFP register arguments".
- **Rebuild the port you are about to test.** A shared test source is still
  two separate binaries. `usb_test` on AArch32 reproduced a defect that had
  already been fixed, purely because only the AArch64 target had been rebuilt;
  the symptom was indistinguishable from the original bug.
- **A hardware run is one test per power cycle.** It is `load_image` into RAM
  over the previous test's leftovers, and the Pi has no SRST — the Cortex-A53
  debug target has no reset method a script can drive. `run-hw.sh` refuses a
  suite for this reason.
- **A hardware budget is not the test's own duration.** It is dominated by
  semihosting traps, which scale with how much a test prints. `smp_test4`
  reaches its verdict at t=9597 ms of target time and still needs more than
  120 s of wall clock.
- **`Invalid ACK (0) in DAP response` is not a firmware fault.** The debug link
  gave up; once it is gone nothing services the semihosting traps, so every
  core halts inside one and it reads like a hang. Drop the JTAG clock with
  `UOS_HW_ADAPTER_KHZ=1000` and check the supply. The runner reports this as
  DEBUG LINK LOST.
- **QEMU suites must run one at a time.** Running two four-core suites
  concurrently, or alongside a build, starves a vCPU: `smp_test2` stalled with
  three workers finished and the fourth frozen mid-loop. On an idle host the
  same binary passes 5 out of 5. A stalled worker with no fault is contention,
  not a bug — re-run before investigating.
- **The AArch32 suite runs on `raspi3b` with the boot shim, never `raspi2b`.**
  The port is built `-mcpu=cortex-a53`, so its load-acquire instructions are
  undefined on the raspi2b Cortex-A7 and it faults at the first one. QEMU's
  raspi3b starts its cores in AArch64, so a 20-line stub drops to AArch32 and
  jumps to the image. Hardware needs none of this: `config.txt` sets
  `arm_64bit=0`.
- **`rtk`'s `diff` reports "Files are identical" for files with different
  MD5s.** Seen on `sd.cpp`, `bcm2837.hpp`, `bcm_irq.hpp`. Use `md5sum` or
  Python `difflib` for anything that matters.
- `rtk` silently dropped the `-u` flag from `git push -u`; tracking was set
  with `git branch --set-upstream-to`. Expect this on new branches.
- Do **not** add a blanket `*.html` ignore rule — the kernel ships three
  doxygen templates as `.html`.
- There are **214 tracked Makefiles**, not the 24 an early count suggested.
- A test app is only ~5 tracked files; the ~100 others per directory are
  untracked build artifacts.
- **The SMP port contract is small.** The whole kernel patch is 379 lines and
  asks a port for only: `OS_USE_SMP_SCHEDULER`, `OS_NCPU`, `port_cpu_id`,
  `port::scheduler::switch_stacks`, `port::stack::element_t`, plus a kernel
  lock and an IPI.
- **`cortexm` SMP is not from scratch.** pico2's `os-core.cpp` is already a
  complete dual-core Cortex-M33 SMP port.
- **`posix-arch` is pristine upstream v1.0.1**, untracked in the old
  workspace. Single host thread, `ucontext` coroutines, cooperative only.
- **Three POSIX defects to fix when going multi-threaded:** `sigprocmask` is
  unspecified in a multithreaded process (use `pthread_sigmask`);
  `setitimer(ITIMER_REAL)` delivers to an arbitrary thread (use `timer_create`
  with `SIGEV_THREAD_ID`); `errno`/`thread_local` are host-thread local, so
  µOS++ thread migration between CPUs corrupts them.
