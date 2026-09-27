# -----------------------------------------------------------------------------
# Platform: µOS++ III Cortex-M3 on QEMU's generic Cortex-M machine (single core).
#
# `qemu-cortex-m3` runs the portable harness suites on the SMP kernel's
# single-core branch (OS_NCPU=1, no OS_USE_SMP_SCHEDULER), compiled for the
# Cortex-M3 ISA and executed on QEMU's mps2-an385 machine.
# -----------------------------------------------------------------------------

set (xpack_platform_compile_definition "MICRO_OS_PLUS_PLATFORM_QEMU_CORTEX_M3")

# The generic QEMU Cortex-M3 device (device-qemu-cortexm) and its AN385 map.
set (xpack_device_compile_definition "MICRO_OS_PLUS_DEVICE_QEMU_CORTEX_M3")
set (xpack_device_linker_script_file_name "mem-mps2-an385.ld")

# The port's board this platform derives from. The generic image does not link
# the board, but the Cortex-M port reads BOARD to pick its board.cmake.
set (BOARD "nucleof411" CACHE STRING "Target board (the port's board id)" FORCE)
