# -----------------------------------------------------------------------------
# Platform specific definitions — µOS++ III AArch64, Raspberry Pi 4 B.
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/definitions.cmake..."
)

# -----------------------------------------------------------------------------

set (xpack_platform_compile_definition
     "MICRO_OS_PLUS_PLATFORM_AARCH64_RPI4B")

# The board. The port's CMakeLists reads BOARD when tests-main.cmake
# add_subdirectory()s it, after this file, and defaults it to rpi-zero-2w; a
# plain `set (BOARD ... CACHE ...)` would not override an existing cache entry,
# hence FORCE -- as the luckfox-lyra platform does. BOARD=rpi4b is the Pi 4 B:
# its own board sources (test/boards/rpi4b/: GIC-400, 4 GB VA MMU, EL3/EL2
# startup), its own SoC (soc/bcm2711/), and its own tests, test/rpi4b/.
set (BOARD "rpi4b" CACHE STRING "Target board (the port's board id)" FORCE)

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
