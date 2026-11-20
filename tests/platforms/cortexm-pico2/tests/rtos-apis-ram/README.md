# RTOS APIs (RAM-Resident Execution) on Raspberry Pi Pico 2 (RP2350)

This directory contains the RAM-resident variant of the RTOS APIs test suite for the Raspberry Pi Pico 2 (RP2350, dual Cortex-M33).

Like `cmsis-os-validator-ram`, this test is linked to execute **entirely from internal SRAM** (`0x20000000`) without writing anything to the external QSPI flash.

---

## 1. Overview & Architecture

- **Target Architecture**: Raspberry Pi Pico 2 (RP2350, 2x Cortex-M33).
- **Toolchain**: `arm-none-eabi-gcc` 15.2 (xPack GNU Arm Embedded Toolchain).
- **Debugger**: OpenOCD via CMSIS-DAP (Raspberry Pi Debug Probe).
- **Execution Target**: Internal SRAM (`0x20000000`, 520 KB).

### Isolation Guarantee
- All modifications are strictly isolated to this test directory and its test hook registrations.
- Existing flash-based tests, board-level OpenOCD configs, and framework boot flows remain completely unmodified.

---

## 2. Components

| File | Purpose |
|------|---------|
| `linker-ram.ld` | Dedicated linker script mapping all loadable sections (`.text`, `.rodata`, `.data`) to SRAM `0x20000000`. Marks `.bss`, `.heap`, `.stack` as `(NOLOAD)` and embeds Pico `.embedded_end_block` to keep the download size compact. |
| `harness-suite.cpp` | Name-only source: the suite is `test::<suite>`, the verdict `board-tests/cortexm/test-end.cpp` on the platform's start-up |

---

## 3. Running the Test

### Via CTest
```bash
cd <workspace>/micro-os-plus-iii/tests/build/cortexm-pico2-cmake-gcc-release
ctest -V -R cortexm-pico2-rtos-apis-ram-hwd
```

The `-hwd` test is registered in `platforms/cortexm-pico2/CMakeLists.txt` (`_hwd_ram`): CTest runs OpenOCD with the board's `openocd.cfg`, which loads the image into SRAM, verifies it, starts core 1 in the boot ROM and core 0 from the image's vector table (VTOR, SP, PC). The test's semihosting exit ends OpenOCD; its `RESULT` line is the verdict.

