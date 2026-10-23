# Shared SMP port declarations

`cmsis-plus/rtos/port/os-decls.h` here is the C++ half of the SMP port
contract: the stack/interrupt/scheduler type aliases, the kernel-lock and
ticket-lock structures, and the per-CPU arrays the SMP scheduler in
`src/rtos/os-core.cpp` expects a port to define.

It contains no machine instructions. Everything width-dependent reaches it
through `cmsis-plus/rtos/port/os-c-decls.h`, which each architecture project
supplies for itself.

Measured before it was put here: the rpi AArch32 and AArch64 ports carried
byte-identical copies, and the Cortex-A7 port's copy differed by one word --
it was missing `volatile` on `lock_state[]`, which is read and written by
several cores. The copy here is the `volatile` one.

It also declares `kernel_lock_state[OS_NCPU]` (2026-10-23), the per-core flag
of the kernel's own critical section (`scheduler::kernel_critical_section`). A
port defines and uses it only together with `OS_HAS_PORT_KERNEL_LOCK` in its
`os-c-decls.h` (the aarch64 port); a port without that macro leaves it
undefined, and the kernel's section falls back to the scheduler lock (the
AArch32 port).

## Using it

An architecture project that wants these declarations puts this directory on
its include path *instead of* writing its own `os-decls.h`:

    target_link_libraries (my-port INTERFACE micro-os-plus::port-smp-decls)

and supplies `cmsis-plus/rtos/port/os-c-decls.h` and
`cmsis-plus/rtos/port/os-inlines.h` from its own `include/`.

This is opt-in. A port with different requirements -- a single-CPU Cortex-M
build, or a POSIX port whose state types are not integers -- keeps its own
`os-decls.h` in its own `include/` and simply does not link this target.
Nothing here is on the default include path, so the two cannot be confused:
a port gets this file only by asking for it.
