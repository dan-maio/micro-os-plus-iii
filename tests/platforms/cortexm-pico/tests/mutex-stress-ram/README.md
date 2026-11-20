# Mutex Stress Test (RAM-Resident Execution) on Raspberry Pi Pico (RP2040)

This directory contains the RAM-resident variant of the mutex stress test suite for the Raspberry Pi Pico (RP2040, dual Cortex-M0+).

Like `cmsis-os-validator-ram`, this test is linked to execute **entirely from internal SRAM** (`0x20000000`) without writing anything to the external QSPI flash.

---

## 1. Overview & Architecture

- **Target Architecture**: Raspberry Pi Pico (RP2040, 2x Cortex-M0+).
- **Toolchain**: `arm-none-eabi-gcc` 15.2 (xPack GNU Arm Embedded Toolchain).
- **Debugger**: OpenOCD via the JTAGprobe (CMSIS-DAP v2, `2e8a:000c`), SWD at 15 MHz by default (`UOS_HW_ADAPTER_KHZ` overrides it).
- **Execution Target**: Internal SRAM (`0x20000000`, 264 KB).

### Isolation Guarantee
- All modifications are strictly isolated to this test directory and its test hook registrations.
- Existing flash-based tests, board-level OpenOCD configs, and framework boot flows remain completely unmodified.

---

## 2. Components

| File | Purpose |
|------|---------|
| `linker-ram.ld` | Dedicated linker script mapping all loadable sections (`.text`, `.rodata`, `.data`) to SRAM `0x20000000` (264 KB). Marks `.bss`, `.heap` and the 8 KB `.stack` as `(NOLOAD)` and discards `.boot2` (the flash second stage, not needed in RAM), so only the loadable sections are downloaded (~39 KB). |
| `harness-suite.cpp` | Name-only source: the suite is `test::<suite>`, the verdict `board-tests/cortexm/test-end.cpp` on the platform's start-up |

---

## 3. Running the Test

### Via CTest
```bash
cd <workspace>/micro-os-plus-iii/tests/build/cortexm-pico-cmake-gcc-debug
ctest -V -R cortexm-pico-mutex-stress-ram-hwd
```

The `-hwd` test is registered in `platforms/cortexm-pico/CMakeLists.txt` (`_hwd_ram`): CTest runs OpenOCD with the board's `openocd.cfg`, which loads the image into SRAM, verifies it, starts core 1 in the boot ROM and core 0 from the image's vector table (VTOR, SP, PC). The test's semihosting exit ends OpenOCD; its `RESULT` line is the verdict.

