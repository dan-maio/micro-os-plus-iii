# -----------------------------------------------------------------------------
# Platform library — µOS++ III AArch32 on the Raspberry Pi 3 B.
#
# Two interface libraries:
#
#   micro-os-plus::platform          the base: include dirs, compile/link
#                                    options, the linker script, and the port.
#                                    Port tests link this and bring their own
#                                    strong main()/startup hooks.
#   micro-os-plus::platform-support  adds the startup hooks + strong main()
#                                    (src/platform-support.cpp) and the
#                                    kernel's semihosting syscall groups, for
#                                    the harness suites, which provide none of
#                                    them.
#
# Keeping them apart is what lets the port's own tests (which define their own
# strong main()/hooks) link the base without colliding with the harness's.
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/platform-library.cmake..."
)

# -----------------------------------------------------------------------------

# Validate: the port must have published its board facts before this file runs.
if (NOT DEFINED UOS_BOARD_NCPU OR NOT DEFINED UOS_BOARD_LINKER_QEMU)
  message (
    FATAL_ERROR
      "The AArch32 port did not publish its board facts (UOS_BOARD_*). "
      "It must be added by tests-main.cmake before this platform."
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
    # This is the QEMU variant, so the port selects its QEMU semihosting
    # (SVC + reason-by-value) rather than the hardware one.
    QEMU_BUILD
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
  INTERFACE micro-os-plus::aarch32
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
# Support for the harness suites: startup hooks, strong main(), and the C
# library. The plain iii kernel ships the latter in its core; the SMP kernel
# makes them optional groups. This is what the original harness relies on:
# newlib reentrant syscalls (_write_r, _gettimeofday_r, ...) -> the semihosting
# __posix_* layer, and the exit procedure os_terminate() -> report_exception()
# -> SWI 0x123456.
add_library (platform-aarch32-rpi3b-support-interface INTERFACE
             EXCLUDE_FROM_ALL)

target_sources (
  platform-aarch32-rpi3b-support-interface
  INTERFACE "src/platform-support.cpp"
)

target_link_libraries (
  platform-aarch32-rpi3b-support-interface
  INTERFACE platform-aarch32-rpi3b-interface
)

add_library (micro-os-plus::platform-support
             ALIAS platform-aarch32-rpi3b-support-interface)
message (
  VERBOSE
  "> micro-os-plus::platform-support -> "
  "platform-aarch32-rpi3b-support-interface"
)

# -----------------------------------------------------------------------------
