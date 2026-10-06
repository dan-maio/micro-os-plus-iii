# -----------------------------------------------------------------------------
# Platform: µOS++ III Cortex-M on the Pi-Zero RP2350B (16 MB flash).
#
# The library under test is the local Cortex-M port
# (micro-os-plus-iii-cortexm.git), selected by the `^cortexm` branch in
# tests-main.cmake. The board is the port's own `pico2-pizero`.
#
# HARDWARE ONLY. This board is built ARMv8-M (__ARM_ARCH_8M_MAIN__) and QEMU's
# generic Cortex-M machine has no Cortex-M33, so there is no `qemu` image to
# register -- see the board's board.cmake, which clears UOS_BOARD_LINKER_QEMU.
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/definitions.cmake..."
)

set (xpack_platform_compile_definition
     "MICRO_OS_PLUS_PLATFORM_CORTEXM_PICO2_PIZERO")

# The port's board this platform targets. Must be set before tests-main.cmake
# add_subdirectory()s the port.
set (BOARD "pico2-pizero" CACHE STRING "Target board (the port's board id)" FORCE)
