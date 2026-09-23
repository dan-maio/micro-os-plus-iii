# -----------------------------------------------------------------------------
# Platform library — µOS++ III Cortex-M33 SMP on QEMU mps2-an521.
#
# The generic M33 port core auto-launches core 1 and registers its idle thread,
# so linking this platform is enough to bring up both cores.
# -----------------------------------------------------------------------------

add_library (platform-2xcortex-m33-interface INTERFACE EXCLUDE_FROM_ALL)

target_include_directories (platform-2xcortex-m33-interface INTERFACE "include")

target_compile_definitions (
  platform-2xcortex-m33-interface
  INTERFACE
    "${xpack_platform_compile_definition}"
    _POSIX_C_SOURCE=200809L
    # For S_IREAD
    _GNU_SOURCE
    # Dual core SMP.
    OS_NCPU=2
    OS_USE_SMP_SCHEDULER=1
)

target_link_libraries (
  platform-2xcortex-m33-interface
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

add_library (micro-os-plus::platform ALIAS platform-2xcortex-m33-interface)
