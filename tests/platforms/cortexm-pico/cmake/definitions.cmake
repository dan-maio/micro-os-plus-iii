# -----------------------------------------------------------------------------
# Platform: µOS++ III Cortex-M on the Raspberry Pi Pico (RP2040).
#
# The library under test is the local Cortex-M port
# (micro-os-plus-iii-cortexm.git), selected by the `^cortexm` branch in
# tests-main.cmake. The board is the port's own `pico`.
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/definitions.cmake..."
)

set (xpack_platform_compile_definition "MICRO_OS_PLUS_PLATFORM_CORTEXM_PICO")

# The `qemu` variant of a pico test does not link the board: it links the
# kernel plus the harness's generic QEMU Cortex-M device
# (tests/device-qemu-cortexm), whose vectors-cortexm.c owns the vector table,
# configured for the Cortex-M0 on QEMU's mps2-an385 map -- exactly as the
# qemu-cortex-m0 platform. The port's micro-os-plus::cortexm-qemu-m0 library
# has the matching flags.
set (xpack_device_compile_definition "MICRO_OS_PLUS_DEVICE_QEMU_CORTEX_M0")
set (xpack_device_linker_script_file_name "mem-mps2-an385.ld")

# The port's board this platform targets. Must be set before tests-main.cmake
# add_subdirectory()s the port.
set (BOARD "pico" CACHE STRING "Target board (the port's board id)" FORCE)
