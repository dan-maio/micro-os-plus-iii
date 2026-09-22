# -----------------------------------------------------------------------------
# Platform library — µOS++ III AArch32 on the Luckfox Lyra B (RK3506).
#
# One interface library, the base:
#
#   micro-os-plus::platform   include dirs, compile/link options, the board's
#                             HARDWARE linker script, and the port. A board
#                             test links this and brings its own strong
#                             main()/startup hooks.
#
# There is no micro-os-plus::platform-support here. That exists for the
# harness suites, which supply neither a main() nor startup hooks; the Lyra
# platform runs a port test, and the port test supplies both. Adding a support
# library would only create a second strong main() to collide with it.
#
# The build is HARDWARE (HW_BUILD), never QEMU_BUILD: the trap the port's
# semihosting uses is the debugger's (SVC 0x123456, the cortex_a Angel trap),
# and the exit reason is a POINTER -- see the port's include/semihosting.hpp.
# Defining QEMU_BUILD here would silently select the emulator's SVC + reason-
# by-value instead, which under OpenOCD reports the wrong status.
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/platform-library.cmake..."
)

# -----------------------------------------------------------------------------

# Validate: the port must have published its board facts before this file runs.
if (NOT DEFINED UOS_BOARD_NCPU OR NOT DEFINED UOS_BOARD_LINKER_HW)
  message (
    FATAL_ERROR
      "The AArch32 port did not publish its board facts (UOS_BOARD_*). "
      "It must be added by tests-main.cmake before this platform, with "
      "BOARD=luckfox-lyra selected in definitions.cmake."
  )
endif ()

# -----------------------------------------------------------------------------

add_library (platform-aarch32-luckfox-lyra-interface INTERFACE EXCLUDE_FROM_ALL)

target_include_directories (
  platform-aarch32-luckfox-lyra-interface INTERFACE "include"
)

target_compile_definitions (
  platform-aarch32-luckfox-lyra-interface
  INTERFACE
    "${xpack_platform_compile_definition}"
    OS_NCPU=${UOS_BOARD_NCPU}
    OS_USE_SMP_SCHEDULER=1
    TRACE
    SEMIHOST
    # This is the hardware variant, so the port selects its hardware
    # semihosting (the debugger's trap, reason-by-pointer) rather than the
    # emulator's. There is deliberately no QEMU_BUILD.
    HW_BUILD
    __ARM_EABI__
    __ARM_ARCH_7A__
    # GNU extensions used by the kernel's semihosting syscall layer
    # (c-syscalls-semihosting.cpp: S_IREAD, S_IWRITE, ...), which the harness
    # suites link through micro-os-plus::iii-semihosting.
    _GNU_SOURCE
)

target_compile_options (
  platform-aarch32-luckfox-lyra-interface
  INTERFACE $<$<COMPILE_LANGUAGE:C>:-std=gnu11>
            $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions>
            $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti>
            $<$<COMPILE_LANGUAGE:CXX>:-fabi-version=0>
)

target_link_options (
  platform-aarch32-luckfox-lyra-interface
  INTERFACE -nostartfiles -Wl,--gc-sections "-T${UOS_BOARD_LINKER_HW}"
)

target_link_libraries (
  platform-aarch32-luckfox-lyra-interface
  INTERFACE micro-os-plus::aarch32
)

add_library (micro-os-plus::platform
             ALIAS platform-aarch32-luckfox-lyra-interface)
message (
  VERBOSE
  "> micro-os-plus::platform -> platform-aarch32-luckfox-lyra-interface"
)

# -----------------------------------------------------------------------------
# Support for the HARNESS suites: startup hooks + strong main()
# (src/platform-support.cpp) and the kernel's C-library groups, for the suites,
# which provide neither a main() nor the syscalls.
#
# The port's own board tests bring their own main()/hooks and link only the
# base, so this stays separate and does not collide with them.
add_library (platform-aarch32-luckfox-lyra-support-interface INTERFACE
             EXCLUDE_FROM_ALL)

target_sources (
  platform-aarch32-luckfox-lyra-support-interface
  INTERFACE "src/platform-support.cpp"
)

target_link_libraries (
  platform-aarch32-luckfox-lyra-support-interface
  INTERFACE platform-aarch32-luckfox-lyra-interface
            # The C library: newlib reentrant syscalls (_write_r, ...) -> the
            # semihosting __posix_* layer. printf() and gettimeofday() in the
            # harness suites need these.
            micro-os-plus::iii-newlib-reent
            micro-os-plus::iii-semihosting
)

add_library (micro-os-plus::platform-support
             ALIAS platform-aarch32-luckfox-lyra-support-interface)
message (
  VERBOSE
  "> micro-os-plus::platform-support -> "
  "platform-aarch32-luckfox-lyra-support-interface"
)

# -----------------------------------------------------------------------------
