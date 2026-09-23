# -----------------------------------------------------------------------------
# Platform: µOS++ III Cortex-M on the Raspberry Pi Pico 2 (RP2350).
#
# The library under test is the local Cortex-M port
# (micro-os-plus-iii-cortexm.git), selected by the `^cortexm` branch in
# tests-main.cmake. The board is the port's own `pico2`.
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/definitions.cmake..."
)

set (xpack_platform_compile_definition "MICRO_OS_PLUS_PLATFORM_CORTEXM_PICO2")

# The `qemu` variant of a pico2 test does not link the board: it links the
# kernel plus the harness's generic QEMU Cortex-M device
# (tests/device-qemu-cortexm), whose vectors-cortexm.c owns the vector table.
# The device's CMSIS core has no Cortex-M33, so the emulated image targets
# QEMU's generic Cortex-M7 machine (mps2-an500) -- see the port's
# micro-os-plus::cortexm-qemu library for the matching flags.
set (xpack_device_compile_definition "MICRO_OS_PLUS_DEVICE_QEMU_CORTEX_M7")
set (xpack_device_linker_script_file_name "mem-mps2-an500.ld")

# The port's board this platform targets. Must be set before tests-main.cmake
# add_subdirectory()s the port.
set (BOARD "pico2" CACHE STRING "Target board (the port's board id)" FORCE)
