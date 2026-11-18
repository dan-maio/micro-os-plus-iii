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
// Platform support on the host (the POSIX synthetic port), for the tests that
// supply no start-up of their own: the portable tests (tests/sources/) and the
// harness suites. The same contract as the silicon platforms' file:
//
//   * the two os_startup_initialize_hardware*() hooks;
//   * a main() that creates the main thread and starts the scheduler;
//   * the main thread's trampoline, which installs one idle thread per CPU,
//     releases the secondary "cores" (host threads) and waits for them, then
//     calls os_main().
//
// The heap (__heap_start/__heap_end) is the board's heap.cpp; the C library
// is the host's.

#include <cmsis-plus/rtos/os.h>

#include <cstddef>
#include <cstdio>
#include <cstdlib>

#include <uart.hpp>
#include <exception_handler.hpp>

// The port's SMP APIs. The kernel does not bring cores 1..3 up by itself on
// this port, so (as the port's own SMP tests do) the application must install
// one idle thread per core and then release each core. smp_install_boot_
// threads() is NOT defined here: the harness suite is built by the port's own
// builder, which already compiles test/<board>/src/test-smp-boot.cpp into
// every application. Reusing it keeps one copy of the bring-up, exactly as the
// port's tests share it.
#if defined(OS_USE_SMP_SCHEDULER)
#include <smp.hpp>
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
    // (Not in a 1-CPU image, e.g. upstream's suites built at OS_NCPU=1 to prove
    // the port's non-SMP branch: there is no other core.)
#if defined(OS_USE_SMP_SCHEDULER)
    smp_install_boot_threads ();
    smp::start_secondary_cores ();
    extern int test_wait_secondaries (int timeout_ms);
    test_wait_secondaries (3000);
#endif

    // The harness test contract is os_main(argc, argv); run with no arguments,
    // as the port's own tests do.
    //
    // The suite is linked with -Wl,--wrap=os_main (the portable tests: board-tests/), so this call lands in the wrapper, which runs
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
}
