# µOS++ IIIe test framework — developer guide

How to **configure**, **run** and **write** tests in the xPack/xpm test
framework of `micro-os-plus-iii` (the SMP fork, aligned with upstream in
2026-11).

The framework is upstream's: every command is an `xpm run <action>` in the
kernel's `tests/` folder, CMake builds, CTest runs. Every test lives in that
folder. The portable ones are in `tests/sources/`, the board facts, board
code and board-only tests in `tests/platforms/<platform>/`. The AArch and
Cortex-M ports carry no test projects (`posix-arch` keeps upstream's two
`trace-*` programs), and the device packages carry no tests. The command
reference is
[`COMMANDS.md`](COMMANDS.md); what each test does is in
[`TESTS-CATALOG.md`](TESTS-CATALOG.md).

Every statement in this guide was checked against the files it names. When
another document disagrees, the files win.

---

## Contents

1. [Vocabulary](#1-vocabulary)
2. [The workspace](#2-the-workspace)
3. [Architecture in one picture](#3-architecture-in-one-picture)
4. [Layer 1 — `tests/package.json`](#4-layer-1--testspackagejson)
5. [Layer 2 — the CMake tree and the platforms](#5-layer-2--the-cmake-tree-and-the-platforms)
6. [Layer 3 — the board tests' builder](#6-layer-3--the-board-tests-builder)
7. [Layer 4 — CTest: names, labels, verdicts, runs](#7-layer-4--ctest-names-labels-verdicts-runs)
8. [Writing a new test](#8-writing-a-new-test)
9. [Adding a configuration or a platform](#9-adding-a-configuration-or-a-platform)
10. [Checklist before you commit](#10-checklist-before-you-commit)
11. [Troubleshooting](#11-troubleshooting)
12. [Reference tables](#12-reference-tables)

---

## 1. Vocabulary

| term | meaning |
|---|---|
| **configuration** | one entry of `xpack.buildConfigurations` in `tests/package.json`, e.g. `cortexm-pico2-cmake-gcc-debug`; it owns the build folder `tests/build/<configuration>/` |
| **platform** | the value of `PLATFORM_NAME`, e.g. `cortexm-pico2`: one folder under `tests/platforms/`, shared by the debug and release configurations |
| **port** | an architecture package: `micro-os-plus-iii-{aarch32,aarch64,cortexm,posix-arch}` |
| **device package** | the chips' drivers: `micro-os-plus-iii-devices-{bcm283x,rk3506,rp2xxx,stm32f4,storage}` |
| **suite** | upstream's portable test library in `tests/sources/<suite>/` (`mutex-stress`, `rtos-apis`, `cmsis-os-validator`): `test::<suite>`, its own `os_main()` |
| **portable test** | a test in `tests/sources/<test>/` with `os_main()` only (`smp_test0`, `smp-mat-test`, `sd_test`, …): the platform starts it up and ends it |
| **board test** | a test only one board runs: `tests/platforms/<platform>/tests/<test>/`, with its own start-up when it needs one |
| **variant** | how an image runs: `-qemu` (emulator), `-host` (a native program), `-hwd` (the board, through OpenOCD) |

---

## 2. The workspace

The kernel and its packages are separate git repositories and xPacks, in one
folder, grouped by architecture:

```text
<workspace>/
├── micro-os-plus-iii/                the kernel; tests/ is the test project
├── aarch32/   micro-os-plus-iii-aarch32,  micro-os-plus-iii-devices-rk3506
├── aarch64/   micro-os-plus-iii-aarch64
├── cortexm/   micro-os-plus-iii-cortexm,  micro-os-plus-iii-devices-rp2xxx,
│              micro-os-plus-iii-devices-stm32f4
├── posix-arch/ micro-os-plus-iii-posix-arch
└── common/    micro-os-plus-iii-devices-bcm283x, micro-os-plus-iii-devices-storage
```

The tests reach the packages the xPack way, not by relative paths: each
package is registered once with `xpm link` (in its folder), and
`xpm run link-deps --config <configuration>` links the ones a configuration
needs into `tests/build/<configuration>/xpacks/@micro-os-plus/`. A platform
names them in its `cmake/dependencies-folders.cmake`; when one is not linked
the configure stops with "`<package>` is not linked into this build folder".

Everything else — CMake, Ninja, the host GCC/clang versions,
`arm-none-eabi-gcc`, `aarch64-none-elf-gcc`, `qemu-arm`, `openocd` — is
pinned per configuration and installed by xpm. The QEMU and OpenOCD tests
use the configuration's `build/<configuration>/xpacks/.bin` copy, which xpm
puts first on `PATH` during configure; if the configuration has none, the
one on `PATH` is used.

The install commands are in [`COMMANDS.md`](COMMANDS.md) §2.

---

## 3. Architecture in one picture

```text
 xpm run build --config aarch64-rpi4b-cmake-gcc-debug
   │
   │ LAYER 1  tests/package.json
   │          configuration -> toolchain, build type, PLATFORM_NAME
   ▼
 cmake -S tests -B build/<C> -G Ninja -D PLATFORM_NAME=aarch64-rpi4b ...
   │
   │ LAYER 2  tests/CMakeLists.txt -> cmake/tests-main.cmake
   │          -> platforms/<platform>/cmake/*.cmake (definitions, the linked
   │             packages, the board facts, micro-os-plus::platform)
   │          -> platforms/<platform>/CMakeLists.txt
   ▼
 add_subdirectory (board-tests)        the board tests' builder
   │
   │ LAYER 3  board-tests/CMakeLists.txt + platforms/<P>/tests/tests.cmake
   │          one image per test and variant: <test>-qemu, -hwd, -host
   ▼
 ctest -R '^aarch64-rpi4b-smp_test0-qemu$'
   │
   │ LAYER 4  the platform registers each image (cmake/uos-tests-run.cmake):
   │          QEMU, the host program, or OpenOCD, started by CTest itself
   ▼
 PASS / FAIL / SKIP (the RESULT line) or TIMEOUT
```

Two rules hold it together: **only `package.json` passes `PLATFORM_NAME`,
the build type and the toolchain file**; and **only the platform folder
creates CTest cases**. There is no shell script anywhere in the chain.

---

## 4. Layer 1 — `tests/package.json`

### 4.1 Properties and mixins

Properties are Liquid templates xpm expands before an action runs; the
global ones build every CMake command (`commandCMakePrepareWithToolchain`,
`commandCMakeBuild`, `commandCMakePerformTests`). A configuration supplies
`buildType`, `platformName`, `toolchainFileName` and (for short Windows
paths) `shortConfigurationName`.

A configuration with `"hidden": true` is a mixin, inherited by the others:

| mixin | provides |
|---|---|
| `cmake-actions` | `prepare`, `build`, `test`, `clean` |
| `native-actions`, `cortexm-actions`, `aarch32-actions`, `aarch64-actions` | `install` and `link-deps` (the port and device packages that family links) |
| `gccNN-dependencies`, `clangNN-dependencies`, `arm-none-eabi-gcc-dependencies`, `aarch32-dependencies`, `aarch64-dependencies` | the pinned compilers |
| `qemu-arm-dependencies`, `openocd-dependencies` | emulator and probe tools |
| `clang-gcc14-properties` | clang 16–18 against the xPack GCC 14 libstdc++ |
| `short-win-paths-properties` | `build/<shortConfigurationName>` on Windows |

### 4.2 A configuration

Name pattern: **`<platform>-cmake-<toolchain>-<debug|release>`**.

```json
"aarch64-rpi4b-cmake-gcc-debug": {
  "inherit": ["aarch64-actions", "cmake-actions", "aarch64-dependencies",
              "short-win-paths-properties"],
  "properties": {
    "buildType": "Debug",
    "platformName": "aarch64-rpi4b",
    "toolchainFileName": "aarch64-none-elf-gcc.cmake",
    "shortConfigurationName": "a64p4d"
  },
  "actions": {
    "test": "cd {{ properties.buildFolderRelativePath }} && ctest -V -LE \"hwd\""
  }
}
```

The release configuration inherits the debug one and changes only
`buildType` (`MinSizeRel` on the boards, `Release` on native); it has its
own build folder, so it needs its own `install` and `link-deps`. A local
action replaces an inherited one of the same name: that is how `test`
excludes the hardware tests on the configurations that have them.

### 4.3 The actions

| kind | actions |
|---|---|
| per configuration | `install`, `link-deps`, `prepare`, `build`, `test`, `clean` |
| groups (no `--config`) | `test-native-cmake[-<compiler>]`, `test-cortex-cmake`, `test-qemu-cortex-m*-cmake`, `test-smp-cmake`, `test-<platform>-cmake`, `test-all`, `build-aarch32-luckfox-lyra-cmake` |
| housekeeping | `install-all`, `link-deps-all`, `clean-all`, `deep-clean`, `git-*-deps` |

There are no per-test actions: one test is one CTest case, selected with
`ctest -R` in the build folder (§7). A group action stops at the first
failing configuration; an array action takes no extra arguments.

---

## 5. Layer 2 — the CMake tree and the platforms

```text
tests/
├── CMakeLists.txt              project, C11/C++20, enable_testing(), build helper
├── cmake/
│   ├── tests-main.cmake        the platform's cmake/*.cmake, the linked packages
│   │                           (and their UOS_<PACKAGE>_DIR), the kernel, the platform
│   ├── common-options.cmake    warnings and options for every target
│   ├── uos-aarch-board.cmake   micro-os-plus::board of an AArch platform
│   ├── uos-cortexm-board.cmake micro-os-plus::board of a Cortex-M platform
│   ├── uos-tests-run.cmake     how CTest runs a test: QEMU, host, OpenOCD (§7)
│   ├── uos-hwd.tcl             the AArch hardware run, in OpenOCD (§7.4)
│   └── uos-hwd-reset.cmake     the reset that drops the debug link (§7.4)
├── board-tests/                the board tests' builder (§6) and what every
│                               board shares (the start-up end, the SD mount)
├── sources/<test>/             suites and portable tests
├── platforms/<platform>/       one folder per PLATFORM_NAME
├── device-qemu-cortexm/         the generic QEMU Cortex-M device (upstream platforms)
├── third_party/lwip/           lwIP 2.2.1, for the network tests
└── package.json                Layer 1
```

### 5.1 A platform folder

```text
tests/platforms/<platform>/
├── CMakeLists.txt                the tests this platform builds and registers
├── cmake/
│   ├── definitions.cmake         xpack_platform_compile_definition, BOARD
│   ├── dependencies-folders.cmake the suites and linked packages it needs
│   ├── board.cmake               the board facts (flags, CPU count, linker
│   │                             scripts, defines, the SD driver set)
│   └── platform-library.cmake    micro-os-plus::platform and micro-os-plus::board
├── include/, src/                the board's code (console, SMP boot, MMU,
│                                 platform.h, the suites' support files)
├── device/linker-scripts/        the hardware and QEMU linker scripts
├── openocd*.cfg                  the probe and the target
└── tests/                        the board-only tests (§6)
    ├── tests.cmake               the per-test knobs
    ├── include/, src/            what the board's tests share
    └── <test>/                   one folder per test
```

Some boards add their own folders: `net/` (Pi 4 B Ethernet), `wifi/` (Zero
2 W), `usb/`, `qemu/`, `glue/` (Pico 2). The Pi 3 B platforms reuse the Zero
2 W's board code (same SoC).

`dependencies-folders.cmake` is per platform: a suite or package it does not
list does not exist on that platform, and the configure fails.

### 5.2 The two shapes of a platform `CMakeLists.txt`

**(a) The board platforms** (`aarch32-*`, `aarch64-*`, `cortexm-*`,
`native`) say what to build and hand it to the builder, then register every
image it built:

```cmake
include ("cmake/platform-library.cmake")
include ("${CMAKE_SOURCE_DIR}/cmake/uos-tests-run.cmake")

set (UOS_TESTS_PORT aarch64)
set (UOS_TESTS_SOURCES  smp_test0 ... sd_test clock-test)   # from tests/sources/
set (UOS_TESTS_PORTABLE smp_test0 ... sd_test clock-test)   # os_main() only
set (UOS_TESTS_STORAGE  sd_test smp-mat-sdcard-test ...)    # get /sd/ mounted
set (UOS_TESTS_SUITES   mutex-stress rtos-apis cmsis-os-validator)
set (UOS_TESTS_BOARD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/tests")
add_subdirectory ("${CMAKE_SOURCE_DIR}/board-tests" "port-tests/test")

foreach (_app IN LISTS UOS_TESTS_APPS)       # handed back by the builder
  uos_tests_add_qemu (NAME "${PLATFORM_NAME}-${_app}-qemu" APP "${_app}"
                      IMAGE ".../${_app}-qemu.bin" QEMU "${_qemu}"
                      MACHINE -M raspi4b -smp 4)
  uos_tests_add_hwd  (NAME "${PLATFORM_NAME}-${_app}-hwd" APP "${_app}"
                      ELF "$<TARGET_FILE:${_app}-hwd>" CFG ... ENTRY ...)
endforeach ()
```

Adding a board test therefore needs no edit here: a new folder in
`tests/` and a re-`prepare` are enough.

| platform family | `-qemu` | `-host` | `-hwd` |
|---|---|---|---|
| `aarch32-rpi*`, `aarch64-rpi*` | `raspi3b` / `raspi4b`, `-smp 4` (AArch32 through a boot shim) | — | `uos_tests_add_hwd` (§7.4) |
| `aarch32-luckfox-lyra` | — (hardware only) | — | `uos_tests_add_hwd` |
| `cortexm-pico`, `cortexm-pico2`, `-pico2-rp2350b-psram` | the tests the board can run emulated, on a generic Cortex-M | — | `uos_tests_add_openocd` |
| `cortexm-pico2-pizero`, `-nucleof411`, `-weactf411`, `-weactf412` | — | — | `uos_tests_add_openocd` |
| `native` | — | `uos_tests_add_host` | — |

**(b) The upstream platforms** (`qemu-cortex-m*`, `pico2-1cpu`,
`2xcortex-m33`, `nucleo-*`, `raspberrypi-pico`) build upstream's suites
themselves, as upstream does:

```cmake
add_executable (rtos-apis-test)
target_link_libraries (rtos-apis-test PRIVATE micro-os-plus::common-options
  test::rtos-apis micro-os-plus::iii micro-os-plus::platform xpacks::chan-fatfs)
add_test (NAME "${PLATFORM_NAME}-rtos-apis-test" COMMAND "${_qemu}" ... )
```

---

## 6. Layer 3 — the board tests' builder

`tests/board-tests/CMakeLists.txt` is one builder for every port (it was
each port's own `test/CMakeLists.txt`). It reads what the platform set
(§5.2a) and the board facts, and builds:

- **the board tests** — every folder of `UOS_TESTS_BOARD_DIR` holding a
  `*.cpp` (the folder name is the test name), each with the board's shared
  `tests/src/*.cpp`;
- **the portable tests** (`UOS_TESTS_SOURCES`) — one copy in
  `tests/sources/<test>/` for every board. Those in `UOS_TESTS_PORTABLE` get
  the platform's start-up (`src/platform-support.cpp`: board bring-up, the
  secondary cores, then `os_main()`) and the common end
  (`board-tests/portable-test-end.cpp`, or `board-tests/cortexm/test-end.cpp`
  on Cortex-M): it prints `RESULT: PASS|FAIL` from `os_main()`'s return
  value and ends the run;
- **the suites** (`UOS_TESTS_SUITES`) — from their `test::<suite>`
  libraries, on the platform's start-up, with what upstream's platforms link
  them with (`rtos-apis`: Chan FatFs; `cmsis-os-validator`: the Arm
  validator) and the platform's `src/<suite>-support.cpp` when there is one;
- **the storage** of the tests in `UOS_TESTS_STORAGE` — the board's SD card
  as the posix-io block device `/dev/sd`, Chan FatFs, mounted at `/sd/`
  before `os_main()` (`board-tests/portable-test-storage.cpp`; a board test
  calls `uos_test_storage_start()` from `uos-test-storage.h` itself).

Each test becomes one image per variant: `-qemu` and `-hwd` when the board
has a QEMU linker script, `-hwd` only when it has not, `-host` on the POSIX
port. The builder hands the names back in `UOS_TESTS_APPS`.

### 6.1 `tests.cmake` — the per-test knobs

`tests/platforms/<P>/tests/tests.cmake` changes what the defaults do, per
test. Each knob is a function `(<test> <out-variable>)`:

| knob | for |
|---|---|
| `board_test_defines` | per-test `-D` (e.g. `usb_test`'s LED pattern) |
| `board_test_sources`, `board_test_includes` | extra sources and include folders |
| `board_test_libs` | extra libraries (a driver set, `aarch64-rpi4b-eth`, `micro-os-plus::devices-usb`) |
| `board_test_linker`, `board_test_options` | a test's own linker script or options |
| `board_test_ncpu` | a CPU count other than the board's |
| `board_test_sd_posix` | the card's driver set of a storage test (`OWN`: the test brings its own) |
| `board_test_qemu_libs`, `_sources`, `_includes` | what replaces the board in the emulated image (the RP2xxx boards) |

and the lists `BOARD_TEST_SELF_CONTAINED` (brings its own start-up),
`BOARD_TEST_NO_KERNEL` (no scheduler), `BOARD_TEST_HWD_ONLY` (no QEMU
image), plus additions to `UOS_TESTS_STORAGE`.

### 6.2 Cache options

| variable | meaning |
|---|---|
| `UOS_DEBUG_BOOT` | compile the `-hwd` images with the early-boot markers (each one a semihosting trap) |
| `SEMI_PRINTS` | AArch64: mirror every console line to semihosting in the `-hwd` images (keep 0 for the USB tests) |
| `LED_PIN` | the GPIO used as the user LED (per board) |
| `WIFI_TEST_SSID`, `WIFI_TEST_PASS` | the Wi-Fi tests' network; kept in the build folder's `CMakeCache.txt`, never committed |

---

## 7. Layer 4 — CTest: names, labels, verdicts, runs

### 7.1 Names and labels

| platform shape | CTest name | label |
|---|---|---|
| board platforms | `<platform>-<test>-qemu` / `-hwd` / `-host` | `qemu` / `hwd` / `host` |
| board platforms, by-hand case | `<platform>-<test>-hwd` | `hwd-manual` (excluded from `-L hwd`) |
| upstream platforms | `<platform>-<suite>-test` | `qemu` |
| the debug-link reset before a hardware test | `<platform>-<test>-hwd-reset` | `hwd-reset` |
| a per-run SD image (QEMU, host) | `<name>-sd-make`, `<name>-sd-remove` | as the test |

`ctest -R` is a regular-expression **substring** match: anchor the full name
(`-R '^cortexm-pico2-smp-test1-qemu$'`). The configuration's `test` action
excludes the hardware label (`ctest -LE hwd`).

The PSRAM `smp-test-nested-clock_200` and `_250` cases are labelled
`hwd-manual`: they need the potentiometer and `y` on the UART, and their
clock reboot clears the debug/semihosting state, so CTest cannot read their
verdict. Run them explicitly with `ctest -R` and read `RESULT` on the UART.

### 7.2 The verdict

Every test prints one line: `RESULT: PASS`, `RESULT: FAIL` or
`RESULT: SKIP` (e.g. `usb_test` under QEMU, which has no USB device mode).
CTest's `PASS/FAIL/SKIP_REGULAR_EXPRESSION` read it
(`UOS_TESTS_RESULT_PROPERTIES`); with a pass expression set, the exit code
does not decide. Each test has a time limit (`uos_tests_timeout()`: 300 s
unless listed — `smp_test0/1/3/4` 150, `smp-mat-test` 900,
`smp-num/pipeline/pro-cons` 1000, `smp-mat-sdcard-test` 2000, `sd_test` 450,
`usb_test` 200; the hardware tests set their own).

A test must also **end the run** after its line, or it ends in a timeout:

- portable tests and suites return from `os_main()`; the common end prints
  the line and ends;
- Cortex-M board tests call `hw_result::ok()` / `fail()`
  (`board-tests/cortexm/hw_result.hpp`): the line through semihosting, then
  `_Exit()`, a semihosting `SYS_EXIT`;
- AArch board tests print the line through their console and semihosting and
  end through semihosting the same way.

On QEMU and on a board, the semihosting exit ends QEMU or OpenOCD.

### 7.3 QEMU and host runs

`uos_tests_add_qemu` runs QEMU with semihosting and the image
(`-kernel`; on AArch32 Pis, a shim that drops `raspi3b`'s AArch64 cores to
AArch32 and a `-device loader` for the image). `uos_tests_add_host` runs the
native program. A test that uses the SD card gets a fresh 4 GiB card image
(MBR + FAT32, `board-tests/sd-image.py`; `sd_test`'s with a seed file) from a
CTest fixture, deleted after the run.

### 7.4 Hardware runs

CTest runs OpenOCD directly with the board's configuration. No GDB, no
script; the test's semihosting `SYS_EXIT` ends OpenOCD.

- **AArch boards** (`uos_tests_add_hwd`): `cmake/uos-hwd.tcl` halts the
  cores, enables semihosting, runs the board's hooks, an optional pre-load,
  loads the image and resumes in the board's mode (`entry`, `cpsr`,
  `pc-first`, `cpsr-first`, `pc`). These boards have no reset line: before
  each test, `cmake/uos-hwd-reset.cmake` resets them in its own OpenOCD
  session (the Pi's PM watchdog, the RK3506 global reset), waits for them to
  boot, and runs as a CTest fixture (`<test>-hwd-reset`); if it cannot reach
  the board, the test is not run.
- **Cortex-M boards** (`uos_tests_add_openocd`): the board's commands, from
  its `CMakeLists.txt`: program the flash, reset, enable semihosting, run;
  the `-ram` tests load into SRAM and start core 0 from the image's vector
  table.

The environment: `PROBE` (Zero 2 W / Pi 3 B probe: `jlink`, `olimex`,
`cmsis-dap`), `UOS_HW_ADAPTER_SERIAL` (which CMSIS-DAP), `UOS_HW_ADAPTER_KHZ`
(the clock). The board's UART is never opened by a test run: it is yours, in
your own terminal. Hardware tests run one at a time (`RUN_SERIAL`); two
boards on different probes can run side by side from two build folders
(OpenOCD's Tcl and telnet ports are off), except the Lyra, whose WCH-Link
loses its link beside another CMSIS-DAP probe.

The OpenOCD route has been proven on the boards and is the only hardware
route; the former `<test>-hwsh` twins and the boards' `hw.sh` scripts have
been removed.

---

## 8. Writing a new test

### 8.1 Which kind?

| the test… | it is a… | lives in |
|---|---|---|
| checks kernel behaviour on every architecture, `os_main()` only | **portable test** | `tests/sources/<test>/main.cpp` |
| is one of upstream's suites, or a new one in their shape | **suite** | `tests/sources/<suite>/` (an INTERFACE library `test::<suite>`) |
| needs one board, a driver, an SMP boot detail | **board test** | `tests/platforms/<P>/tests/<test>/` |

### 8.2 A portable test

1. Create `tests/sources/<test>/main.cpp` with `int os_main (int, char*[])`,
   returning 0 for a pass; use the µOS++ interfaces only (start from
   `smp_test0/`). No `main()`, no board headers.
2. Add it to `UOS_TESTS_SOURCES` and `UOS_TESTS_PORTABLE` of every platform
   that should run it (and to `UOS_TESTS_STORAGE` if it needs `/sd/`).
3. If it needs more than 300 s, add it to `uos_tests_timeout()`.
4. `prepare`, `build`, run it with `ctest -R` (§7.1).

### 8.3 A board test

1. Create `tests/platforms/<P>/tests/<test>/main.cpp`, starting from the
   closest sibling; the folder name is the test name.
2. End with a verdict that stops the run (§7.2): on Cortex-M,

   ```cpp
   #include <hw_result.hpp>
   // ...
   if (ok)
     hw_result::ok ();      // RESULT: PASS through semihosting, then SYS_EXIT
   else
     hw_result::fail ();
   ```

3. If it needs anything special, say so in `tests/tests.cmake` (§6.1). Most
   tests need nothing.
4. Re-`prepare` (the folder glob runs at configure time) and check:
   `ctest -N | grep <test>`.
5. Build, run `-qemu` if the board has one, then `-hwd` on the board.

### 8.4 A suite

Copy `tests/sources/mutex-stress/` (its `CMakeLists.txt` defines
`test-<name>-interface` and the alias `test::<name>`, its
`include/cmsis-plus/os-app-config.h` the RTOS configuration, `src/main.cpp`
the `os_main()`). Then add the folder to each platform's
`cmake/dependencies-folders.cmake`, and the name to `UOS_TESTS_SUITES` (board
platforms) or an `add_executable` + `add_test` (upstream platforms).

---

## 9. Adding a configuration or a platform

### 9.1 A new toolchain or build type

1. Copy the nearest debug + release pair in `xpack.buildConfigurations`,
   named `<platform>-cmake-<toolchain>-<debug|release>`.
2. Change the dependency mixin, `toolchainFileName` and a unique
   `shortConfigurationName`; keep the sibling's `test` action.
3. Add it to the relevant group action.
4. `xpm run install --config <new>`, `link-deps`, `prepare`, `build`, `test`.

### 9.2 A new board

1. Copy the nearest sibling folder under `tests/platforms/` and adapt
   `cmake/definitions.cmake`, `dependencies-folders.cmake` (the port and the
   device packages, linked by xpm), `board.cmake` (the facts),
   `platform-library.cmake`, `include/`, `src/`, the linker scripts and
   `openocd*.cfg`.
2. In `CMakeLists.txt`: the lists of §5.2a, and the run — `uos_tests_add_qemu`
   for an emulated machine, `uos_tests_add_hwd` (AArch: entry, target name
   format, cores, resume mode, reset) or `uos_tests_add_openocd` (Cortex-M:
   the OpenOCD commands) for the board.
3. Add its configuration pair to `package.json` (§9.1), with
   `openocd-dependencies` for a board and `qemu-arm-dependencies` for QEMU,
   and its `link-deps`.
4. Re-run the emulated tests of the other platforms of the same port: a new
   board must not change their results.

Files with a "DO NOT EDIT … generated from build-helper" header
(`cmake/tests-main.cmake`, `cmake/common-options.cmake`) have been changed
on purpose: edit the local copy, do not regenerate it.

---

## 10. Checklist before you commit

- [ ] `prepare` done after adding or removing a test folder; `ctest -N` shows
      the new case with the name you expect.
- [ ] `cmake --build build/<C> -- -k 0` builds every target, not only yours.
- [ ] The test passes alone and in the configuration's full `test` run.
- [ ] Debug **and** release.
- [ ] A port or builder change: the emulated tests of the port's other boards
      still pass.
- [ ] A hardware change: the `-hwd` case passes on the board.
- [ ] [`TESTS-CATALOG.md`](TESTS-CATALOG.md) updated for a new test or
      platform.
- [ ] No `WIFI_TEST_*` value in what you commit.

---

## 11. Troubleshooting

| symptom | cause and fix |
|---|---|
| "`<package>` is not linked into this build folder" | `xpm link` the package once, then `xpm run link-deps --config <C>` |
| `found /usr/bin/cc`, or the toolchain guard complains | configured before `install`, or `build` before `prepare`: `install`, then `prepare` |
| `Missing …/build/<C>/xpacks/…` on a release configuration | release has its own build folder: `install` and `link-deps` it |
| a new board test is not in `ctest -N` | not re-prepared, or its folder has no `*.cpp` |
| CTest runs an old image after a failed build | delete the image (or `build` successfully) before running again |
| `undefined reference to test::<suite>` / target not found | the suite is not in the platform's `dependencies-folders.cmake` |
| `<test> is both a portable test … and a board test` | the same name in `tests/sources/` and the platform's `tests/`: rename one |
| two definitions of `main` / of the start-up | a test that brings its own start-up is not in `BOARD_TEST_SELF_CONTAINED` |
| a QEMU test times out with no fault | host contention (parallel emulators): re-run it alone |
| a hardware test is "Not Run" with a failed `-hwd-reset` | the reset session did not reach the board: power, probe, wiring, `PROBE` |
| a hardware test never ends | it prints `RESULT` but does not end through semihosting (§7.2) |
| a USB gadget test does not enumerate | `SEMI_PRINTS` must be 0; the cable in the board's data/OTG port |

---

## 12. Reference tables

### 12.1 Files

| file | edit when |
|---|---|
| `tests/package.json` | a new configuration, toolchain or group |
| `tests/cmake/tests-main.cmake` | practically never |
| `tests/cmake/uos-tests-run.cmake` | a new way to run, a timeout |
| `tests/cmake/uos-hwd.tcl`, `uos-hwd-reset.cmake` | the AArch hardware run itself |
| `tests/board-tests/CMakeLists.txt` | the builder (affects every board) |
| `tests/platforms/<P>/cmake/*.cmake` | the board facts, the linked packages |
| `tests/platforms/<P>/CMakeLists.txt` | the tests a platform runs and how |
| `tests/platforms/<P>/tests/tests.cmake` | per-test knobs |
| `tests/platforms/<P>/tests/<test>/` | a board test |
| `tests/sources/<test>/` | a portable test or a suite |

### 12.2 Related documents

- [`COMMANDS.md`](COMMANDS.md) — every command, the probes and boards.
- [`TESTS-CATALOG.md`](TESTS-CATALOG.md) — every platform and test.
- [`test-framework.md`](test-framework.md) — upstream's framework, as on
  `xpack-development`.
- [`../posix-arch-port.md`](../posix-arch-port.md),
  [`../cortexm-port.md`](../cortexm-port.md),
  [`../building-aarch32-aarch64.md`](../building-aarch32-aarch64.md) — the
  ports.
- [`../history/`](../history/) — the layout and scripts before the
  alignment.
