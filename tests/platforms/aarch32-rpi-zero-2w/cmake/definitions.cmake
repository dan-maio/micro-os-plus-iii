# -----------------------------------------------------------------------------
# Platform specific definitions — µOS++ III AArch32, Raspberry Pi Zero 2 W.
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/definitions.cmake..."
)

# -----------------------------------------------------------------------------

set (xpack_platform_compile_definition
     "MICRO_OS_PLUS_PLATFORM_AARCH32_RPI_ZERO_2W")

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
