# -----------------------------------------------------------------------------
# Platform specific definitions — µOS++ III AArch64, Raspberry Pi 3 B.
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/definitions.cmake..."
)

# -----------------------------------------------------------------------------

set (xpack_platform_compile_definition
     "MICRO_OS_PLUS_PLATFORM_AARCH64_RPI3B")

# The board. The port's CMakeLists reads BOARD when tests-main.cmake
# add_subdirectory()s it, after this file, and defaults it to rpi-zero-2w; a
# plain `set (BOARD ... CACHE ...)` would not override an existing cache entry,
# hence FORCE -- as the luckfox-lyra platform does. BOARD=rpi3b is the Pi 3 B:
# the Zero 2 W's sources with -DBOARD_RPI3B (mailbox ACT LED, 1 GB RAM,
# linker-rpi3b.ld), and its own test directory, test/rpi3b/.
set (BOARD "rpi3b" CACHE STRING "Target board (the port's board id)" FORCE)

# The AArch64 port supplies startup, vectors and the linker scripts, so there
# is no separate device xPack here and no xpack_device_* variables.

# -----------------------------------------------------------------------------
# Reproducibility guard: this platform is validated with the pinned xPack
# aarch64-none-elf-gcc 15.2. The harness relies on xpm prepending
# build/<config>/xpacks/.bin to PATH, where the pinned compiler lives.
if (DEFINED CMAKE_C_COMPILER_VERSION
    AND NOT CMAKE_C_COMPILER_VERSION MATCHES "^15\\.2\\.")
  message (
    FATAL_ERROR
      "This platform must be built with the pinned xPack aarch64-none-elf-gcc "
      "15.2, but found ${CMAKE_C_COMPILER} ${CMAKE_C_COMPILER_VERSION}.\n"
      "Run `xpm run install --config <config>` before prepare/build, and do "
      "not delete build/<config>/ — it holds the pinned toolchain."
  )
endif ()

# -----------------------------------------------------------------------------
