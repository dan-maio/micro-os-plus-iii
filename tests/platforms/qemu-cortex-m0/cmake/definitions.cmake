# -----------------------------------------------------------------------------
# Platform: µOS++ III Cortex-M0 on QEMU's generic Cortex-M machine (single core).
#
# `qemu-cortex-m0` runs the portable harness suites on the SMP kernel's
# single-core branch (OS_NCPU=1, no OS_USE_SMP_SCHEDULER), compiled for the
# Cortex-M0 ISA. QEMU models no Cortex-M0 mps2 board, so the Thumb-1 image runs
# on the Cortex-M3 core of the mps2-an385 machine; the M0 code is a subset of
# what that core executes.
# -----------------------------------------------------------------------------

set (xpack_platform_compile_definition "MICRO_OS_PLUS_PLATFORM_QEMU_CORTEX_M0")

# The generic QEMU Cortex-M0 device (device-qemu-cortexm) and its AN385 map.
set (xpack_device_compile_definition "MICRO_OS_PLUS_DEVICE_QEMU_CORTEX_M0")
set (xpack_device_linker_script_file_name "mem-mps2-an385.ld")

# The port's board this platform derives from. The generic image does not link
# the board, but the Cortex-M port reads BOARD to pick its board.cmake.
set (BOARD "nucleof411" CACHE STRING "Target board (the port's board id)" FORCE)
