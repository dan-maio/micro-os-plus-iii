# platforms/qemu-cortex-m3

Support files for building a Cortex-M3 application to run on QEMU's
`mps2-an385` emulated board.

The library under test is the local Cortex-M port's generic single-core M3
core, `micro-os-plus::cortexm-qemu-m3`, running the SMP kernel's non-SMP
branch (`OS_NCPU=1`, no `OS_USE_SMP_SCHEDULER`). The platform links the
generic device in `tests/device-qemu-cortexm` (vector table, CMSIS core,
linker script) and registers three harness suites:
`qemu-cortex-m3-rtos-apis-test`, `qemu-cortex-m3-mutex-stress-test` and
`qemu-cortex-m3-cmsis-os-validator-test`.

## Include folders

The platform supplies its own `include/` (`cmsis-plus/platform.h`); the build
adds it automatically.

## Source files

Provided by the local Cortex-M port (`micro-os-plus::cortexm-qemu-m3`) and the
generic device `tests/device-qemu-cortexm` (vectors, CMSIS, linker script);
the platform links them automatically.

## Memory range

The applications are built for the following memory range:

- FLASH: 0x0000_0000-0x007F_FFFF (8 MB)
- RAM: 0x2000_0000-0x207F_FFFF (8 MB)
- HEAP: 0x2100_0000-0x21FF_FFFF (16 MB)
- stack: 0x2200_0000

The heap and stack are set automatically in `_startup()` to the values
returned by `SEMIHOSTING_SYS_HEAPINFO`.

## QEMU invocation

Each test is registered with CTest; the command is:

```sh
qemu-system-arm --machine mps2-an385 --cpu cortex-m3 --nographic -d unimp,guest_errors --kernel "rtos-apis-test.elf" --semihosting-config enable=on,target=native
```

For debug sessions start QEMU in GDB server mode by passing both `-s -S`:

```sh
qemu-system-arm --machine mps2-an385 --cpu cortex-m3 --nographic -d unimp,guest_errors -s -S --semihosting-config enable=on,target=native
```

## Links

- [QEMU Arm](https://www.qemu.org/docs/master/system/target-arm.html)
- [virt](https://www.qemu.org/docs/master/system/arm/virt.html)
