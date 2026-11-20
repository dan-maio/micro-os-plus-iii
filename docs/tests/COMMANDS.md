# µOS++ III SMP — the commands, from the workspace to every test run

> For the complete guide to running all tests, one architecture, one board or
> one selected case, see [`RUNNING-TESTS.md`](RUNNING-TESTS.md).

How to install, build and run every test of µOS++ IIIe SMP, after the
alignment with upstream (2026-11). Every test lives in the kernel's
`tests/`: the portable ones in `tests/sources/`, the board-only ones and the
board code in `tests/platforms/<platform>/`. CTest runs everything: QEMU and
the host directly, the boards through OpenOCD. No shell script is involved.
How the tests are organised: [`TESTS-DEVELOPER-GUIDE.md`](TESTS-DEVELOPER-GUIDE.md);
what each test does: [`TESTS-CATALOG.md`](TESTS-CATALOG.md).

## 1. The workspace

One folder holds the kernel and, grouped by architecture, the ports and the
device packages. Each is its own git repository and xPack:

```text
<workspace>/
├── micro-os-plus-iii/                 the kernel; all the tests in tests/
├── aarch32/  micro-os-plus-iii-aarch32,  micro-os-plus-iii-devices-rk3506
├── aarch64/  micro-os-plus-iii-aarch64
├── cortexm/  micro-os-plus-iii-cortexm,  micro-os-plus-iii-devices-rp2xxx,
│             micro-os-plus-iii-devices-stm32f4
├── posix-arch/ micro-os-plus-iii-posix-arch
└── common/   micro-os-plus-iii-devices-bcm283x, micro-os-plus-iii-devices-storage
```

The AArch and Cortex-M ports carry no tests (their `test/` holds only
`.gitkeep`, as upstream's Cortex-M port); `posix-arch` keeps upstream's two
`trace-*` programs. The device packages carry the chips' drivers.

## 2. Install once

Register every local package with xpm, so the tests can link it (run in
each package's folder):

```bash
cd <workspace>
for p in aarch32/micro-os-plus-iii-aarch32 aarch32/micro-os-plus-iii-devices-rk3506 \
         aarch64/micro-os-plus-iii-aarch64 \
         cortexm/micro-os-plus-iii-cortexm cortexm/micro-os-plus-iii-devices-rp2xxx \
         cortexm/micro-os-plus-iii-devices-stm32f4 \
         posix-arch/micro-os-plus-iii-posix-arch \
         common/micro-os-plus-iii-devices-bcm283x common/micro-os-plus-iii-devices-storage; do
  (cd $p && xpm link)
done
```

Then install the tests' dependencies and toolchains, and link the local
packages into every configuration:

```bash
cd <workspace>/micro-os-plus-iii/tests
xpm run install-all          # npm install; xpm install --all-configs
xpm run link-deps-all        # the global links, then each configuration's port
                             # and device packages
```

One configuration alone:

```bash
xpm run install   --config <configuration>
xpm run link-deps --config <configuration>
```

A configuration is named `<platform>-cmake-<toolchain>-<debug|release>`, for
example `aarch64-rpi4b-cmake-gcc-debug` or `native-cmake-sys-release`. Its
build folder is `tests/build/<configuration>/`. Never delete a build folder's
`CMakeCache.txt` by hand: it holds the `-D` settings you gave it (the Wi-Fi
credentials of the Wi-Fi tests, for example).

## 3. Build and run one configuration

```bash
cd <workspace>/micro-os-plus-iii/tests
xpm run prepare --config <configuration>     # CMake configure
xpm run build   --config <configuration>     # build every test image
xpm run test    --config <configuration>     # the tests that need no board
```

`test` runs `ctest -V` in the build folder; on the configurations that also
have hardware tests it runs `ctest -V -LE hwd`, so the board tests are
built but not run. Every test is a CTest case named
`<platform>-<test>-<variant>`:

| Variant | Label | What runs it |
|---|---|---|
| `-host` | `host` | the native test program on the PC (POSIX port) |
| `-qemu` | `qemu` | QEMU, with semihosting |
| `-hwd` | `hwd` | the board, through OpenOCD (section 5) |
| `-hwd` manual | `hwd-manual` | the board, by hand (PSRAM 200/250 MHz clock tests) |

Board configurations also provide a `test-hwd` action (`ctest -V -L hwd`).
On a mixed board, `test` runs the QEMU cases and `test-hwd` runs the board
cases; on a hardware-only board, `test` already runs the automatic board set.

The verdict is the test's own `RESULT: PASS` / `FAIL` / `SKIP` line (CTest's
regular expressions), and each test has a time limit. In a built
configuration:

```bash
cd build/<configuration>
ctest -N                                   # list the tests
ctest -R '^<test name>$' --output-on-failure   # one test
ctest -L qemu                              # all the QEMU tests
```

After a change that failed to build, delete the test's image before running
it again: CTest otherwise runs the previous image.

## 4. The groups of configurations

Every group action runs `prepare`, `build` and `test` for the `-debug` and
then the `-release` configuration of each member.

| Action | Configurations |
|---|---|
| `xpm run test-native-cmake-sys` | the POSIX host with the system compiler |
| `xpm run test-native-cmake` | the POSIX host with xPack GCC 11–14 and clang 16–19 (`test-native-cmake-gcc14`, `-clang19`, … one by one) |
| `xpm run test-cortex-cmake` | QEMU Cortex-M0, M3, M4F, M7F (`test-qemu-cortex-m7f-cmake`, …) |
| `xpm run test-smp-cmake` | the SMP QEMU configurations: AArch32 and AArch64 Pi Zero 2 W and Pi 3 B, the dual Cortex-M33, the single-CPU Pico 2, the Pico 2 and its PSRAM board (not the Pi 4 B) |
| `xpm run test-aarch64-rpi4b-cmake`, `test-cortexm-pico-cmake` | one board's QEMU tests |
| `xpm run test-all` | the native, Cortex-M and SMP groups above; not every platform |

The Luckfox Lyra (`aarch32-luckfox-lyra-*`), the Pico 2 Pi Zero, the Nucleo
F411 and the WeAct F411 and F412 have hardware tests only. Their `test`
action runs the unattended board set; on the Lyra and Pi-Zero it skips the
PC-driven cases, and `test-hwd` runs every hardware case (section 5).

## 5. On the board (`hwd`)

A hardware test is a CTest case too. CTest runs OpenOCD with the board's
configuration (`tests/platforms/<platform>/`); OpenOCD loads the image, the
test runs, and its semihosting `SYS_EXIT` ends OpenOCD. The `RESULT` line is
the verdict, as for QEMU. The board's UART is never opened: watch it in your
own terminal (`tio`), preferably by its fixed name in `/dev/serial/by-id/`
(the `ttyACM` numbers change with every replug).

```bash
cd build/<configuration>
ctest -L hwd                                       # every hardware test, one after another
ctest -R '^aarch64-rpi4b-smp_test0-hwd$' --output-on-failure   # one
ctest -L hwd -E '(usb_big_test|eth-net|eth-tcp-server)-hwd$'   # without some
ctest -R '^cortexm-pico2-rp2350b-psram-smp-test-nested-clock_200-hwd$'  # manual
```

`-L hwd` skips cases labelled `hwd-manual`: the PSRAM 200/250 MHz clock
tests need the potentiometer and a `y` on the UART, and their reboot drops
the debug/semihosting state, so their verdict is read on the UART rather
than by CTest.

Before a test, a board without a reset line is reset through its debug port
in a separate OpenOCD session: the Pi's PM watchdog, then a few seconds for
the firmware to boot; the RK3506 global reset on the Lyra. That session is a
CTest fixture (`<test>-hwd-reset`, label `hwd-reset`) that CTest adds by
itself; if it does not reach the board, the test is not run.

What a run reads from the environment:

| Variable | What for |
|---|---|
| `PROBE` | the Pi Zero 2 W and Pi 3 B probe: `jlink` (default), `olimex`, `cmsis-dap` |
| `UOS_HW_ADAPTER_SERIAL` | which CMSIS-DAP probe, by serial number, when several are connected |
| `UOS_HW_ADAPTER_KHZ` | the JTAG/SWD clock (slower for long wires) |

The probes and the boards, as used on the bench:

| Platform | Probe | Notes |
|---|---|---|
| `aarch64-rpi4b` | CMSIS-DAP ("JTAG probe on Pico") | slow image load; Ethernet tests need the cable, `usb_big_test` the USB-C port |
| `aarch32-/aarch64-rpi-zero-2w`, `-rpi3b` | `PROBE=cmsis-dap`, `olimex` or J-Link | the SD card must boot the port's width (`arm_64bit=0`/`1`) |
| `aarch32-luckfox-lyra` | WCH-Link (CMSIS-DAP) | run it alone, not beside another CMSIS-DAP board; its USB tests use the USB1 port |
| `cortexm-pico`, `cortexm-pico2` | Raspberry Pi Debug Probe | the `-ram` variants load to RAM |
| `cortexm-pico2-pizero` | XV-Link CMSIS-DAP | |
| `cortexm-pico2-rp2350b-psram` | generic CMSIS-DAP (`c251:f001`) | when neither core can be examined, rescue-reset it: `openocd -c "set RESCUE 1" -f openocd.cfg -c init -c shutdown` |
| `cortexm-nucleof411`, `-weactf411`, `-weactf412` | ST-LINK / WCH-Link | the F412's console is USART1 (PA9/PA10), not the ST-LINK's port |

Some tests need the PC's side during the run: the USB gadget tests
(`usb_test`, `usb_big_test`, `smp-test-usb-cdc-acm`, `smp-test-usb-hid`,
the Lyra's `smp_test7`, `smp_test_int3`, `smp_test_int4`) and the network
tests (`eth-tcp-server`, `wifi-tcp-server`). Each test folder's README says
which host tool to run and when; the tests that need nothing from the PC run
unattended. Several interactive Pico 2 PSRAM tests (`smp-test-nested-clock*`)
reboot into a clock chosen with a potentiometer and are run by hand from
flash.

The former `<test>-hwsh` twins and the boards' `hw.sh` scripts were removed
after the OpenOCD route was proven on hardware; the `-hwd` case is the only
way a test runs on a board.

## 6. Results

The hardware and QEMU results of each round are in the workspace's
`hw-check/<date>/RESULTS.md` and `step*-check/` folders; the known flaky
tests are in `baseline-2026-11-17/BASELINE.md`.
