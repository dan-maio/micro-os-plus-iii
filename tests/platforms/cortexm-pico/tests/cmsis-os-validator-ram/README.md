# CMSIS-RTOS Validator (RAM-Resident Execution) on Raspberry Pi Pico (RP2040)

This directory contains the RAM-resident variant of the CMSIS-RTOS validator test for the Raspberry Pi Pico (RP2040, dual Cortex-M0+).

Unlike the standard flash-based tests, `cmsis-os-validator-ram` is linked to execute **entirely from internal SRAM** (`0x20000000`) without writing anything to the external QSPI flash.

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
| `linker-ram.ld` | Dedicated linker script mapping all loadable sections (`.text`, `.rodata`, `.data`) to SRAM `0x20000000` (264 KB). Marks `.bss`, `.heap` and the 8 KB `.stack` as `(NOLOAD)` and discards `.boot2` (the flash second stage, not needed in RAM), so only the loadable sections are downloaded (~66 KB). |
| `harness-suite.cpp` | Name-only source: the suite is `test::<suite>`, the verdict `board-tests/cortexm/test-end.cpp` on the platform's start-up |

---

## 3. Linker Memory Layout (`linker-ram.ld`)

```
0x20000000 +-------------------------+  __vector_table / _entry_point
           | .text (.vectors, code)  |
           | .rodata                 |
           +-------------------------+
           | .data (initialized vars)|
0x200108FC +-------------------------+  __data_end__ (End of ELF FileSiz)
           | .bss (NOLOAD)           |
0x200146DC +-------------------------+  __bss_end__
           | .heap (NOLOAD, ~174 KB) |
0x20040000 +-------------------------+  __StackLimit
           | .stack (NOLOAD, 8 KB)   |
0x20041000 |   OpenOCD work-area     |  (verify_image only, before the run)
0x20042000 +-------------------------+  __StackTop
```

---

## 4. Boot & Execution Flow

1. **Reset Init**: OpenOCD connects via SWD, halts both cores, and resets peripherals.
2. **Load & Verify**: ELF binary is loaded directly into SRAM `0x20000000` via `load_image` and validated with `verify_image`.
3. **Core 1 Initialization**: Core 1 (`rp2040.core1`) has semihosting enabled and is resumed, idling in bootrom wait until launched by the RTOS.
4. **Core 0 Initialization**:
   - Vector Table Offset Register (VTOR, `0xE000ED08`) set to `0x20000000`.
   - Main Stack Pointer (SP) set to `[0x20000000]` (`__StackTop`).
   - Program Counter (PC) set to `[0x20000004] & ~1` (`_reset_handler`).
   - Semihosting enabled.
5. **Resume**: Core 0 begins executing directly from RAM.
6. **Verdict**: The RTOS test suite runs, validates kernel objects, timers, threads, and semaphores, then writes `RESULT: PASS` via semihosting and exits.

---

## 5. Running the Test

### Via CTest
```bash
cd <workspace>/micro-os-plus-iii/tests/build/cortexm-pico-cmake-gcc-debug
ctest -V -R cortexm-pico-cmsis-os-validator-ram-hwd
```

The `-hwd` test is registered in `platforms/cortexm-pico/CMakeLists.txt` (`_hwd_ram`): CTest runs OpenOCD with the board's `openocd.cfg`, which loads the image into SRAM, verifies it, starts core 1 in the boot ROM and core 0 from the image's vector table (VTOR, SP, PC). The test's semihosting exit ends OpenOCD; its `RESULT` line is the verdict.

