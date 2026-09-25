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
//   * the newlib syscalls the C library needs (printf -> _write,
//     gettimeofday -> _gettimeofday, ...), routing output through the port's
//     UART (mirrored to semihosting under SEMIHOST). The strong semihosting
//     _Exit()/_exit() come from the port itself (src/handlers.cpp).
//
// The kernel's own semihosting groups are AArch32-only (SWI, r0/r1), so they
// are not used here.

#include <cmsis-plus/rtos/os.h>

#include <cstddef>
#include <cstdio>
#include <cstdlib>

#include <sys/time.h>

#include <uart.hpp>
#include <exception_handler.hpp>

// The port's SMP APIs. The kernel does not bring cores 1..3 up by itself on
// this port, so (as the port's own SMP tests do) the application must install
// one idle thread per core and then release each core. smp_install_boot_
// threads() is NOT defined here: the harness suite is built by the port's own
// builder, which already compiles test/<board>/src/test-smp-boot.cpp into
// every application. Reusing it keeps one copy of the bring-up, exactly as the
// port's tests share it.
#include <smp.hpp>

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

    setvbuf (stdout, nullptr, _IOLBF, 0);
  }

  // --------------------------------------------------------------------------
  // main(): the port's own tests each provide one; the kernel's weak main does
  // not set the interrupts stack, so we provide a strong one.

  [[noreturn]] static void
  harness_main_trampoline (void)
  {
    // Bring the other cores up, so the suite runs on all of them: install one
    // idle thread per core, then release cores 1..N-1 (each waits on its own
    // timer tick before the next is let go).
    smp_install_boot_threads ();
    smp::start_secondary_cores ();
    extern int test_wait_secondaries (int timeout_ms);
    test_wait_secondaries (3000);

    // The harness test contract is os_main(argc, argv); run with no arguments,
    // as the port's own tests do.
    //
    // The suite is linked with -Wl,--wrap=os_main (aarch64-rpi3b-harness-suite
    // in the port's tests.cmake), so this call lands in the wrapper, which runs
    // the suite and prints the RESULT line the other tests print on both
    // channels. On this SMP port the wrapper then stops the run with the
    // port's semihosting report_result(), not by returning here: std::exit()
    // runs the atexit handlers and C++ static destructors while the suite's
    // threads are still alive, which has been observed to block instead of
    // ending. The std::exit() below is only the fallback for a build without
    // SEMIHOST.
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
  // newlib syscalls.
  //
  // The port already provides _write, _read, _close, _lseek, _fstat, _isatty
  // and the strong semihosting _Exit()/_exit() (src/handlers.cpp), routing them
  // to the UART / semihosting. Only _gettimeofday, which the harness's
  // mutex-stress uses and the port does not define, is added here.

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
