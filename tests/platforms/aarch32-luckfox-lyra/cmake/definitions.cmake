# -----------------------------------------------------------------------------
# Platform specific definitions — µOS++ III AArch32, Luckfox Lyra B (RK3506).
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/definitions.cmake..."
)

# -----------------------------------------------------------------------------

set (xpack_platform_compile_definition
     "MICRO_OS_PLUS_PLATFORM_AARCH32_LUCKFOX_LYRA")

# -----------------------------------------------------------------------------
# Select the board in the port.
#
# tests-main.cmake includes this file BEFORE it add_subdirectory()s the port,
# so setting BOARD here is what makes the port read
# test/boards/luckfox-lyra/board.cmake and publish its facts. The port's own
# `set (BOARD "rpi-zero-2w" CACHE ...)` does not override an existing cache
# entry, so this wins.
#
# The Lyra is hardware-only: its board.cmake sets no UOS_BOARD_LINKER_QEMU,
# so the port emits one image per test (`hwd`) and no emulated suite. There is
# nothing here to select between -- QEMU models none of the RK3506's blocks.
set (BOARD "luckfox-lyra" CACHE STRING "Target board (the port's board id)" FORCE)

# -----------------------------------------------------------------------------
# Reproducibility guard.
#
# This platform is validated with the pinned xPack arm-none-eabi-gcc 15.2.1.
# The harness relies on xpm prepending build/<config>/xpacks/.bin to PATH,
# which is where the pinned compiler lives. A bare `cmake` (or a build tree
# whose xpacks/ was deleted) silently picks the system arm-none-eabi-gcc
# instead, so refuse anything that is not 15.2.
if (DEFINED CMAKE_C_COMPILER_VERSION
    AND NOT CMAKE_C_COMPILER_VERSION MATCHES "^15\\.2\\.")
  message (
    FATAL_ERROR
      "This platform must be built with the pinned xPack arm-none-eabi-gcc "
      "15.2, but found ${CMAKE_C_COMPILER} ${CMAKE_C_COMPILER_VERSION}.\n"
      "Run `xpm run install --config <config>` before prepare/build, and do "
      "not delete build/<config>/ — it holds the pinned toolchain."
  )
endif ()

# -----------------------------------------------------------------------------
