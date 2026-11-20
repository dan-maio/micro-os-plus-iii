# Building the AArch32 and AArch64 ports

From an empty folder to every AArch test image, run under QEMU or on a
Raspberry Pi (Zero 2 W, 3 B, 4 B) or a Luckfox Lyra B. The ports are built
the way upstream builds its Cortex-M port: as xPack dependencies of the
kernel's test project, `micro-os-plus-iii/tests`. The AArch ports carry no
tests of their own.

---

## 1. Get the sources

Each architecture package keeps **no copy** of the kernel, and the drivers
are separate device packages:

```text
<workspace>/
├── micro-os-plus-iii/                     the kernel; every test is in tests/
├── aarch32/micro-os-plus-iii-aarch32/     the AArch32 port (ARMv7-A)
├── aarch32/micro-os-plus-iii-devices-rk3506/   the RK3506 SD host (Lyra)
├── aarch64/micro-os-plus-iii-aarch64/     the AArch64 port (ARMv8-A)
└── common/
    ├── micro-os-plus-iii-devices-bcm283x/ BCM2837/BCM2711: SoC, SD, SDHOST, DWC2 USB
    └── micro-os-plus-iii-devices-storage/ the SD card as a posix-io block device
```

Register each package once with xpm (in its folder: `xpm link`), then link
them into the configurations that use them:

```sh
cd <workspace>/micro-os-plus-iii/tests
xpm run install   --config aarch64-rpi4b-cmake-gcc-debug
xpm run link-deps --config aarch64-rpi4b-cmake-gcc-debug
```

`link-deps` links the port, `-devices-storage` and the SoC packages
(`-devices-bcm283x`; on AArch32 also `-devices-rk3506`) into
`build/<configuration>/xpacks/@micro-os-plus/`. The full install sequence is
in [`tests/COMMANDS.md`](tests/COMMANDS.md) §2.

## 2. Tools

xpm installs the pinned tools per configuration: `aarch64-none-elf-gcc` 15
(AArch64, and the AArch32 QEMU boot shim), `arm-none-eabi-gcc` 15 (AArch32),
CMake, Ninja, `qemu-arm` and `openocd`. The tests run the configuration's
`build/<configuration>/xpacks/.bin` copies (QEMU 9.x is pinned for the AArch
platforms, since `raspi4b` needs it); if a configuration has none, the ones
on `PATH` are used.

## 3. Configure and build

Every board is a platform of the test project, `tests/platforms/<platform>/`,
with a debug and a release configuration:

| Configuration prefix | Port | Silicon | SMP cluster | `-mcpu` | Tests |
|---|---|---|---|---|---|
| `aarch64-rpi-zero-2w` | aarch64 | BCM2837 | 4× Cortex-A53 | `cortex-a53` | 18 (qemu + hwd) |
| `aarch64-rpi3b` | aarch64 | BCM2837 | 4× Cortex-A53 | `cortex-a53` | 16 (15 on hardware) |
| `aarch64-rpi4b` | aarch64 | BCM2711 | 4× Cortex-A72 | `cortex-a72` | 22 (qemu + hwd) |
| `aarch32-rpi-zero-2w` | aarch32 | BCM2837 | 4× Cortex-A53 (32-bit) | `cortex-a53` | 18 (qemu + hwd) |
| `aarch32-rpi3b` | aarch32 | BCM2837 | 4× Cortex-A53 (32-bit) | `cortex-a53` | 16 (15 on hardware) |
| `aarch32-luckfox-lyra` | aarch32 | RK3506 | 3× Cortex-A7 | `cortex-a7` | 21 (hwd only) |

```sh
cd <workspace>/micro-os-plus-iii/tests
xpm run prepare --config aarch32-rpi3b-cmake-gcc-debug
xpm run build   --config aarch32-rpi3b-cmake-gcc-debug
```

or a whole board, debug and release, prepared, built and tested under QEMU:
`xpm run test-aarch32-rpi3b-cmake` (and `test-aarch64-rpi4b-cmake`, … ;
`xpm run test-smp-cmake` for all the emulated SMP boards). The Lyra has
`xpm run build-aarch32-luckfox-lyra-cmake`.

The Pi 3 B platforms use the Zero 2 W's board code with `BOARD_RPI3B` and
their own linker script. The board facts (flags, CPU count, linker scripts,
LED pin, the SD driver set) are each platform's `cmake/board.cmake`.

`luckfox-lyra` is the RK3506's three Cortex-A7. Its Cortex-M0 is a different
ISA outside the coherency domain and is not a CPU the scheduler can use, so
the board is multi-core while the SMP cluster is three. It carries the
predecessor's RK3506 tests as well as the portable ones (the GIC-400 SGI
pair, the USB gadget tests, the SD tests and the Cortex-M0 doorbell), and is
the only **hardware-only** AArch board: its `board.cmake` sets no QEMU linker
script, so it builds one image per test. QEMU models none of the RK3506's
own blocks, so there would be nothing for one to prove.

### What you get

In `build/<configuration>/platform-bin/port-tests/test/`, for each test and
variant, an ELF, a `.bin` (the `kernel8.img` / `kernel7.img` equivalent) and
a `.map`:

```
smp_test0-qemu.{elf,bin,map}     smp_test0-hwd.{elf,bin,map}
sd_test-qemu...                  sd_test-hwd...
...
shim8.img                        the AArch32 QEMU boot shim
```

`qemu` is the emulator build; `hwd` the board's (`HW_BUILD`: the SD tests use
the card's existing FAT32 boot partition). Which tests a board builds, and
how they are built, is in
[`tests/TESTS-DEVELOPER-GUIDE.md`](tests/TESTS-DEVELOPER-GUIDE.md); what each
does is in [`tests/TESTS-CATALOG.md`](tests/TESTS-CATALOG.md).

## 4. Running the QEMU tests

```sh
cd build/aarch32-rpi3b-cmake-gcc-debug
ctest -L qemu                                        # all of them
ctest -R '^aarch32-rpi3b-smp_test2-qemu$' -V         # one
```

CTest starts QEMU itself (`tests/cmake/uos-tests-run.cmake`): `raspi3b -smp 4`
for the Zero 2 W and the Pi 3 B, `raspi4b -smp 4` for the Pi 4 B, with
semihosting. The verdict is the test's `RESULT:` line.

QEMU's `raspi3b` starts its Cortex-A53 cores in AArch64, so an AArch32 image
is started through a 20-line shim (`shim8.img`) that drops to AArch32 and
jumps to the image, loaded with `-device loader` at `0x10000`.

> **Not `raspi2b`.** The port is built `-mcpu=cortex-a53`, so its
> load-acquire instructions are undefined on the raspi2b Cortex-A7 and the
> image faults at the first one. Hardware needs no shim at all: `config.txt`
> sets `arm_64bit=0` and the cores come up in AArch32 directly.

The SD tests get a fresh 4 GiB card image with a boot card's layout (MBR +
FAT32; `sd_test`'s seeded by the host) from a CTest fixture, deleted after
the run. `usb_test`, the network and the USB tests report `RESULT: SKIP`
(QEMU emulates no USB device mode).

> **Run one emulated SMP suite at a time.** Two four-core suites at once, or
> one alongside a build, starves a QEMU vCPU: a worker freezes mid-loop with no
> fault, which looks exactly like a deadlock. Re-run on an idle host before
> investigating.

## 5. Running on hardware

### Standalone boot

Copy a `*-hwd.bin` as `kernel8.img` (AArch64) or `kernel7.img` (AArch32) to
the boot partition, with the platform's `config.txt`.

### Debug-in-RAM, through OpenOCD

```sh
cd build/aarch64-rpi-zero-2w-cmake-gcc-debug
PROBE=cmsis-dap ctest -R '^aarch64-rpi-zero-2w-smp_test2-hwd$' --output-on-failure
PROBE=cmsis-dap ctest -L hwd                         # every hardware test
```

CTest runs OpenOCD with the board's configuration and
`tests/cmake/uos-hwd.tcl`: halt the cores, enable semihosting, the board's
hooks, an optional pre-load, `load_image`, resume in the board's mode. It is
**pure OpenOCD** — no GDB — and it never opens the serial device, so it cannot
fight the terminal you keep on the console (`tio -b 115200 <port>`). The test's
semihosting `SYS_EXIT` ends OpenOCD, and its `RESULT` line is the verdict.

Neither board has a reset line a probe can drive, so before each hardware
test CTest runs a reset in its own OpenOCD session, as a fixture
(`<test>-hwd-reset`): the Pi's PM watchdog, then a wait for the firmware to
boot and re-enable JTAG; on the Lyra, the RK3506 global software reset. If
that session does not reach the board, the test is not run. The tests can
therefore run one after another without power cycles.

| Env | Meaning |
|---|---|
| `PROBE` | the Zero 2 W and Pi 3 B probe: `jlink` (default), `olimex`, `cmsis-dap` |
| `UOS_HW_ADAPTER_SERIAL` | which CMSIS-DAP, by serial number, when several are connected |
| `UOS_HW_ADAPTER_KHZ` | the JTAG/SWD clock. `board/rpi3.cfg` asks for 4000 kHz, more than jumper wires always carry; a probe that gives up mid-run prints `Invalid ACK (0) in DAP response` and fails to re-examine the cores |

A test's time limit is **not** its own duration: it is dominated by
semihosting traps and the image load. `smp_test4` reaches its verdict at
t=9597 ms of target time yet needs well over 120 s of wall clock, because its
reporter emits about nine lines a second and each is a debug halt and resume
over JTAG; on the Pi 4 B the CMSIS-DAP image load alone takes minutes.

### On a Luckfox Lyra B

```sh
cd build/aarch32-luckfox-lyra-cmake-gcc-debug
ctest -R '^aarch32-luckfox-lyra-smp_test0-hwd$' --output-on-failure
```

The same run, with the board's facts in its `CMakeLists.txt` and `openocd.cfg`:

- **The probe is a WCH-Link over SWD** (`cmsis-dap`, USB `1a86:8011`,
  4000 kHz). There is no `PROBE` choice. Do not run it beside another
  CMSIS-DAP board: the WCH-Link loses its link.
- **Only core 0 is a debug target when the image is loaded.** Cores 1 and 2
  sit in the BootROM until the kernel clears their CRU reset bits, so the
  configuration declares them `-defer-examine` and the run drives core 0
  alone. The secondaries are released through the SRAM mailbox, not a spin
  table.
- **The MMU and caches are turned off before the load.** The Rockchip
  miniloader hands core 0 over with both on, and `load_image` writing through
  a dirty cache leaves DRAM holding something other than the image. The run's
  pre-load clears `SCTLR.{M,C,I}` and invalidates the I-cache, branch
  predictor and TLB, the sequence the predecessor's `write_board.sh` used.

The console is the Lyra debug header at **115200**, the rate the miniloader
leaves UART1 at; the port does not reprogram it unless the build defines
`UART_BAUD`. The USB tests (`smp_test6`, `smp_test7`, `smp_test_int3`,
`smp_test_int4`) need the USB1 (OTG1) port connected to the PC and their host
tool (`host/` in the test's folder).

### The boot card

The SD tests and `usb_test` mount the card's **existing** FAT32 partition at
`/sd/` (µOS++ POSIX I/O, Chan FatFs with long file names) and keep every file
under `/sd/tests/`. They never format it and never touch the root.

### `usb_test` needs a host

Power the Zero 2 W from **`PWR IN`** and run the data cable from the PC to the
**`USB`** socket — the OTG port. On the wrong socket the board boots and prints
normally but never enumerates, with no error message.

```sh
ctest -R '^aarch64-rpi-zero-2w-usb_test-hwd$' --output-on-failure   # one terminal
# once 1d6b:0104 is on the bus, in another (the kernel's tests/):
python3 platforms/aarch64-rpi-zero-2w/tests/usb_test/send_file.py <file> --get --terminate
```

`host_xfer.py` runs the size matrix instead — 0, 1, 511, 512, 513, 1024,
65536, 1048576 bytes, each written and read back with CRC checks — then a
`LIST`, then the terminating `PING` that makes the device print its tally and
`RESULT`. Without that ping the device serves commands until its time limit.

The verdict is `crc_errors == 0 && commands != 0 && active >= 3`: at least
three of the four cores must have run the unpinned load generators, which is
what makes it an SMP test and not only a USB one. The Pi 3 B has no hardware
`usb_test`: its USB ports sit behind the on-board hub.

### Defects this suite found

Hardware exercised paths QEMU cannot, and five of them were real:

| Defect | Why only on hardware |
|---|---|
| Every blinking test drove **GPIO16** | `led.hpp` falls back to header pin 36; the Zero 2 W's onboard ACT LED is GPIO29. Only `usb_test` had ever set `LED_PIN`. It is a board fact now, set once for every test. |
| `usb_test` replied to a PUT **after** its console output | The reply is sent immediately after the store now. The hexdump and listing are queue posts drained one semihosting trap at a time, so a completed store looked like a hang. |
| Console posts **blocked** the USB service thread | They use `try_send` now and are dropped when the consumer falls behind, with `console_dropped` in the tally. Diagnostics must never throttle the protocol. |
| `LIST` compared names case-sensitively | the emulated card kept the name as sent, the board's FAT returned it in upper case (8.3 names, before long names were enabled). |
| **`kOutChunkMax` overflowed `PKTCNT`** | `D{I,O}EPTSIZ` is bounded by *two* fields. This core reports `GHWCFG3 = 0x0ff000e8`: XFRSIZ 19 bits (524287 bytes) but PKTCNT **10 bits — 1023 packets**, so 65472 bytes at full speed. The old `0x7F000` was sized against XFRSIZ alone and against 512-byte packets, and asked for 8128 packets in a 10-bit field. A 1 MiB transfer stored 61440 bytes, truncated. 65536 was the last size to pass because it overflows the field by exactly one packet. |

`DEBUG_BOOT` is off by default in the `hwd` builds — each early-boot marker is
a semihosting trap. `-D UOS_DEBUG_BOOT=ON` on `prepare` restores them for
board bring-up.

## 6. Adding a test

A test is never declared by hand. A portable one is a folder in
`tests/sources/` listed in the platform's `UOS_TESTS_SOURCES`; a board-only
one is a folder in `tests/platforms/<platform>/tests/`, found by the builder's
glob. The builder (`tests/board-tests/CMakeLists.txt`) builds each in both
variants, with the kernel, the port, the board, `OS_NCPU` (and
`OS_USE_SMP_SCHEDULER` above one), the board's flags and linker script, and
emits the `.bin`. See [`tests/TESTS-DEVELOPER-GUIDE.md`](tests/TESTS-DEVELOPER-GUIDE.md) §8.

## 7. CMake targets

### The kernel, `micro-os-plus-iii`

| Target | Contents |
|---|---|
| `micro-os-plus::iii` | the kernel core every port compiles |
| `micro-os-plus::iii-posix-io` | the file-descriptor layer (the storage tests' `/sd/`) |
| `micro-os-plus::iii-startup` | the generic reset path — a port with its own `startup.S` skips it |
| `micro-os-plus::iii-newlib-reent`, `-semihosting` | the C library and semihosting groups |
| `micro-os-plus::iii-trace-itm` / `-trace-semihosting` / `-trace-segger-rtt` | mutually exclusive; link at most one |

### The ports and the device packages

| Target | Package | Contents |
|---|---|---|
| `micro-os-plus::aarch32`, `micro-os-plus::aarch64` | the ports | the port, its `-mcpu` as a compile **and** link option (without it at link time every AArch32 link fails with *"uses VFP register arguments"*) |
| `micro-os-plus::soc-bcm2837`, `-soc-bcm2711` | `-devices-bcm283x` | registers, IRQ, mailbox, GIC-400 (BCM2711) |
| `micro-os-plus::devices-sd-posix`, `-sdhost-posix` | `-devices-bcm283x` | the Arasan SDHCI and the SDHOST card as `/dev/sd` |
| `micro-os-plus::devices-usb` | `-devices-bcm283x` | the DWC2 USB gadget |
| `micro-os-plus::devices-rk3506-sd-posix` | `-devices-rk3506` | the RK3506 DW-MMC card as `/dev/sd` |
| `micro-os-plus::devices-storage-posix`, `-storage-sd` | `-devices-storage` | the block device and the card's SD protocol |

The board itself is `micro-os-plus::board`, defined by the platform
(`tests/cmake/uos-aarch-board.cmake`).
