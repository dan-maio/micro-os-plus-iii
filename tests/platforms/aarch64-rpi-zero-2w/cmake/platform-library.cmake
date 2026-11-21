# -----------------------------------------------------------------------------
# Platform library — µOS++ III AArch64 on the Raspberry Pi Zero 2 W.
#
# One interface library:
#
#   micro-os-plus::platform          the base: include dirs, compile/link
#                                    options, the linker script, and the port.
#
# The tests' builder (tests/board-tests/CMakeLists.txt) compiles the platform's
# src/platform-support.cpp into <platform>-test-startup, with that image's own
# variant defines and linker script; there is no separate support target.
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/platform-library.cmake..."
)

# -----------------------------------------------------------------------------

# Validate: the port must have published its board facts before this file runs.
# The board: its facts (cmake/board.cmake) and micro-os-plus::board.
include ("${CMAKE_CURRENT_LIST_DIR}/board.cmake")
include ("${CMAKE_SOURCE_DIR}/cmake/uos-aarch-board.cmake")
uos_aarch_board_library ("${UOS_BOARD_SOC_DIR}")

if (NOT DEFINED UOS_BOARD_NCPU OR NOT DEFINED UOS_BOARD_LINKER_QEMU)
  message (
    FATAL_ERROR
      "cmake/board.cmake did not set the board facts this platform needs (UOS_BOARD_*)."
  )
endif ()

# -----------------------------------------------------------------------------

add_library (platform-aarch64-rpi-zero-2w-interface INTERFACE EXCLUDE_FROM_ALL)

target_include_directories (
  platform-aarch64-rpi-zero-2w-interface INTERFACE "include"
)

target_compile_definitions (
  platform-aarch64-rpi-zero-2w-interface
  INTERFACE
    "${xpack_platform_compile_definition}"
    OS_NCPU=${UOS_BOARD_NCPU}
    OS_USE_SMP_SCHEDULER=1
    TRACE
    SEMIHOST
    __ARM_EABI__
    __ARM_ARCH_8A__
    _GNU_SOURCE
)

target_compile_options (
  platform-aarch64-rpi-zero-2w-interface
  INTERFACE $<$<COMPILE_LANGUAGE:C>:-std=gnu11>
            $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions>
            $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti>
            $<$<COMPILE_LANGUAGE:CXX>:-fabi-version=0>
)

target_link_options (
  platform-aarch64-rpi-zero-2w-interface
  INTERFACE -nostartfiles -Wl,--gc-sections "-T${UOS_BOARD_LINKER_QEMU}"
)

target_link_libraries (
  platform-aarch64-rpi-zero-2w-interface
  INTERFACE micro-os-plus::aarch64 micro-os-plus::board
)

add_library (micro-os-plus::platform
             ALIAS platform-aarch64-rpi-zero-2w-interface)
message (
  VERBOSE
  "> micro-os-plus::platform -> platform-aarch64-rpi-zero-2w-interface"
)

# -----------------------------------------------------------------------------
