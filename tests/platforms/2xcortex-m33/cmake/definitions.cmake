# -----------------------------------------------------------------------------
# Platform: µOS++ III Cortex-M33 SMP on QEMU mps2-an521 (2 x Cortex-M33).
#
# `2xcortex-m33` is the closest emulation of the pico2's dual Cortex-M33 that
# QEMU offers: an SSE-200 with two cores sharing one coherency domain. It is
# NOT a pico2 test -- QEMU models none of the RP2350's SIO/USB/PSRAM, and the
# SSE-200 supplies the IPI through its MHU instead -- but it exercises the
# kernel's SMP scheduler on the pico2's ISA. The pico2 hardware tests stay in
# `cortexm-pico2`.
# -----------------------------------------------------------------------------

set (xpack_platform_compile_definition "MICRO_OS_PLUS_PLATFORM_2XCORTEX_M33")

# The generic QEMU Cortex-M33 device (device-qemu-cortexm) and its AN521 map.
set (xpack_device_compile_definition "MICRO_OS_PLUS_DEVICE_QEMU_CORTEX_M33")
set (xpack_device_linker_script_file_name "mem-mps2-an521.ld")

# The port's board this platform derives from. The generic image does not link
# the board, but the Cortex-M port reads BOARD to pick its board.cmake.
set (BOARD "pico2" CACHE STRING "Target board (the port's board id)" FORCE)
