# -----------------------------------------------------------------------------
# Platform library — µOS++ III Cortex-M33 on QEMU mps2-an505.
#
# The library under test is the local Cortex-M port, but the emulated image
# uses its GENERIC Cortex-M33 core (micro-os-plus::cortexm-qemu-m33), not the
# board core: QEMU models none of the RP2350's SIO/USB/PSRAM.
# -----------------------------------------------------------------------------

add_library (platform-pico2-1cpu-interface INTERFACE EXCLUDE_FROM_ALL)

target_include_directories (platform-pico2-1cpu-interface INTERFACE "include")

target_compile_definitions (
  platform-pico2-1cpu-interface
  INTERFACE
    "${xpack_platform_compile_definition}"
    _POSIX_C_SOURCE=200809L
    # For S_IREAD
    _GNU_SOURCE
    # Single core: no OS_USE_SMP_SCHEDULER.
    OS_NCPU=1
)

target_link_libraries (
  platform-pico2-1cpu-interface
  INTERFACE
    # The generic Cortex-M33 port (brings the kernel, micro-os-plus::iii).
    micro-os-plus::cortexm-qemu-m33
    # CMSIS Cortex-M33 core headers (core_cm33.h).
    xpack-3rd-party::arm-cmsis-core-m
    # The generic QEMU device: vector table + CMSIS.
    micro-os-plus::device
    # The kernel's optional groups the startup and the C library need.
    micro-os-plus::iii-startup
    micro-os-plus::iii-trace-semihosting
    micro-os-plus::iii-semihosting
    micro-os-plus::iii-newlib-reent
    micro-os-plus::iii-posix-io
)

add_library (micro-os-plus::platform ALIAS platform-pico2-1cpu-interface)
