# -----------------------------------------------------------------------------
# Platform library — µOS++ III AArch32 on the Raspberry Pi 3 B.
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

add_library (platform-aarch32-rpi3b-interface INTERFACE EXCLUDE_FROM_ALL)

target_include_directories (
  platform-aarch32-rpi3b-interface INTERFACE "include"
)

target_compile_definitions (
  platform-aarch32-rpi3b-interface
  INTERFACE
    "${xpack_platform_compile_definition}"
    OS_NCPU=${UOS_BOARD_NCPU}
    OS_USE_SMP_SCHEDULER=1
    TRACE
    SEMIHOST
    __ARM_EABI__
    __ARM_ARCH_7A__
    # The kernel's trace goes to the semihosting channel (SVC 0x123456).
    OS_USE_TRACE_SEMIHOSTING_STDOUT
    # GNU extensions used by the semihosting syscall layer (S_IREAD, ...).
    _GNU_SOURCE
)

target_compile_options (
  platform-aarch32-rpi3b-interface
  INTERFACE $<$<COMPILE_LANGUAGE:C>:-std=gnu11>
            $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions>
            $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti>
            $<$<COMPILE_LANGUAGE:CXX>:-fabi-version=0>
)

target_link_options (
  platform-aarch32-rpi3b-interface
  INTERFACE -nostartfiles -Wl,--gc-sections "-T${UOS_BOARD_LINKER_QEMU}"
)

target_link_libraries (
  platform-aarch32-rpi3b-interface
  INTERFACE micro-os-plus::aarch32 micro-os-plus::board
            # The C library: newlib reentrant syscalls (_write_r, ...) -> the
            # semihosting __posix_* layer. Any test that uses printf needs
            # these, the port tests and the harness suites alike. The plain iii
            # kernel ships them in its core; the SMP kernel makes them optional
            # groups.
            micro-os-plus::iii-newlib-reent
            micro-os-plus::iii-semihosting
)

add_library (micro-os-plus::platform
             ALIAS platform-aarch32-rpi3b-interface)
message (
  VERBOSE
  "> micro-os-plus::platform -> platform-aarch32-rpi3b-interface"
)

# -----------------------------------------------------------------------------
