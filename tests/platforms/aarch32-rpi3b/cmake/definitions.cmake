# -----------------------------------------------------------------------------
# Platform specific definitions — µOS++ III AArch32, Raspberry Pi 3 B.
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/definitions.cmake..."
)

# -----------------------------------------------------------------------------

set (xpack_platform_compile_definition
     "MICRO_OS_PLUS_PLATFORM_AARCH32_RPI3B")

# The board. The port's CMakeLists reads BOARD when tests-main.cmake
# add_subdirectory()s it, after this file, and defaults it to rpi-zero-2w; a
# plain `set (BOARD ... CACHE ...)` would not override an existing cache entry,
# hence FORCE -- as the luckfox-lyra platform does. BOARD=rpi3b is the Pi 3 B:
# the Zero 2 W's sources with -DBOARD_RPI3B (mailbox ACT LED, 1 GB RAM,
# linker-rpi3b.ld), and its own test directory, test/rpi3b/.
set (BOARD "rpi3b" CACHE STRING "Target board (the port's board id)" FORCE)

# The AArch32 port supplies startup, vectors and the linker scripts, so there
# is no separate device xPack here and no xpack_device_* variables.

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
