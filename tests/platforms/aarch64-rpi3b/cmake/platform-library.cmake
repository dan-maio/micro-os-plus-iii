# -----------------------------------------------------------------------------
# Platform library — µOS++ III AArch64 on the Raspberry Pi 3 B.
#
# Two interface libraries:
#
#   micro-os-plus::platform          the base: include dirs, compile/link
#                                    options, the linker script, and the port.
#                                    Port tests link this and bring their own
#                                    strong main()/startup hooks.
#   micro-os-plus::platform-support  adds the startup hooks + strong main()
#                                    (src/platform-support.cpp), the strong
#                                    semihosting _Exit(), and _gettimeofday,
#                                    for the harness suites.
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
      "The AArch64 port did not publish its board facts (UOS_BOARD_*). "
      "It must be added by tests-main.cmake before this platform."
  )
endif ()

# -----------------------------------------------------------------------------

add_library (platform-aarch64-rpi3b-interface INTERFACE EXCLUDE_FROM_ALL)

target_include_directories (
  platform-aarch64-rpi3b-interface INTERFACE "include"
)

target_compile_definitions (
  platform-aarch64-rpi3b-interface
  INTERFACE
    "${xpack_platform_compile_definition}"
    OS_NCPU=${UOS_BOARD_NCPU}
    OS_USE_SMP_SCHEDULER=1
    TRACE
    SEMIHOST
    # This is the QEMU variant (the AArch64 port uses HLT either way, but the
    # board code may branch on it).
    QEMU_BUILD
    __ARM_EABI__
    __ARM_ARCH_8A__
    _GNU_SOURCE
)

target_compile_options (
  platform-aarch64-rpi3b-interface
  INTERFACE $<$<COMPILE_LANGUAGE:C>:-std=gnu11>
            $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions>
            $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti>
            $<$<COMPILE_LANGUAGE:CXX>:-fabi-version=0>
)

target_link_options (
  platform-aarch64-rpi3b-interface
  INTERFACE -nostartfiles -Wl,--gc-sections "-T${UOS_BOARD_LINKER_QEMU}"
)

target_link_libraries (
  platform-aarch64-rpi3b-interface
  INTERFACE micro-os-plus::aarch64
)

add_library (micro-os-plus::platform
             ALIAS platform-aarch64-rpi3b-interface)
message (
  VERBOSE
  "> micro-os-plus::platform -> platform-aarch64-rpi3b-interface"
)

# -----------------------------------------------------------------------------
# Support for the harness suites: startup hooks, strong main(), the strong
# semihosting _Exit() and _gettimeofday. Port tests provide their own main()
# and hooks, and terminate via hw_result, so they link only the base.
add_library (platform-aarch64-rpi3b-support-interface INTERFACE
             EXCLUDE_FROM_ALL)

target_sources (
  platform-aarch64-rpi3b-support-interface
  INTERFACE "src/platform-support.cpp"
)

target_link_libraries (
  platform-aarch64-rpi3b-support-interface
  INTERFACE platform-aarch64-rpi3b-interface
)

add_library (micro-os-plus::platform-support
             ALIAS platform-aarch64-rpi3b-support-interface)
message (
  VERBOSE
  "> micro-os-plus::platform-support -> "
  "platform-aarch64-rpi3b-support-interface"
)

# -----------------------------------------------------------------------------
