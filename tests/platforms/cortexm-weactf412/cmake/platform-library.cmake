# -----------------------------------------------------------------------------
# Platform library — µOS++ III Cortex-M on the WeAct F412RE (STM32F412RE).
#
# micro-os-plus::platform is the port plus the kernel's optional groups the
# board's tests and the harness suites need. The port's own tests link
# micro-os-plus::cortexm directly (through the port's builder); the harness
# suites link this.
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/platform-library.cmake..."
)

add_library (platform-cortexm-weactf412-interface INTERFACE EXCLUDE_FROM_ALL)

target_include_directories (platform-cortexm-weactf412-interface INTERFACE "include")

target_compile_definitions (
  platform-cortexm-weactf412-interface INTERFACE "${xpack_platform_compile_definition}" _GNU_SOURCE
)

target_link_libraries (
  platform-cortexm-weactf412-interface
  INTERFACE
    # The Cortex-M port: brings the kernel (micro-os-plus::iii), the board's
    # flags, and the board's own sources.
    micro-os-plus::cortexm
    # The kernel's optional groups the startup and the C library need.
    micro-os-plus::iii-startup
    micro-os-plus::iii-semihosting
    micro-os-plus::iii-newlib-reent
    micro-os-plus::iii-posix-io
)

add_library (micro-os-plus::platform ALIAS platform-cortexm-weactf412-interface)
message (VERBOSE "> micro-os-plus::platform -> platform-cortexm-weactf412-interface")
