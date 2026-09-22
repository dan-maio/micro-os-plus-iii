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
// Platform support for the harness tests on the AArch64 port.
//
// The port's own tests each supply their own startup hooks, their own main()
// and the newlib syscalls; the harness tests supply none of them. This file
// provides the same strong implementation the original micro-os-plus-iii
// harness relies on, adapted to AArch64:
//
//   * the two os_startup_initialize_hardware*() hooks called by startup.S;
//   * a strong main() that sets the interrupts stack (the kernel's weak main
//     does not, which leaves the port with a 0-byte IRQ stack and hangs the
//     scheduler), creates the main thread and starts the scheduler;
//   * a STRONG _Exit() that terminates through the port's AArch64 semihosting
//     (HLT #0xF000, x1 -> { reason, status }), which QEMU turns into a real
//     process exit code, so CTest sees pass/fail;
//   * the newlib syscalls the C library needs (printf -> _write,
//     gettimeofday -> _gettimeofday, ...), routing output through the port's
//     UART (mirrored to semihosting under SEMIHOST).
//
// The kernel's own semihosting groups are AArch32-only (SWI, r0/r1), so they
// are not used here.

#include <cmsis-plus/rtos/os.h>

#include <cstddef>
#include <cstdlib>

#include <sys/time.h>

#include <uart.hpp>
#include <exception_handler.hpp>

#if defined(SEMIHOST)
#include <semihosting.hpp>
#endif

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

  void
  os_startup_initialize_hardware (void)
  {
    uart::uart1.init ();

    os_startup_initialize_free_store (
        __heap_start,
        static_cast<std::size_t> (__heap_end - __heap_start));

    exception::init ();
  }

  // --------------------------------------------------------------------------
  // main(): the port's own tests each provide one; the kernel's weak main does
  // not set the interrupts stack, so we provide a strong one.

  [[noreturn]] static void
  harness_main_trampoline (void)
  {
    // The harness test contract is os_main(argc, argv). Without the kernel's
    // AArch32-only semihosting args layer, run with no arguments (as the
    // port's own tests do).
    int code = os_main (0, nullptr);
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

  // --------------------------------------------------------------------------
  // Strong semihosting exit. The kernel's _Exit() is weak and, on this
  // bare-metal port, would reset or idle; this strong definition ends the run
  // through the AArch64 semihosting SYS_EXIT, which QEMU maps to the process
  // exit code (0 on success), so CTest reports Passed.

  void
  _Exit (int code) __attribute__ ((noreturn));

  void
  _Exit (int code)
  {
#if defined(SEMIHOST)
    if (code == 0)
      {
        semihosting::exit_success ();
      }
    else
      {
        semihosting::exit_failure ();
      }
#else
    (void)code;
#endif
    for (;;)
      {
        // Never reached under SEMIHOST.
      }
  }

  // --------------------------------------------------------------------------
  // newlib syscalls.
  //
  // The port already provides _write, _read, _close, _lseek, _fstat and
  // _isatty (in test/boards/rpi-zero-2w/include/uart.hpp and src/handlers.cpp),
  // routing them to the UART / semihosting. Only _gettimeofday, which the
  // harness's mutex-stress uses and the port does not define, is added here.

  int
  _gettimeofday (struct timeval* tv, void*)
  {
    if (tv != nullptr)
      {
        tv->tv_sec = 0;
        tv->tv_usec = 0;
      }
    return 0;
  }
}
