# -----------------------------------------------------------------------------
# Platform: µOS++ III Cortex-M33 on QEMU mps2-an505 (single Cortex-M33).
#
# `pico2-1cpu` is the pico2's Cortex-M33 run emulated on the single-core
# SSE-200 machine: the same ISA as the RP2350, one core, so the kernel's
# non-SMP branch is what runs. It is a QEMU-only configuration: pico2's
# hardware tests stay in `cortexm-pico2`.
# -----------------------------------------------------------------------------

set (xpack_platform_compile_definition "MICRO_OS_PLUS_PLATFORM_PICO2_1CPU")

# The generic QEMU Cortex-M33 device (device-qemu-cortexm) and its AN505
# memory map.
set (xpack_device_compile_definition "MICRO_OS_PLUS_DEVICE_QEMU_CORTEX_M33")
set (xpack_device_linker_script_file_name "mem-mps2-an505.ld")

# The port's board this platform derives from. The generic image does not link
# the board, but the Cortex-M port reads BOARD to pick its board.cmake.
set (BOARD "pico2" CACHE STRING "Target board (the port's board id)" FORCE)
