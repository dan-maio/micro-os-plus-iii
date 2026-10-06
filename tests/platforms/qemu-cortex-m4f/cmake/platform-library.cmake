# -----------------------------------------------------------------------------
# Platform library — µOS++ III Cortex-M4F on QEMU's generic Cortex-M machine.
#
# The library under test is the local Cortex-M port's GENERIC M4F core
# (micro-os-plus::cortexm-qemu-m4f), run single-core on the SMP kernel.
# -----------------------------------------------------------------------------

add_library (platform-qemu-cortex-m4f-interface INTERFACE EXCLUDE_FROM_ALL)

target_include_directories (platform-qemu-cortex-m4f-interface INTERFACE "include")

target_compile_definitions (
  platform-qemu-cortex-m4f-interface
  INTERFACE
    "${xpack_platform_compile_definition}"
    _POSIX_C_SOURCE=200809L
    # For S_IREAD
    _GNU_SOURCE
    # Single core: no OS_USE_SMP_SCHEDULER.
    OS_NCPU=1
)

target_link_libraries (
  platform-qemu-cortex-m4f-interface
  INTERFACE
    # The generic Cortex-M4F port (brings the kernel, micro-os-plus::iii).
    micro-os-plus::cortexm-qemu-m4f
    # CMSIS Cortex-M core headers (core_cm4.h).
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

add_library (micro-os-plus::platform ALIAS platform-qemu-cortex-m4f-interface)
