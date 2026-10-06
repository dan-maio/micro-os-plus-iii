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
// Platform support for the harness tests on the AArch32 port.
//
// The port's own tests each supply their own startup hooks and their own
// main(); the harness tests supply neither. This file provides them, mirroring
// the port's tests:
//
//   * the two os_startup_initialize_hardware*() hooks called by startup.S
//     (uart, free store, exception handlers);
//   * a main() that sets the interrupts stack (the kernel's weak main does
//     not, which leaves the port with a 0-byte IRQ stack and hangs the
//     scheduler), creates the main thread and starts the scheduler;
//   * the argc/argv the harness's main-with-arguments contract expects, via
//     os_startup_initialize_args().
//
// The C library and the exit procedure are NOT implemented here. They come
// from the kernel's optional groups, linked by the harness suite's INTERFACE
// target (aarch32-rpi3b-harness-suite, in the port's test/rpi3b/tests.cmake):
// micro-os-plus::iii-newlib-reent (the newlib reentrant syscalls) and
// micro-os-plus::iii-semihosting (the __posix_* layer and the strong
// _Exit(), which issues the semihosting SYS_EXIT). That is the same
// semihosting implementation the original micro-os-plus-iii harness uses, and
// it is what makes the CTest exit code real.

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

  extern void initialise_monitor_handles (void);

  void
  os_startup_initialize_hardware (void)
  {
    uart::uart1.init ();

    os_startup_initialize_free_store (
        __heap_start,
        static_cast<std::size_t> (__heap_end - __heap_start));

    exception::init ();

    initialise_monitor_handles ();

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
    // timer tick before the next is let go). LDREX/STREX is the port's lock.
    smp_install_boot_threads ();
    smp::start_secondary_cores ();
    extern int test_wait_secondaries (int timeout_ms);
    test_wait_secondaries (3000);

    // The harness test contract is os_main(argc, argv); run with no arguments,
    // as the AArch64 platform does. The AArch32 semihosting args layer would
    // ask the debugger for a command line (SYS_GET_CMDLINE) that a JTAG run
    // has no answer for.
    //
    // The suite is linked with -Wl,--wrap=os_main (aarch32-rpi3b-harness-suite
    // in the port's tests.cmake), so this call lands in the wrapper, which runs
    // the suite and prints the RESULT line the other tests print on both
    // channels. On this SMP port the wrapper then stops the run with the
    // port's semihosting report_result(), not by returning here: std::exit()
    // runs the atexit handlers and C++ static destructors while the suite's
    // threads are still alive, which has been observed to block instead of
    // ending. The std::exit() below is only the fallback for a build without
    // SEMIHOST; it is the strong semihosting _Exit()
    // (src/semihosting-exit.cpp) that gives QEMU the exit code CTest reads.
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

// ----------------------------------------------------------------------------
// Console mirror.
//
// newlib printf() goes to the kernel's semihosting __posix_write(), so without
// this the suites' output would reach only the debugger's semihosting console.
// The kernel calls the weak os_board_console_mirror() hook for stdout/stderr;
// write the same bytes to the board UART, so the output is also visible on the
// serial terminal. Always in addition to semihosting, never instead of it.
extern "C" void os_board_console_mirror (int fildes, const void* buf,
                                         std::size_t nbyte);
extern "C" void
os_board_console_mirror (int /* fildes */, const void* buf, std::size_t nbyte)
{
  // putc_uart(), not putc(): putc() also issues a semihosting SYS_WRITEC per
  // character, and the kernel has already sent this same stream to the
  // semihosting console. A second HLT per character floods the debugger and
  // stalls the core; the mirror only has to reach the UART.
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

// stdout would otherwise be fully buffered, surfacing only when the buffer
// fills or at exit -- too late for a suite the runner stops at the RESULT line.
// Line buffer it, so every printf() reaches the console as it is emitted.
namespace
{
  struct StdioLineBuffered
  {
    StdioLineBuffered ()
    {
      std::setvbuf (stdout, nullptr, _IOLBF, 0);
      std::setvbuf (stderr, nullptr, _IOLBF, 0);
    }
  };

  StdioLineBuffered stdio_line_buffered;
} // namespace
