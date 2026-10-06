/*
 * This file is part of the µOS++ project (https://micro-os-plus.github.io/).
 * Copyright (c) 2026 Liviu Ionescu. All rights reserved.
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose is hereby granted, under the terms of the MIT license.
 *
 * If a copy of the license was not distributed with this file, it can be
 * obtained from https://opensource.org/licenses/mit.
 */

// ----------------------------------------------------------------------------
//
// Platform support for the HARNESS suites on the AArch32 port, Luckfox Lyra.
//
// The port's own board tests each supply their own startup hooks and their own
// main(); the harness suites supply neither. This file provides them, mirroring
// the port's tests:
//
//   * the two os_startup_initialize_hardware*() hooks called by startup.S
//     (uart, free store, exception handlers);
//   * a main() that sets the interrupts stack (the kernel's weak main does
//     not, which leaves the port with a 0-byte IRQ stack and hangs the
//     scheduler), creates the main thread and starts the scheduler.
//
// The C library and the exit procedure are NOT implemented here. They come
// from the kernel's optional groups, linked by cmake/platform-library.cmake on
// the support library: micro-os-plus::iii-newlib-reent (the newlib reentrant
// syscalls) and micro-os-plus::iii-semihosting (the __posix_* layer). The
// port's own strong _Exit() (src/semihosting-exit.cpp) then terminates the run
// through the port's semihosting -- SVC 0x123456, the cortex_a Angel trap.
//
// HARDWARE VERDICT. A hardware run has no process status to compare: OpenOCD
// is a debugger, not a parent. So before exiting, the trampoline prints the
// "RESULT: PASS|FAIL" line the runner greps, exactly like the port's own board
// tests. (Under QEMU the same code would just return the exit code.)

#include <cmsis-plus/rtos/os.h>

#include <cstddef>
#include <cstdio>
#include <cstdlib>

#include <uart.hpp>
#include <exception_handler.hpp>
#include <smp.hpp>

// ----------------------------------------------------------------------------

extern "C"
{
  extern char __heap_start[];
  extern char __heap_end[];
  extern char __fiq_stack_top[];
  extern char __irq_stack_top[];

  extern void os_startup_create_thread_idle (void);
  extern os::rtos::thread* os_main_thread;

  // --------------------------------------------------------------------------
  // Startup hooks, called by startup.S before main().

  void
  os_startup_initialize_hardware_early (void)
  {
  }

  extern void initialise_monitor_handles (void);

  void
  os_startup_initialize_hardware (void)
  {
    uart::uart1.init ();

    os_startup_initialize_free_store (
        __heap_start,
        static_cast<std::size_t> (__heap_end - __heap_start));

    exception::init ();

    // Open the semihosting standard file descriptors (":tt"). WITHOUT this the
    // semihosting fd table is empty, so the C library's _write() finds no slot
    // for fd 1 and EVERY printf() in the harness suites is silently discarded
    // -- the kernel's own unbuffered trace still shows, which makes it look
    // like a buffering problem when it is not. The AArch32 Pi sibling calls it
    // here too; the suites then run with no arguments (see
    // harness_main_trampoline()).
    initialise_monitor_handles ();

    // Line-buffer stdout so the suites' printf output reaches the semihosting
    // channel line by line, as it does under QEMU. Without this, stdout could
    // be fully buffered and the output would only appear when the buffer
    // fills.
    //
    // This must come AFTER the free store: setvbuf() allocates the stdout
    // buffer, and before os_startup_initialize_free_store() there is no heap,
    // so the allocation throws bad_alloc().
    setvbuf (stdout, nullptr, _IOLBF, 0);
  }

  // --------------------------------------------------------------------------
  // main(): the port's own tests each provide one; the kernel's weak main does
  // not set the interrupts stack, so we provide a strong one.

  [[noreturn]] static void
  harness_main_trampoline (void)
  {
    // Bring up secondary cores so the suite runs across all cores on SMP.
    smp_install_boot_threads ();
    smp::start_secondary_cores ();
    extern int test_wait_secondaries (int timeout_ms);
    test_wait_secondaries (3000);

    // Run with no arguments, as the AArch32/AArch64 Pi siblings do.
    // initialise_monitor_handles() has already opened the semihosting fds
    // (see os_startup_initialize_hardware()); the AArch32 semihosting args
    // layer would instead ask the debugger for a command line
    // (SYS_GET_CMDLINE) that a JTAG run has no answer for. The suites default
    // their parameters when argc <= 1.
    int code = os_main (0, nullptr);

    // The verdict, then the stop. OpenOCD has no process status, so this line
    // is the result; std::exit() -> the port's strong _Exit() -> SYS_EXIT.
    uart::uart1 << (code == 0 ? "\nRESULT: PASS\n" : "\nRESULT: FAIL\n");
    uart::uart1.flush ();

    std::exit (code);
  }

  int
  main (int, char*[])
  {
    using namespace os::rtos;

#if defined(OS_HAS_INTERRUPTS_STACK)
    interrupts::stack ()->set (
        reinterpret_cast<thread::stack::element_t*> (__fiq_stack_top),
        __irq_stack_top - __fiq_stack_top);
    interrupts::stack ()->initialize ();
#endif

    scheduler::initialize ();

    static thread::stack::element_t main_stack[8192];
    thread::attributes attr = thread::initializer;
    attr.th_stack_address = main_stack;
    attr.th_stack_size_bytes = sizeof (main_stack);

    static thread main_thread{
      "main", reinterpret_cast<thread::func_t> (harness_main_trampoline),
      nullptr, attr
    };
    os_main_thread = &main_thread;

    os_startup_create_thread_idle ();
    scheduler::start ();

    return 0;
  }
}

// ----------------------------------------------------------------------------
// Console mirror.
extern "C" void os_board_console_mirror (int fildes, const void* buf,
                                         std::size_t nbyte);
extern "C" void
os_board_console_mirror (int /* fildes */, const void* buf, std::size_t nbyte)
{
  const char* cbuf = static_cast<const char*> (buf);
  for (std::size_t i = 0; i < nbyte; ++i)
    {
      if (cbuf[i] == '\n')
        {
          uart::uart1.putc_uart ('\r');
        }
      uart::uart1.putc_uart (cbuf[i]);
    }
}
