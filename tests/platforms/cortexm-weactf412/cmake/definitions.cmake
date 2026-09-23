# -----------------------------------------------------------------------------
# Platform: µOS++ III Cortex-M on the WeAct F412RE (STM32F412RE).
#
# The library under test is the local Cortex-M port
# (micro-os-plus-iii-cortexm.git), selected by the `^cortexm` branch in
# tests-main.cmake. The board is the port's own `weactf412`.
#
# HARDWARE ONLY: this board is programmed over its ST-Link and run on the desk,
# so the board declares no UOS_BOARD_LINKER_QEMU and the port's builder emits
# `hwd` alone.
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/definitions.cmake..."
)

set (xpack_platform_compile_definition "MICRO_OS_PLUS_PLATFORM_CORTEXM_WEACTF412")

# The port's board this platform targets. Must be set before tests-main.cmake
# add_subdirectory()s the port.
set (BOARD "weactf412" CACHE STRING "Target board (the port's board id)" FORCE)
