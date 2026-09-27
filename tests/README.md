# Tests

## Overview

The µOS++ testing strategy is to compile the sources with as many
toolchains as possible, and run them on as many platforms as possible.

The harness is driven by **xpm** and **CTest**. The authoritative guides are
[`docs/tests/STEPS.md`](../docs/tests/STEPS.md) (how to install, build, run
and add tests) and
[`docs/tests/TESTS-CATALOG.md`](../docs/tests/TESTS-CATALOG.md) (every
platform, test and probe). This file is only a short orientation.

## Platforms

There are 22 platforms under `platforms/`, grouped by the port they exercise:

- `aarch32-rpi-zero-2w`, `aarch32-rpi3b`, `aarch32-luckfox-lyra` — the AArch32 port
- `aarch64-rpi-zero-2w`, `aarch64-rpi3b` — the AArch64 port
- `cortexm-pico2`, `cortexm-pico2-pizero`, `cortexm-pico2-rp2350b-psram`,
  `cortexm-nucleof411`, `cortexm-weactf411`, `cortexm-weactf412` — the Cortex-M
  port on real boards
- `pico2-1cpu`, `2xcortex-m33` — the Cortex-M port's generic Cortex-M33 core
  in QEMU (single core and dual-core SMP)
- `qemu-cortex-m0`, `qemu-cortex-m3`, `qemu-cortex-m4f`, `qemu-cortex-m7f` —
  the Cortex-M port's generic M0/M3/M4F/M7 cores in QEMU, run single-core
- `native` — the POSIX-arch port, as a host process (gcc or clang)
- `nucleo-f411re`, `nucleo-f767zi`, `nucleo-h743zi`, `raspberrypi-pico` —
  the upstream plain-kernel platforms

See [`docs/tests/TESTS-CATALOG.md`](../docs/tests/TESTS-CATALOG.md) for the
full table with QEMU machines, CPU counts and probes.

The tests are performed on GNU/Linux, macOS and Windows.

Exactly the same source files are used on all platforms, without changes.

## Toolchains

For native tests, the toolchains used are:

- GCC 11, 12, 13, 14 and the latest (`native-cmake-gcc`)
- clang 13, 14, 15, 16, 17, 18, 19

For Cortex-M tests, the toolchain is arm-none-eabi-gcc 15.2.

## Tests details

All commands run from this `tests/` folder. To build and run the emulated
Cortex-M sets, debug and release:

```sh
xpm run test-cortex-cmake
```

To build and run one platform, debug and release:

```sh
xpm run test-<platform>-cmake      # e.g. test-aarch32-rpi-zero-2w-cmake
```

To run the CI set plus the native suites:

```sh
xpm run test-all
```

To run the tests in a forever loop:

```sh
set -e
while (true); do xpm run test-cortex-cmake -C "${HOME}/Work/micro-os-plus-iii-smp.git/tests"; done
```

```sh
set -e
while (true); do xpm run test-all -C "${HOME}/Work/micro-os-plus-iii-smp.git/tests"; done
```

The tests ran many hours in loops without problems.

Note: there should be no trace messages in the scheduler interrupt, otherwise
the tests occasionally fail, as shown below.

### rtos-apis

A simple test to exercise most of the RTOS APIs, both C and C++.

### mutex-stress

This test exercises the mutex logic, by using random locks from multiple
threads and checking the distribution.

### cmsis-os-validator

This test uses the Arm CMSIS Validator (60 cases).

### fp-switch

Six threads at three priorities each load their own FPU pattern and check it
survives preemption (and, on SMP, migration). Needs an FPU; without one it
passes with nothing to test.

### blinky and instrumentation

Small demos enabled only on `nucleo-f411re`. `blinky` is registered as
`blinky-test`; `instrumentation` (SEGGER SystemView) is built but not
registered — it runs from SEGGER Ozone with a J-Link.

### deprecated

The old tests are kept for historical reasons. Some of them might be
revived in the future.
