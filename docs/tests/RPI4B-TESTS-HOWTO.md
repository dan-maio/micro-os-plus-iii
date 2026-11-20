# RPi 4B tests — build, run, clean (µOS++ III, AArch64)

The Raspberry Pi 4 B (BCM2711, 4× Cortex-A72) is the platform
`tests/platforms/aarch64-rpi4b/` of the kernel's test project. Its board
code and board-only tests are there; the portable tests are in
`tests/sources/`. CTest builds and runs everything: QEMU (`raspi4b`) and the
board through OpenOCD.

## 0. Prerequisites (once per PC)

| Need | Command / note |
|---|---|
| `git`, Node.js + `npm` | from the distribution |
| `xpm` | `npm install -g xpm@latest` |
| internet | the first `xpm install` downloads CMake, Ninja, GCC and QEMU into `~/.local/xPacks` |
| **OpenOCD, for `-hwd` only** | installed per configuration by `xpm run install --config <C>` (`@xpack-dev-tools/openocd@0.12.0-7.1`) |
| probe, for `-hwd` only | CMSIS-DAP JTAG probe with user access (udev); a USB-serial on the Pi UART (GPIO14/15) |

The hardware tests use the configuration's
`build/<configuration>/xpacks/.bin/openocd`; if it has none, `openocd` from
`PATH` is used (`UOS_TESTS_OPENOCD` in the build folder's cache says which).

## 1. Get the sources

The workspace layout and the one-time `xpm link` of each package are in
[`COMMANDS.md`](COMMANDS.md) §1–§2. The Pi 4 B needs the kernel, the AArch64
port and the device packages `micro-os-plus-iii-devices-bcm283x` and
`micro-os-plus-iii-devices-storage`.

## 2. Names

| Item | Value |
|---|---|
| Run all commands from | `<workspace>/micro-os-plus-iii/tests` |
| Board files (code, OpenOCD cfg, `config.txt`) | `tests/platforms/aarch64-rpi4b/` |
| Board-only tests | `tests/platforms/aarch64-rpi4b/tests/<test>/` |
| Portable tests | `tests/sources/<test>/` |
| Configurations `C` | `aarch64-rpi4b-cmake-gcc-debug` (Debug), `aarch64-rpi4b-cmake-gcc-release` (MinSizeRel) |
| Build folder | `build/$C/` (one per configuration) |
| Images | `build/$C/platform-bin/port-tests/test/<test>-hwd.elf`, `<test>-qemu.elf` |
| CTest case | `aarch64-rpi4b-<test>-<variant>` |

**Variants**

- `-qemu` runs in QEMU (`raspi4b`); needs no board.
- `-hwd` runs on the board: OpenOCD over the CMSIS-DAP JTAG probe, with no GDB.

**Tests (22):** `smp_test0` … `smp_test4`, `smp-mat-test`,
`smp-mat-sdcard-test`, `smp-num-test`, `smp-pipeline-test`,
`smp-pro-cons-test`, `sd_test`, `clock-test`, `cmsis-os-validator`,
`mutex-stress`, `rtos-apis` (portable), and the board's own `smp_mem_test`,
`smp_mem_inter_test`, `smp-list-storage-test`, `smp-shapes-test`, `eth-net`,
`eth-tcp-server`, `usb_big_test`.

`smp-list-storage-test` and `smp-shapes-test` are the C++ versions of tests
first written for the Zig port, check for check: `smp-list-storage-test` is a
generic intrusive list with its nodes on thread stacks, in `.data` and on the
heap, under thread churn on the 4 cores (UART only); `smp-shapes-test` is a
list of polymorphic shapes (an abstract C++ base class and four derived ones,
built and destroyed by threads on the 4 cores), with a logger thread writing
every line to the UART and to `tests/shapes.log` on the SD card, read back
and CRC-checked.

`clock-test` checks the kernel's clocks against the BCM2711 System Timer
(1 MHz): 5000 ticks of `sysclock`, and `hrclock` over them, keep its time;
`hrclock.sleep_until (now () + 100 ms)` lasts 100 ms (+1 tick) on core 0 and
on core 1; and a thread on core 1 wakes promptly after core 0's tick. It
guards the clock fixes of 2026-10-22: the tick re-armed on an absolute grid
(`timer_arm::rearm_1ms()`, `CNTP_CVAL += period`; re-arming one period from
*now* in the interrupt lost the handler's latency every tick), `hrclock.now()`
counted from core 0's tick origin (`timer_arm::hr_base()`), and the counter's
frequency calibrated once instead of by every core. On the board: 5000 ticks
= 5 000 000 µs, the 100 ms sleep 101.0 ms on both cores.

`eth-net` and `eth-tcp-server` are the Ethernet tests, the wired
counterparts of the Zero 2 W's Wi-Fi tests. They bring their network stack
with them: a polled driver for the BCM2711's GENET v5 controller and its
BCM54213PE PHY, lwIP 2.2.1 without an OS layer, and the glue between them, in
the platform's `net/`; lwIP itself is in `tests/third_party/lwip/`. One
thread owns the controller and lwIP and polls every 2 ms; a second thread
owns the SD card, so the link stays serviced while a file is written. Both
need the board on a network (a cable to a router with DHCP, or a static
address, §5a); their `-qemu` images only report `RESULT: SKIP`. The driver,
the threads and the options are described in the platform's `net/README.md`.

- `eth-net`: controller and PHY, link, DHCP, four ICMP echoes to the gateway,
  and the run's log written to `tests/ETHNET.LOG` on the SD card and read
  back.
- `eth-tcp-server`: the same bring-up, then a TCP echo server on port 7. What
  a client sends is echoed, kept, and written to `tests/ETHRX.BIN` on the SD
  card and read back; the board prints the size and the CRC-32 of what it
  received. It needs a client: `eth-tcp-host.py`, next to the test.

`usb_big_test` is the DWC2 USB gadget on the USB-C port; its README
(`tests/platforms/aarch64-rpi4b/tests/usb_big_test/README.md`) has the host
tool.

```sh
cd <workspace>/micro-os-plus-iii/tests
C=aarch64-rpi4b-cmake-gcc-debug        # or aarch64-rpi4b-cmake-gcc-release
T=smp_mem_test                         # the test of your choice
```

## 3. First time for a configuration (in this order)

```sh
xpm run install   --config $C    # the pinned aarch64 GCC and QEMU -> build/$C/xpacks
xpm run link-deps --config $C    # the port and the device packages -> build/$C/xpacks
xpm run prepare   --config $C    # CMake configure; finds the test folders
```

- Debug and release are separate folders, so each needs all three steps.
- Never `rm -rf build/$C`: it holds the pinned toolchain and the cache with
  your `-D` settings.

## 4. Build

| Goal | Command |
|---|---|
| all images of the configuration | `xpm run build --config $C` |
| one image only | `PATH="$PWD/build/$C/xpacks/.bin:$PATH" cmake --build build/$C --target $T-hwd` (or `$T-qemu`) |
| list the test cases | `ctest --test-dir build/$C -N` |

After you add or rename a test folder, run `xpm run prepare --config $C` again.

## 5. Run

**One test on the board**, with the UART terminal open:

```sh
UOS_HW_ADAPTER_KHZ=15000 ctest --test-dir build/$C -R "^aarch64-rpi4b-$T-hwd\$" --output-on-failure
```

CTest first runs `aarch64-rpi4b-$T-hwd-reset` (the watchdog reset, then 10 s
for the firmware to boot), then the test. Build first: CTest does not build.

**One test in QEMU:**

```sh
ctest --test-dir build/$C -R "^aarch64-rpi4b-$T-qemu\$" --output-on-failure
```

**Sets:**

| Goal | Command |
|---|---|
| all QEMU tests (does not build) | `xpm run test --config $C` (= `ctest -V -LE hwd`) |
| all board tests, back to back | `UOS_HW_ADAPTER_KHZ=15000 ctest --test-dir build/$C -L hwd` |

## 5a. The Ethernet tests

`eth-net` runs like any other board test, with the Ethernet cable plugged in:

```sh
UOS_HW_ADAPTER_KHZ=15000 ctest --test-dir build/$C -R '^aarch64-rpi4b-eth-net-hwd$' -V
```

`eth-tcp-server` waits 60 s for a client after it prints
`[TEST] TCP server ready at <address>:7` on the UART. Start it, then run the
client from a second terminal with that address:

```sh
UOS_HW_ADAPTER_KHZ=15000 ctest --test-dir build/$C -R '^aarch64-rpi4b-eth-tcp-server-hwd$' -V

# second terminal, while the test waits (from the kernel's tests/)
platforms/aarch64-rpi4b/tests/eth-tcp-server/eth-tcp-host.py 192.168.1.191 --size 1048576
```

The client sends a pattern, checks that every byte comes back, and prints the
size and CRC-32 it sent; the board's `received <n> bytes, CRC-32 <crc>` line
must show the same two numbers. With `--serial <port>` instead of an address
the client reads the address and the board's CRC from the console itself; use
that only when no terminal is open on the port.

Options, given at configure time
(`xpm run prepare --config $C`, then `cmake -D NAME=value build/$C`):

| Option | Default | Meaning |
|---|---|---|
| `ETH_TEST_STATIC_IP` | empty (DHCP) | `a.b.c.d/len`: use this address instead of DHCP |
| `ETH_TEST_GATEWAY` | from DHCP | the gateway `eth-net` pings; required with a static address |
| `ETH_TEST_PEER` | empty | a second host for `eth-net` to ping |
| `ETH_TCP_WAIT_S` | `60` | seconds `eth-tcp-server` waits for a client |

When a test fails before the network is up, its `RESULT: FAIL (...)` line
says where it stopped: no controller or PHY, no link (with the PHY's status
registers for the gigabit attempt and for the 10/100 retry that follows after
7 s), or no DHCP lease (with the frame counters). Without a link the driver
also sends one frame to itself through the MAC and through the PHY and prints
`loopback self-test: MAC ok, PHY ok` on the UART, which separates a controller
fault from a cable fault.

## 6. Board settings

| Variable | Default | Meaning |
|---|---|---|
| `UOS_HW_ADAPTER_KHZ` | `4000` (the config's) | JTAG TCK after connect; `10000`–`15000` tested with the PIO probe firmware |
| `UOS_HW_ADAPTER_SERIAL` | — | which CMSIS-DAP, when several are connected |

What one `-hwd` run does (`tests/platforms/aarch64-rpi4b/CMakeLists.txt`,
`tests/cmake/uos-hwd.tcl`):

1. The reset fixture: resets the board through the BCM2711 watchdog, so no
   power cycle is needed between tests, and waits 10 s for the firmware.
2. Connects, then switches to `UOS_HW_ADAPTER_KHZ`.
3. Halts core 0, enables semihosting on all four cores and the board's
   HDE hook, loads the image at `0x80000` and starts core 0. The kernel
   releases cores 1–3.
4. The test's `RESULT: PASS|FAIL` over semihosting is the verdict; its
   semihosting exit ends OpenOCD.

The full console goes to the UART only (GPIO14/15, 115200 8N1). When it
connects, four `Failed to read memory at 0x80{4..7}10088` errors appear. They
are normal.

## 7. Clean

| Goal | Command |
|---|---|
| remove the build outputs (keeps toolchain and CMake cache) | `xpm run clean --config $C` |
| configure again | `xpm run prepare --config $C` |

**Results**

- **Pass:** `RESULT: PASS`, followed by `100% tests passed`.
- **Fail:** `RESULT: FAIL` or a timeout. Read the `ctest -V` output, then the UART.

Latest results (2026-11-20): all QEMU cases pass (the known flaky
`cmsis-os-validator` failed once and passed on rerun), and 22/22 on the board
through CTest/OpenOCD: 19 automatic tests plus `eth-net`,
`eth-tcp-server` and `usb_big_test`.

## 8. Earlier verification (2026-10/11, before the alignment)

> **History.** The runs below used the layout and commands of that time: the
> tests and board files in `micro-os-plus-iii-aarch64/test/`, the sibling
> folder layout, the per-test `xpm run test-<test>-hwd` actions and the board's
> `hw.sh`. They are kept as the record of what was verified then.

### First run: GitHub clone in `/tmp/rpi4b-verify`, 2026-10-13

The five repositories were cloned from `github.com/dan-maio` (branch `smp`) into `/tmp`, with no link to any other workspace.

| Command | Debug | Release |
|---|---|---|
| `xpm install --config $C` | ✅ | ✅ |
| `xpm run prepare --config $C` | ✅ | ✅ |
| one image (`cmake --build … --target $T-hwd`) | ✅ | ✅ |
| `xpm run build --config $C` | ✅ | ✅ |
| `ctest -N` (list) | ✅ | ✅ |
| `xpm run test --config $C` (all QEMU) | ✅ 16/16 passed, 212 s | ✅ 16/16 passed, 212 s |
| `xpm run test-$T-qemu --config $C` | ✅ | not run alone (passed within the 16/16) |
| `xpm run clean --config $C` | ✅ images removed | ✅ images removed |
| `xpm run build --config $C` after clean | ✅ | ✅ |
| `UOS_HW_ADAPTER_KHZ=15000 xpm run test-smp_test2-hwd --config $C` | ✅ `RESULT: PASS`, 14 s | — |
| `xpm run install --config $C`, as on GitHub | ❌ fails at the unused `xpm link` step (§3) | — |
| `xpm run install --config $C`, with the `xpm link` step removed from `aarch64-actions` (local edit in the `/tmp` clone only, not on GitHub) | ✅ | ✅ |

### Second run: unmodified GitHub clone (2026-10-13)

`/tmp/rpi4b-verify` was deleted and cloned again from GitHub, with no file changed. Only the commands of §1–§5 were used, with `xpm install --config $C` (not `xpm run install`):

| Command | Debug | Release |
|---|---|---|
| `npm install`, `xpm install` | ✅ | ✅ |
| `xpm install --config $C` | ✅ | ✅ |
| `xpm run prepare --config $C` | ✅ | ✅ |
| `xpm run build --config $C` | ✅ 32 images | ✅ 32 images |
| `xpm run test --config $C` (all QEMU) | ✅ 16/16 passed, 212 s | ✅ 16/16 passed, 211 s |
| `UOS_HW_ADAPTER_KHZ=15000 xpm run test-smp_test2-hwd --config $C` (board) | ✅ `RESULT: PASS`, 14 s | — |

Conclusion: the GitHub repositories install, build and test (QEMU and board) correctly as they are. The only failing command is `xpm run install`, because of its unused `xpm link` step (§3).

### Third run: clone from `~/Downloads/GIT` (2026-10-13)

The six repositories were cloned as in §1b into `/tmp/rpi4b-local`, with no file changed. That is the same commits as the golden workspace, all committed and pushed.

| Command | Debug | Release |
|---|---|---|
| without the devices clone: `xpm run prepare --config $C` | ❌ `Cannot find source file … drivers/src/sd.cpp` | ❌ same |
| `npm install`, `xpm install` | ✅ | ✅ |
| `xpm install --config $C` | ✅ | ✅ |
| `xpm run prepare --config $C` | ✅ | ✅ |
| `xpm run build --config $C` | ✅ 32 images | ✅ 32 images |
| `xpm run test --config $C` (all QEMU) | ✅ 16/16 passed, 212 s | ✅ 16/16 passed, 212 s |
| board `smp_test3-hwd`, 15 MHz (`ctest … -R aarch64-rpi4b-smp_test3-hwd`) | ✅ `RESULT: PASS`, 24 s | — |
| board `smp_test2-hwd`, 15 MHz (`xpm run test-smp_test2-hwd`) | ✅ `RESULT: PASS`, 14 s | — |

Conclusion: with the devices clone, the `~/Downloads/GIT` repositories install, build and test (QEMU and board) correctly as they are.

### Fourth run: the guide's own commands, verbatim (2026-10-13)

The `sh` blocks of this file were extracted unchanged and run as one script with `set -e`, in a new folder `/tmp/rpi4b-doc`. Only `W=` was set, and `T=smp_test2` before the board command. The script ran §1a, §2, §3, §4 `build`, §5 `test`, §5 `test-$T-qemu` and the §5 board command without rebuild.

| Step (debug) | Result |
|---|---|
| §1a: 5× `git clone`, `npm install`, `xpm install` | ✅ |
| §3: `xpm install --config $C`, `xpm run prepare --config $C` | ✅ |
| §4: `xpm run build --config $C` | ✅ |
| §5: `xpm run test --config $C` | ✅ 16/16 passed |
| §5: `xpm run test-smp_mem_test-qemu --config $C` | ✅ |
| §5: `ctest … -R aarch64-rpi4b-smp_test2-hwd`, 15 MHz | ✅ `RESULT: PASS`, 14 s |

Golden workspace: `smp_mem_inter_test-hwd` at 15 MHz passed in 525 s.

### Ethernet tests (2026-11-12, this workspace, debug configuration)

Built into the existing `build/aarch64-rpi4b-cmake-gcc-debug` tree (`cmake --build` of the four
`eth-*` targets) and run with `ctest -R`, the board on a home router with DHCP.

| Case | Result |
|---|---|
| `aarch64-rpi4b-eth-net-hwd` | ✅ `RESULT: PASS (link, address, gateway ping, log on the SD card)`, 12 s |
| `aarch64-rpi4b-eth-tcp-server-hwd` | ✅ `RESULT: PASS (client served, stream on the SD card)`, 14 s; 1 MiB from `eth-tcp-host.py`, echo identical, about 200 Mbit/s each way |
| `aarch64-rpi4b-eth-net-qemu`, `aarch64-rpi4b-eth-tcp-server-qemu` | ✅ `RESULT: SKIP`, passed |
| loopback self-test (cable not linked) | ✅ `MAC ok, PHY ok` |

Not verified: the release configuration, a static address, the `xpm run test-eth-*` actions
(the cases were run with `ctest` directly), and the client's `--serial` mode.

### What was not verified

- `xpm run test-hwd` (all 16 board tests back to back); only single board tests were run.
- A PC without OpenOCD in `~/.local/xPacks`. This PC already had it, so §0's `xpm install -g` line was checked only as a no-op ("already installed").
- `xpm run install` on a PC with **no** global `micro-os-plus-iii-aarch64` link. It is expected to fail too (nothing to link), which is why §3 uses `xpm install --config $C`.
