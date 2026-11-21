# The µOS++ test catalogue

Every test the framework registers, per architecture, platform and board:
what each test does, whether it runs the SMP scheduler or a single core, how
it is run (QEMU, host or the real board) and, for the board runs, which debug
probe. How the framework works: [`TESTS-DEVELOPER-GUIDE.md`](TESTS-DEVELOPER-GUIDE.md);
the commands: [`COMMANDS.md`](COMMANDS.md).

The sources of truth are the files, not other documents. All of them are in
the kernel's `tests/`:

| What | Where |
|---|---|
| which tests a platform runs | `platforms/<platform>/CMakeLists.txt` (the `UOS_TESTS_*` lists), plus every folder of `platforms/<platform>/tests/` (globbed at configure time) |
| the portable tests and suites | `sources/<test>/` |
| per-test knobs (core count, HWD_ONLY, sources, libraries) | `platforms/<platform>/tests/tests.cmake` |
| board facts (CPU, core count, linker scripts, SD driver) | `platforms/<platform>/cmake/board.cmake` |
| the probe | `platforms/<platform>/openocd*.cfg`, and the OpenOCD run in the platform's `CMakeLists.txt` |
| how a test runs, its time limit | `cmake/uos-tests-run.cmake` |

## 1. Legend

**Variant** (the suffix of the CTest name):

| Suffix | Runs on | Started by CTest as |
|---|---|---|
| `-qemu` | QEMU | `qemu-system-arm` / `qemu-system-aarch64` with semihosting |
| `-host` | the Linux host (POSIX port) | the native program |
| `-hwd` | the real board | OpenOCD with the board's configuration (label `hwd`) |
| `-hwd` manual | the real board, driven by hand | label `hwd-manual`; excluded from `-L hwd` |
| `-test` (no variant) | the upstream platforms: QEMU | the command in the platform's `CMakeLists.txt` |

The verdict is the test's `RESULT: PASS|FAIL|SKIP` line; the test then ends
the run through semihosting. `-hwd` cases are excluded from the
configuration's `test` action (`ctest -LE hwd`) and run one at a time,
with OpenOCD only (no GDB). Before each AArch hardware test CTest adds
`<test>-hwd-reset`, the board's reset in its own OpenOCD session. The former
`-hwsh` twins and `hw.sh` scripts have been removed.

**Scheduling** (the "Mode" column below):

| Mode | Meaning |
|---|---|
| **SMP n** | kernel built with `OS_USE_SMP_SCHEDULER`, `OS_NCPU = n`, all n cores scheduling |
| **SMP n, 1 active** | SMP build, but the test keeps the secondaries parked |
| **SMP ×1** | SMP scheduler code paths at `OS_NCPU = 1` (single-CPU board) |
| **single** | the kernel's non-SMP branch (`OS_USE_SMP_SCHEDULER` undefined), one core |
| **bare** | no kernel at all: a bare-metal probe |

## 2. Platforms at a glance

| Platform (configuration prefix) | Port | Board / machine | CPU | Cores | Cases | Probe |
|---|---|---|---|---|---|---|
| `aarch32-rpi-zero-2w` | aarch32 | Raspberry Pi Zero 2 W (BCM2837) | 4× Cortex-A53, AArch32 | 4 | 18 qemu, 18 hwd | `PROBE`: J-Link (default), Olimex, CMSIS-DAP |
| `aarch32-rpi3b` | aarch32 | Raspberry Pi 3 B (BCM2837) | 4× Cortex-A53, AArch32 | 4 | 16 qemu, 15 hwd | as the Zero 2 W |
| `aarch32-luckfox-lyra` | aarch32 | Luckfox Lyra B (RK3506) | 3× Cortex-A7 (+ a Cortex-M0 not scheduled) | 3 | 21 hwd | WCH-Link, CMSIS-DAP |
| `aarch64-rpi-zero-2w` | aarch64 | Raspberry Pi Zero 2 W (BCM2837) | 4× Cortex-A53, ARMv8-A | 4 | 18 qemu, 18 hwd | as the AArch32 Zero 2 W |
| `aarch64-rpi3b` | aarch64 | Raspberry Pi 3 B (BCM2837) | 4× Cortex-A53, ARMv8-A | 4 | 16 qemu, 15 hwd | as the Zero 2 W |
| `aarch64-rpi4b` | aarch64 | Raspberry Pi 4 B (BCM2711) | 4× Cortex-A72 | 4 | 22 qemu, 22 hwd | CMSIS-DAP |
| `cortexm-pico2` | cortexm | Raspberry Pi Pico 2 (RP2350) | 2× Cortex-M33 | 2 | 6 qemu, 21 hwd | Raspberry Pi Debug Probe (CMSIS-DAP) |
| `cortexm-pico2-pizero` | cortexm | Pi-Zero RP2350B, 16 MB flash | 2× Cortex-M33 | 2 | 14 hwd | XV-Link CMSIS-DAP |
| `cortexm-pico2-rp2350b-psram` | cortexm | WeAct RP2350B, 16 MB flash + 8 MB PSRAM | 2× Cortex-M33 | 2 | 3 qemu, 15 hwd | CMSIS-DAP `c251:f001` |
| `cortexm-pico` | cortexm | Raspberry Pi Pico (RP2040) | 2× Cortex-M0+ | 2 | 6 qemu, 20 hwd | CMSIS-DAP `2e8a:000c` |
| `cortexm-nucleof411` | cortexm | ST Nucleo-F411RE | 1× Cortex-M4F | 1 | 4 hwd | on-board ST-Link v2.1 |
| `cortexm-weactf411` | cortexm | WeAct Studio F411CE | 1× Cortex-M4F | 1 | 5 hwd | DAPLink CMSIS-DAP (or WCH-Link) |
| `cortexm-weactf412` | cortexm | WeAct Studio F412RE | 1× Cortex-M4F | 1 | 5 hwd | ST-Link |
| `native` | posix-arch | the Linux host | host threads as CPUs | 4 (`-DNCPU`) | 20 host | — |
| `2xcortex-m33` | cortexm | QEMU `mps2-an521` | 2× Cortex-M33 | 2 | 4 QEMU | — |
| `pico2-1cpu` | cortexm | QEMU `mps2-an505` | 1× Cortex-M33 | 1 | 4 QEMU | — |
| `qemu-cortex-m0` | cortexm | QEMU `mps2-an385` | Cortex-M3 (the platform passes `--cpu cortex-m3`, not an M0) | 1 | 3 QEMU | — |
| `qemu-cortex-m3` | cortexm | QEMU `mps2-an385` | Cortex-M3 | 1 | 3 QEMU | — |
| `qemu-cortex-m4f` | cortexm | QEMU `mps2-an386` | Cortex-M4 | 1 | 3 QEMU | — |
| `qemu-cortex-m7f` | cortexm | QEMU `mps2-an500` | Cortex-M7 | 1 | 3 QEMU | — |
| `nucleo-f411re`, `nucleo-f767zi`, `nucleo-h743zi`, `raspberrypi-pico` | upstream | the upstream boards | | 1 | (do not configure, §10) | ST-Link / CMSIS-DAP |

Every platform has a `-cmake-gcc-debug` and a `-cmake-gcc-release`
configuration; `native` also has `-cmake-sys-*`, `-cmake-gccNN-*` and
`-cmake-clangNN-*`.

The QEMU machine for the Zero 2 W and Pi 3 B is `raspi3b -smp 4`, for the Pi 4 B `raspi4b -smp 4`; the AArch32 images are
started through a small AArch64 boot shim (`shim8.img`, image at `0x10000`).
The Cortex-M `-qemu` images of `cortexm-pico2` and `cortexm-pico2-rp2350b-psram`
run on `mps2-an500 -cpu cortex-m7`; those of `cortexm-pico` on
`mps2-an385 -cpu cortex-m3` (the generic M0 core).

The four `qemu-cortex-*` platforms link the local Cortex-M port's generic
single-core QEMU cores (`micro-os-plus::cortexm-qemu-m0/-m3/-m4f/-m7`) and the
generic device in `tests/device-qemu-cortexm`, and run the SMP kernel
single-core (`OS_NCPU=1`, no `OS_USE_SMP_SCHEDULER`). Each registers three
suites: `<platform>-rtos-apis-test`, `-mutex-stress-test` and
`-cmsis-os-validator-test`. (`2xcortex-m33` and `pico2-1cpu` likewise link the
local generic M33 core, `micro-os-plus::cortexm-qemu-m33`.)

## 3. Probes

| Board | Probe | USB id | Transport, speed | Config (in `tests/platforms/`) |
|---|---|---|---|---|
| Pi Zero 2 W, Pi 3 B (both ports) — default, `PROBE=jlink` | SEGGER J-Link | — | JTAG | `<arch>-rpi-zero-2w/openocd-jlink-rpi3.cfg` |
| the same, `PROBE=olimex` | Olimex ARM-USB-OCD (FTDI) | — | JTAG, 1000 kHz | `<arch>-rpi-zero-2w/openocd-olimex.cfg` |
| the same, `PROBE=cmsis-dap` | any CMSIS-DAP (Raspberry Pi Debug Probe, a Pico with the debugprobe firmware) | `2e8a:000c` | JTAG, 15000 kHz | `<arch>-rpi-zero-2w/openocd-cmsisdap-rpi3.cfg` |
| Pi 4 B | CMSIS-DAP (a Pico as JTAG probe) | `2e8a:000c` | JTAG, 4000 kHz | `aarch64-rpi4b/openocd-cmsis-dap-rpi4b.cfg` |
| Luckfox Lyra B | WCH-Link in ARM mode (CMSIS-DAP) | `1a86:8011` | SWD, 4000 kHz | `aarch32-luckfox-lyra/openocd.cfg` |
| Pico 2 | any CMSIS-DAP (no vid_pid pinned) | — | SWD, 1000 kHz | `cortexm-pico2/openocd.cfg` |
| Pi-Zero RP2350B | XV-Link CMSIS-DAP | `0416:5951` | SWD, 2000 kHz | `cortexm-pico2-pizero/openocd.cfg` |
| WeAct RP2350B + PSRAM | CMSIS-DAP | `c251:f001` | SWD, 100 kHz (higher speeds fail to connect/halt) | `cortexm-pico2-rp2350b-psram/openocd.cfg` |
| Pico (RP2040) | JTAGprobe (JTAGprobe_smp firmware on a second Pico), CMSIS-DAP v2 | `2e8a:000c` | SWD, 15000 kHz (`UOS_HW_ADAPTER_KHZ`) | `cortexm-pico/openocd.cfg` |
| Nucleo-F411RE | on-board ST-Link v2.1 | — | SWD, `connect_assert_srst` | `cortexm-nucleof411/openocd.cfg` |
| WeAct F411CE | DAPLink CMSIS-DAP (override: WCH-Link `1a86:8011` through `DAP_VID_PID`) | `0d28:0204` | SWD, 1000 kHz (`ADAPTER_KHZ`) | `cortexm-weactf411/openocd.cfg` |
| WeAct F412RE | ST-Link V2 / V2-1 / V3 | by class | SWD (`ADAPTER_KHZ`) | `cortexm-weactf412/openocd.cfg` |

The Zero 2 W's `openocd-probe.cfg` picks one of its three configurations
from `PROBE`; the Pi 3 B platforms use the Zero 2 W's. With several CMSIS-DAP
probes connected, `UOS_HW_ADAPTER_SERIAL` selects one by serial number.

## 4. The harness suites (portable)

Their sources live in `tests/sources/<suite>/`. They have no `main()`: the
entry is `os_main()`, and its return code is the verdict. On the board
platforms the tests' builder links each suite (`test::<suite>`) with the
platform's start-up and the common end, which prints the `RESULT:` line from
`os_main()`'s return value and ends the run (`board-tests/portable-test-end.cpp`,
`board-tests/cortexm/test-end.cpp` on Cortex-M); the platform's
`src/<suite>-support.cpp` adds what a suite needs from the board.

The same applies to the **portable tests** (`smp_test0` … `smp_test4`,
`smp-mat-test`, `smp-mat-sdcard-test`, `smp-num-test`, `smp-pipeline-test`,
`smp-pro-cons-test`, `sd_test`, `clock-test`): one copy in
`tests/sources/<test>/`, `os_main()` only, run by every platform that lists
it (§5, §6, §8).

| Suite | What it does |
|---|---|
| `rtos-apis` | Exercises the µOS++ C++ API, C API, ISO (`std::`) API, CMSIS-RTOS v1 wrapper and the POSIX I/O layer, plus a Chan FatFs test. |
| `mutex-stress` | Several threads take one mutex at random intervals; the test checks that every thread got it and the distribution is sane. |
| `fp-switch` | Six unpinned threads at three priorities each load their own pattern into s0-s31 and the FPSCR flags, spin long enough to be preempted (and, on SMP, moved to the other core), and check the registers read back unchanged. Needs an FPU; without one it passes with nothing to test. |
| `cmsis-os-validator` | The Arm CMSIS-RTOS v1 validator (60 test cases: threads, timers, signals, semaphores, mutexes, memory pools, message and mail queues, with interrupt-context cases). On a Cortex-M the interrupt is NVIC IRQ 0; see below for the other cores. |
| `blinky` | Blinks the LED. Enabled only on `nucleo-f411re` (`platforms/nucleo-f411re/cmake/definitions.cmake`), where it is the case `blinky-test`. |
| `instrumentation` | SEGGER SystemView use cases. Enabled only on `nucleo-f411re`, which builds `instrumentation-test` and `rtos-apis-instrumentation-test` but registers no CTest case for them: they are run from SEGGER Ozone with a J-Link (see `tests/sources/instrumentation/README.md`). |

Where each suite runs:

| Platform | `rtos-apis` | `mutex-stress` | `cmsis-os-validator` | Mode |
|---|---|---|---|---|
| `aarch32-rpi-zero-2w`, `aarch32-rpi3b`, `aarch64-rpi-zero-2w`, `aarch64-rpi3b`, `aarch64-rpi4b` | qemu, hwd | qemu, hwd | qemu, hwd | SMP 4 |
| `aarch32-luckfox-lyra` | — | hwd | — | SMP 3 |
| `cortexm-pico2` | qemu, hwd, ram | qemu, hwd, ram | qemu, hwd, ram | SMP 2 on hwd; single on qemu & ram (SRAM load) |
| `cortexm-pico` | qemu, hwd, ram | qemu, hwd, ram | qemu, hwd, ram | as `cortexm-pico2` |
| `cortexm-nucleof411`, `cortexm-weactf411`, `cortexm-weactf412` | hwd | hwd | hwd | SMP ×1 |
| `native` | host (`rtos-apis`, single; `smp-rtos-apis`, SMP 4) | host (`mutex-stress`, single; `smp-mutex-stress`, SMP 4) | host | see §8 |
| `2xcortex-m33` | QEMU | QEMU | QEMU | SMP 2 |
| `pico2-1cpu` | QEMU | QEMU | QEMU | single |
| `qemu-cortex-m0/m3/m4f/m7f` | QEMU | QEMU | QEMU | single (local cortexm port's generic QEMU cores, `OS_NCPU=1`) |
| `nucleo-*`, `raspberrypi-pico` | yes | yes | yes | single (upstream; these platforms do not configure, §10) |

`fp-switch` runs where an M33 FPU does: `cortexm-pico2` and `cortexm-pico2-rp2350b-psram` (qemu, hwd),
`2xcortex-m33` (QEMU, SMP 2) and `pico2-1cpu` (QEMU, single). On
`cortexm-pico` (Cortex-M0+, no FPU) it builds and passes with nothing to test.

On `cortexm-pico2` the `-qemu` image of a suite does not run the board at
all: QEMU has no RP2350, so the image links the generic single-core
Cortex-M QEMU core in its place (`board_test_qemu_libs`), with `NCPU` 1.

The validator is CMSIS-RTOS v1, which assumes one CPU. On the SMP platforms the
kernel's wrapper pins every thread `osThreadCreate()` makes to core 0
(`src/rtos/os-c-wrapper.cpp`). On the Pis the platform's
`src/cmsis-os-validator-support.cpp` pins the main thread too; on the RP2xxx
boards the validator's main thread keeps the default affinity while every
thread it creates is on core 0. On the BCM2837 (both Pi ports) its NVIC IRQ 0 is emulated with
the local Mailbox 1 interrupt, and the Cortex-M DWT cycle counter it probes is
answered by a RAM page that says "no cycle counter". Both exist only in the
validator's image (`UOS_CMSIS_OS_VALIDATOR`, `board_test_defines`). On `native`, the validator
xpack's own `SIGUSR1`/`SIGALRM` shims stand in for the NVIC.

## 5. AArch32 and AArch64 — Raspberry Pi Zero 2 W and Pi 3 B

The four (port, board) pairs run the same tests: the portable ones from
`tests/sources/` and `usb_test` from the platform's `tests/`
(`tests/platforms/<arch>-rpi-zero-2w/` and `<arch>-rpi3b/`). The Pi 3 B
platforms use the Zero 2 W's board code with `BOARD_RPI3B`. Every test is
built twice, `-qemu` and `-hwd`, except as noted.

| Test | What it does | Mode |
|---|---|---|
| `smp_test0` | Phase-1 bring-up: PL011 UART, MMU (cacheable, shareable DRAM), the 1 ms generic-timer tick and the scheduler, with one thread printing 10 heartbeats. | SMP 4, 1 active |
| `smp_test1` | Semaphore ping-pong across cores: pinger on core 0, ponger on core 1, a logger on core 2 blinking the LED and printing the round count and cores. | SMP 4 |
| `smp_test2` | Lock coherency: one worker pinned per core bumps a shared counter under a mutex; the final count must be `OS_NCPU × ITER`. | SMP 4 |
| `smp_test3` | `message_queue` producer (core 0) and consumer (core 1) that tests primes and toggles the LED; a logger prints throughput. | SMP 4 |
| `smp_test4` | Load balancing: CPU-bound workers with no affinity; a reporter prints each worker's per-core histogram. | SMP 4 |
| `smp-mat-test` | Parallel block Gaussian elimination (N = 120, B = 20) across all cores with spin barriers, a thread-pool demo, and a classical LU solve as ground truth; compares and times both. | SMP 4 |
| `smp-mat-sdcard-test` | The same solver at N = 200 with the matrices stored on and loaded from the SD card (`/sd/`, FAT on the boot card; under QEMU a fresh card image per run). | SMP 4 |
| `smp-num-test` | Five prioritised threads: UART ticker, LED blinker, an SD text writer, an FP compute writer and a reader, all sharing `num.txt` under one mutex, paced by a counting semaphore. | SMP 4 |
| `smp-pipeline-test` | 13 threads (4 producers, 4 compute workers, 2 SD writers, an auditor that checks CRC and sequence, an LED pacer, telemetry) with heavy `yield()`. | SMP 4 |
| `smp-pro-cons-test` | Producer/consumer that uses every kernel object (thread, memory pool, message queue, both semaphores, mutex, condition variable, event flags, timer, sysclock, suspend/resume). | SMP 4 |
| `sd_test` | SD card through µOS++ POSIX I/O and Chan FatFs (`/sd/`): reads a host-written seed file and writes files of its own under `/sd/tests/`; the boot card is never formatted. Under QEMU a fresh card image per run, seeded by the host. | SMP 4 |
| `usb_test` | DWC2 USB gadget file transfer: a host tool sends files over bulk OUT, stored to the SD card and hex-dumped to the UART and semihosting, with unpinned workers keeping every core busy. | SMP 4 |
| `clock-test` | The kernel's clocks against the BCM2837 System Timer: 5000 ticks of `sysclock` and `hrclock` keep its time; `hrclock.sleep_until (now () + 100 ms)` lasts 100 ms on cores 0 and 1, each woken promptly after core 0's tick. Guards the 2026-10-22 clock fixes. | SMP 4 |
| `rtos-apis`, `mutex-stress`, `cmsis-os-validator` | The harness suites (§4). | SMP 4 |

**Exception**: `usb_test` has **no `-hwd` case on the Pi 3 B**, only `-qemu`. The
Pi 3 B's USB ports sit behind the LAN9514 hub, so the DWC2 can only be a host.

Case counts: the Zero 2 W 36 (18 × 2) on both ports, Pi 3 B 31; the two Wi-Fi
tests are Zero 2 W only (§5.1). The Pi 4 B is §5.2.

### 5.1 Zero 2 W only — Wi-Fi (AArch32 and AArch64)

Two more board tests in `tests/platforms/aarch32-rpi-zero-2w/tests/` and
`aarch64-rpi-zero-2w/tests/`. They bring their stack with them, in the
platform's `wifi/`: an SDIO host on the Arasan controller, a driver for the
board's CYW43436 Wi-Fi chip with its firmware, and lwIP 2.2.1 without an OS
layer (`tests/third_party/lwip/`). The radio owns the Arasan controller, so
these two tests reach the SD card through the BCM2837's other controller
(`SD_BACKEND_SDHOST`, `sd_sdhost.cpp` in `micro-os-plus-iii-devices-bcm283x`);
the other tests are unchanged. One thread owns the radio and lwIP, a second
one the SD card.

The AArch32 copies are the AArch64 sources, with the platform services taking
time and the counter from the AArch32 port (`timer_arm`, CP15) because CNTFRQ
lies on this board (19.2 MHz reported, about 1 MHz actual). The driver, the
options and what was verified are in each platform's `wifi/README.md`.

| Test | What it does | Mode |
|---|---|---|
| `wifi-net` | Radio bring-up (firmware download), scan, join (WPA/WPA2, TKIP/AES, from the scan), DHCP, four ICMP echoes to the gateway; the run's log saved to `tests/WIFINET.LOG` on the SD card and read back. | SMP 4 build, core 0 only |
| `wifi-tcp-server` | The same bring-up, then a TCP echo server on port 7: a file sent by `wifi-tcp-host.py` is echoed, saved to `tests/WIFIRX.BIN` on the SD card, read back, and its size and CRC-32 printed. Needs the client. | SMP 4 build, core 0 only |

Both need the board, an access point and, at configure time,
`-D WIFI_TEST_SSID=... -D WIFI_TEST_PASS=...`; their `-qemu` cases only report
`RESULT: SKIP`. Verified on the board on 2026-11-13 with a CMSIS-DAP probe
(`PROBE=cmsis-dap`):

- AArch64: `wifi-net` PASS; `wifi-tcp-server` PASS with 1 MiB echoed and saved.
- AArch32: `wifi-net` PASS (joined, DHCP lease, four of four gateway pings,
  `tests/WIFINET.LOG` verified); `wifi-tcp-server` PASS with 256 KiB echoed and
  saved, CRC-32 `ff1d2b6f` equal on both sides, 5.7 Mbit/s each way
  (`tests/WIFIRX.BIN` and `WIFITCP.LOG` verified).

The Raspberry Pi 4 B has the wired counterparts, `eth-net` and `eth-tcp-server`
(§5.2).

### 5.2 AArch64 — Raspberry Pi 4 B (BCM2711)

`tests/platforms/aarch64-rpi4b/`: the portable tests and suites of §5 (not
`usb_test`: the Pi 4 B's gadget port is USB-C, tested by `usb_big_test`),
plus its own board tests. Every test is built `-qemu` (`raspi4b`) and `-hwd`.

| Test | What it does | Mode |
|---|---|---|
| the portable tests and suites | as in §5: `smp_test0` … `smp_test4`, `smp-mat-test`, `smp-mat-sdcard-test`, `smp-num-test`, `smp-pipeline-test`, `smp-pro-cons-test`, `sd_test`, `clock-test`, `rtos-apis`, `mutex-stress`, `cmsis-os-validator` | SMP 4 |
| `smp_mem_test` | 20 threads, 5 pinned per core, allocate, write, read back and free blocks of up to 512 MB from the RAM above the first GB at the same time ("over memory" is part of the run). | SMP 4 |
| `smp_mem_inter_test` | `smp_mem_test` plus inter-thread traffic: each block filled by its owner, modified by the next thread in a ring, checked again by the owner (CRC-32). | SMP 4 |
| `smp-list-storage-test` | A generic intrusive list with its nodes on a thread's stack, in the data segment and on the heap, shared by threads on all four cores. | SMP 4 |
| `smp-shapes-test` | Intrusive generic list, C++ polymorphism (abstract `shape`, four derived shapes) and threads on all four cores; output on the UART and the SD card. | SMP 4 |
| `eth-net` | GENET v5 + BCM54213PE Ethernet and lwIP under the scheduler: link, DHCP, ping, a log saved to the SD card. Needs the cable. | SMP 4 |
| `eth-tcp-server` | The same stack, then an RFC 862 echo server on port 7; the received stream saved to `tests/ETHRX.BIN` and read back. Needs the client `eth-tcp-host.py`. | SMP 4 |
| `usb_big_test` | DWC2 gadget on the USB-C port: a host tool sends a large file (MiBs) over bulk OUT; size and CRC-32 checked. Needs the host tool. | SMP 4 |

Under QEMU the network and USB tests report `RESULT: SKIP`. The Ethernet stack
is the platform's `net/` (README there); `smp-shapes-test` under QEMU is a
known flaky case (`baseline-2026-11-17/BASELINE.md` in the workspace).

## 6. AArch32 — Luckfox Lyra B (RK3506)

`tests/platforms/aarch32-luckfox-lyra/`. Hardware only: the board declares no
QEMU linker script. 21 tests, all `-hwd`, all SMP 3.

| Test | What it does |
|---|---|
| `smp_test0` … `smp_test4` | The same bring-up, ping-pong, lock-coherency, message-queue and load-balancing tests as on the Pis (§5), on three cores. |
| `smp-mat-test`, `smp-mat-sdcard-test`, `smp-num-test`, `smp-pipeline-test`, `smp-pro-cons-test`, `sd_test` | As on the Pis (§5), on the Lyra's SD card controller (DW-MMC). |
| `smp_test5` | Three pinned threads: an SD card thread on core 0 (FatFs mount, formatting FAT32 if none), an LED blinker on core 1 and a logger on core 2. |
| `smp_test6` | USB-to-UART logger on three cores: a DWC2 gadget task, a heartbeat logger and an LED task; driven from the host with `usb_test_host`. |
| `smp_test7` | USB vendor gadget receives a file, the SD task writes it as `received.dat`, then asks on the UART whether to delete it; the LED reflects the answer. |
| `smp_test_int` | First external interrupt: UART1 RX on the GIC (ID 99), with an ISR echo and a TX line lock shared with the ISR. Its console is UART-only (`UOS_CONSOLE_UART_ONLY`); only the verdict goes through semihosting, so typing on the UART cannot drop the WCH-Link. |
| `smp_test_int2` | Interrupt-driven TX through a THRE ring, and the UART1 interrupt routed to core 1 via `GICD_ITARGETSR`. |
| `smp_test_int3` | PC keyboard → board: USB OTG1 as an interrupt-driven vendor gadget on core 0 (GIC ID discovered at runtime), UART1 interrupt-driven on core 1. Needs the host tool `kbd_forward`. |
| `smp_test_int4` | Keystroke logger with three IRQs on three cores: USB (core 0) → ring → `keys.log` on the card, written with the DW-MMC data-transfer-over IRQ (core 2); UART on core 1. |
| `smp_test_int5` | AMP doorbell: the RK3506's Cortex-M0 fires Mailbox interrupts every ~40 ms to A7 cores 1 and 2, which report to core 0 over a shared ring. |
| `clock-test` | The kernel's clocks against the generic timer's counter read directly (CNTPCT, 24 MHz; the RK3506 has no BCM System Timer): 5000 ticks keep its time, `hrclock.sleep_until (now () + 100 ms)` lasts 100 ms on cores 0 and 1. Its console is the UART alone, sent through semihosting once at the end. |
| `mutex-stress` | Upstream's `mutex-stress` suite, built and registered by the shared builder like every other board's. |

Every Lyra test ends with a `RESULT:` line and a semihosting exit. The four
USB tests (`smp_test6`, `smp_test7`, `smp_test_int3`, `smp_test_int4`) wait
up to 120 s for the host to configure the gadget, then fail; they are built
`UOS_CONSOLE_UART_ONLY`, so their console does not mirror every line through
semihosting (each such trap halts the core, and during USB traffic that lost
the WCH-Link's debug link). Their host tools are C/C++ sources in the test's
own `host/` folder: `usb_test_host` for `smp_test6`/`smp_test7`,
`kbd_forward` for `smp_test_int3`/`smp_test_int4`.

## 7. Cortex-M

### 7.1 RP2350 boards

Three boards on the same silicon (2× Cortex-M33): `pico2`, `pico2-pizero` and
`pico2-rp2350b-psram`. On the single-core tests `OS_NCPU` is 1
(`board_test_ncpu`); the "bare" tests link no kernel (`BOARD_TEST_NO_KERNEL`).

| Test | What it does | Mode | pico2 | pizero | rp2350b-psram |
|---|---|---|---|---|---|
| `exc-test` | Bare exception-entry probe: SysTick with MSP, then PendSV with PSP. | bare | hwd | hwd | hwd |
| `smp-test0` | Bare boot chain and dual-core launch: C++ constructors, 150 MHz clocks, UART; core 1 blinks the LED. | bare, 2 cores | hwd | hwd | hwd |
| `smp-test1` | Single-core RTOS bring-up: three threads, sysclock, mutex, counting semaphore, LED heartbeat. | single | qemu, hwd | hwd | qemu, hwd |
| `sc-test-ko` | Single-core kernel-object test: ten self-checking sub-tests (mutex, semaphores, queues, event flags, timers, …), controller and helper on core 0. | single | qemu, hwd | hwd | qemu, hwd |
| `smp-test-ko` | The SMP twin of `sc-test-ko`: controller pinned to core 0, helper to core 1, so every hand-off is cross-core. | SMP 2 | hwd | hwd | hwd |
| `smp-test2` | Dual-core SMP: per-core PendSV and SysTick, affinity (one worker per core), SIO spinlock-backed kernel lock. | SMP 2 | hwd | hwd | hwd |
| `smp-test3` | Cross-core IPI through the SIO FIFO: semaphore ping-pong with the one-way wake latency measured on TIMER0. | SMP 2 | hwd | hwd | hwd |
| `smp-test4` | Kernel objects under dual-core contention: seven round-trip sub-tests between a controller (core 0) and a worker (core 1). | SMP 2 | hwd | hwd | hwd |
| `smp-test5` | First peripheral interrupt: UART0 TX IRQ serviced on core 1, draining a ring filled by core 0. | SMP 2 | hwd | hwd | hwd |
| `clock-test` | The kernel's clocks against TIMER0 on both cores: sysclock and hrclock keep its time, `hrclock.sleep_until (now () + 100 ms)` lasts 100 ms. Guards the 2026-10-22 fixes (hrclock's units and origin, the tick caught up from TIMER0). | SMP 2 | hwd | — | — |
| `smp-mat-test` | Parallel block solver (N = 100, B = 50) on two cores. On `pico2-rp2350b-psram` its data lives in PSRAM. | SMP 2 | hwd | hwd | hwd |
| `smp-test-usb-cdc-acm` | USB CDC-ACM virtual serial port: echoes what the host types, mirrored on the UART. | SMP 2 | hwd | hwd | — |
| `smp-test-usb-hid` | USB HID keyboard forwarding; keystrokes printed on the UART. | SMP 2 | hwd | hwd | — |
| `psram-exec` | Bare SRAM supervisor that copies two apps into PSRAM and switches between them on a key press. | bare | — | hwd | — |
| `psram-mat-test-250` | `smp-mat-test` with PSRAM brought up by the app itself, at 250 MHz, from an SRAM-boot linker script. | SMP 2 | — | hwd | — |
| `smp-test-nested` | Nested interrupts on both cores (SysTick, UART0, TIMER0 IRQ 2/3 at different priorities) with thread migration and a lock-free trace. Passes once both workers have run 20 beats and all three nesting interrupts have fired. | SMP 2 | — | — | hwd |
| `smp-test-nested-clock` | `smp-test-nested` plus a clock tree driven from a potentiometer (ADC) and the on-die temperature sensor; data in PSRAM, 250 MHz enabled. **Interactive**: waits for `y` on the UART (a pot position other than the current clock reboots into it first), then the same 20-beat verdict. | SMP 2 | — | — | hwd |
| `smp-test-nested-clock_200` | The same, without `PICO2_ENABLE_250MHZ` (the clock tree at its default). The pot/`y` reboot drops the debug state, so this is a **manual UART-verified** case (label `hwd-manual`). | SMP 2 | — | — | hwd-manual |
| `smp-test-nested-clock_250` | The same, with 250 MHz enabled; also **manual** (label `hwd-manual`). | SMP 2 | — | — | hwd-manual |
| `rtos-apis`, `mutex-stress`, `cmsis-os-validator` | The harness suites (§4). | single | qemu, hwd | — | — |
| `fp-switch` | The harness suite (§4): six unpinned threads at three priorities keep their own s0–s31 and FPSCR flags across preemptive switches. | single | qemu, hwd | — | qemu, hwd |
| `cmsis-os-validator-ram`, `mutex-stress-ram`, `rtos-apis-ram` | RAM-resident harness suites executing entirely from internal SRAM (no flash writes). | single | hwd | — | — |
| `smp-mat-test-ram` | Parallel block solver executing entirely from internal SRAM (no flash writes). | SMP 2 | hwd | — | — |

Case counts: `pico2` 27 (6 qemu, 21 hwd), `pico2-pizero` 14, `pico2-rp2350b-psram` 18 (3 qemu, 15 hwd: 12 automatic + 1 interactive CTest + 2 `hwd-manual`).

### 7.1a RP2040 board

`pico` (Raspberry Pi Pico, RP2040, 2× Cortex-M0+) runs the `pico2` column of
the table above, adapted to the RP2040, with no Pico SDK: the same 26 cases
(20 `hwd`, 6 `qemu`). The differences: 125 MHz clocks; the RP2040 TIMER,
reset bits and IRQs (the SIO FIFO IPI on IRQs 15/16, UART0 on 20, USB on 5);
`smp-mat-test` at N = 80, B = 20 to fit 264 KB of SRAM; `exc-test` without
UsageFault (ARMv6-M has HardFault only); the USB CDC test lights the onboard
LED instead of a WS2812; `fp-switch` has no FPU to test. The `-qemu` images
run single-core on `mps2-an385 -cpu cortex-m3`. The probe is the JTAGprobe
over SWD at 15 MHz.

All 26 passed on 2026-10-13 (debug): 6/6 QEMU and 20/20 on the board, the two
USB tests interactively (Escape then Return in the CDC terminal; Escape
through `kbd_forward` for HID). Release: 6/6 QEMU and 18/18 on the board
(the two USB tests not run).

### 7.2 STM32F4 boards (one CPU)

The three boards are hardware-only: their platforms register no QEMU case.
The harness suites build the SMP scheduler at `OS_NCPU = 1`; the board's own
tests use the kernel's non-SMP branch.

| Test | What it does | Mode | nucleof411 | weactf411 | weactf412 |
|---|---|---|---|---|---|
| `mos-test1` | Single-CPU acceptance: producers and consumers over a bounded buffer with plain and recursive mutexes, counting semaphores, sysclock and an LED thread. | single | hwd | hwd | hwd |
| `spi-pipeline` | SPI-flash pipeline (ported from a Rust example): five threads, eight semaphores, Base64 encode to partition 1, decode and CRC check to partition 2, on the board's own flat-file archive. | single | — | hwd | — |
| `uart-test1` | USART1 echo: RX interrupt → bounded buffer → TX via DMA2, with an LED thread. | single | — | — | hwd |
| `rtos-apis`, `mutex-stress`, `cmsis-os-validator` | The harness suites (§4). | SMP ×1 | hwd | hwd | hwd |

The F412 cannot run under QEMU in any case: its 256 KB of SRAM puts `_estack`
at `0x20040000`, beyond the 128 KB of QEMU's `netduinoplus2`, and
`uart-test1`'s DMA2 Stream 7 is not modelled.

**Ending a board test (`hw_result.hpp`).** In
`tests/board-tests/cortexm/hw_result.hpp`, tests end with `std::_Exit(0|1)`
rather than `std::exit()`: `exit()` runs the `atexit` handlers and static
destructors while RTOS threads are still alive, which fails
`assert(empty())` in `double_list::~double_list()`. `_Exit()` is the
semihosting exit at once.

## 8. POSIX — native host

`tests/platforms/native/`. Host threads stand in for
CPUs: `NCPU` defaults to 4 (`-DNCPU=1` builds everything single-core). All
cases are `-host`.

| Test | What it does | Mode |
|---|---|---|
| `smp_test0` … `smp_test4` | The Pi tests of the same names (§5), on host threads. | SMP 4 (`smp_test0`: 1 active) |
| `smp-mat-test`, `smp-num-test`, `smp-pipeline-test`, `smp-pro-cons-test` | As on the Pis; the SD card is a host file with a card's layout (`UOS_SD_IMAGE`, fresh per run), under POSIX I/O and Chan FatFs. | SMP 4 |
| `mutex-stress` | The upstream suite, unchanged. | single |
| `rtos-apis` | The upstream suite, with the POSIX I/O layer. | single |
| `smp-mutex-stress` | The SMP leg of `mutex-stress`, with `smp_test2`'s start-up. | SMP 4 |
| `smp-rtos-apis` | The whole `rtos-apis` sequence once per core, from a driver pinned to that core, with the API threads unpinned; fails unless every core did the work. | SMP 4 |
| `mutex-ceiling-test` | A thread above a robust protect mutex's ceiling gets `EINVAL`; after it is destroyed, lock/unlock at the ceiling must still work (no `EOWNERDEAD`). | SMP 4 |
| `cmsis-os-validator` | The validator (§4), built and registered by the platform itself. | SMP 4, validator on core 0 |
| `clock-test` | `hrclock.sleep_until (now () + 100 ms)` lasts 100 ms of `CLOCK_MONOTONIC`, and `hrclock.now()` is close to its steady count (the 2026-10-22 origin fix: it used to wait the host's uptime). | SMP 4 |

16 cases.

## 9. How to run

In the kernel's `tests/`, for a configuration `C` such as
`aarch64-rpi3b-cmake-gcc-debug` (the full list: [`COMMANDS.md`](COMMANDS.md)):

```sh
xpm run install --config C && xpm run link-deps --config C
xpm run prepare --config C && xpm run build --config C
xpm run test --config C                       # every qemu/host case
cd build/C
ctest -N                                      # list the cases
ctest -R '^<platform>-<test>-<variant>$' --output-on-failure   # one case
ctest -L hwd                                  # every hardware case, one after another
```

On the Zero 2 W and the Pi 3 B choose the probe with
`PROBE=jlink|olimex|cmsis-dap`. Some hardware tests need the PC's side during
the run (USB, network); their READMEs say what to run.

## 10. Last verified run

**QEMU and host** (2026-11-20, clean rebuild): the full matrix passes —
AArch32 and AArch64 Pi Zero 2 W / Pi 3 B / Pi 4 B, the QEMU Cortex-M boards,
`2xcortex-m33`, `pico2-1cpu`, the Pico 2 boards and the POSIX host. The two
initial failures (`aarch32-rpi3b-smp-pipeline-test-qemu`, the PSRAM board's
`cmsis-os-validator` on RPi 4 B) passed on rerun.

**Hardware** (2026-11-20, through CTest and OpenOCD; logs in the workspace's
`hw-check/2026-11-20-*`):

| Board | Result |
|---|---|
| Raspberry Pi 4 B | 22/22 (19 automatic + `eth-net`, `eth-tcp-server`, `usb_big_test`) |
| Raspberry Pi 3 B AArch64 / AArch32 | 15/15 each |
| Raspberry Pi Zero 2 W AArch64 / AArch32 | 18/18 each (Wi-Fi and USB included) |
| Luckfox Lyra B | 21/21 (the USB tests driven from the PC) |
| Pico 2 | 21/21 |
| Pico (RP2040) | 20/20 on 2026-11-19 (not rerun in this round) |
| Pi-Zero RP2350B | 14/14 (12 automatic + CDC-ACM + HID) |
| WeAct RP2350B + PSRAM | 12 automatic + `smp-test-nested-clock` (interactive, CTest-recorded); the two `hwd-manual` clock tests PASS on the UART |
| Nucleo-F411RE | 4/4 |
| WeAct F411CE | 5/5 |
| WeAct F412RE | 5/5 |

The OpenOCD route (`-hwd`) is proven on every local board. The PSRAM
`smp-test-nested-clock_200`/`_250` cases remain manual: their clock reboot
drops the debug state, so the `RESULT` is read on the UART.

**2026-11-21, Pi 4 B, Pico 2 and Lyra:** Pi 4 B **22/22** (19 automatic,
plus `eth-net`, `eth-tcp-server` with `eth-tcp-host.py`, and `usb_big_test`
with `usb_test_host --big`); Pico 2 **21/21** (19 automatic, plus the CDC-ACM
and HID cases driven from the PC host); Luckfox Lyra **21/21** (17 automatic,
plus `smp_test6` and `smp_test7` with `usb_test_host` and the `y` delete
confirmation on the UART, and `smp_test_int3`/`_int4` with the key records
the PC forwarder sends); AArch32 Zero 2 W **18/18** (15 automatic, plus
`usb_test` with `send_file.py`, `wifi-tcp-server` with `wifi-tcp-host.py`,
and `wifi-net`), at a 15 MHz CMSIS-DAP JTAG clock; AArch64 Zero 2 W
**18/18** with the same set and clock; Pi-Zero RP2350B **14/14** (12
automatic, plus the CDC-ACM and HID cases driven from the PC host).

The upstream `nucleo-f411re`, `nucleo-f767zi`, `nucleo-h743zi` and
`raspberrypi-pico` platforms do not configure (the Cortex-M port does not find
the kernel through their xpacks path), as on the reference `smp` branch.
