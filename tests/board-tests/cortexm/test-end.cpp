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
// The end of an upstream suite (tests/sources/<suite>/) on a Cortex-M board:
// one copy for every Cortex-M platform (it was each board's harness-suite.hpp).
//
// A suite RETURNS its code from os_main(); the hardware runner reads a RESULT
// line. The suite is linked with -Wl,--wrap=os_main (the builder's
// <platform>-test-startup), so the kernel's call to os_main() lands here: run
// the suite, print the line on the board's console (the platform's
// test-end-console.h) and on semihosting, which is what the runner reads
// through OpenOCD, then hand the code back to the kernel, whose std::exit() is
// the semihosting SYS_EXIT that ends the run.

#include <debug-host.h>
#include <test-end-console.h>

namespace
{
  void
  semi_write0 (const char* s)
  {
    if (!uos_debug_host_attached ()) // OpenOCD gone: see debug-host.h
      {
        return;
      }
    register unsigned r0 __asm__ ("r0") = 0x04u; // SYS_WRITE0
    register const char* r1 __asm__ ("r1") = s;
    __asm__ volatile ("bkpt 0xAB"
                      :
                      : "r"(r0), "r"(r1)
                      : "r2", "r3", "ip", "lr", "memory", "cc");
  }
} // namespace

extern "C" int
__real_os_main (int argc, char* argv[]);

extern "C" int
__wrap_os_main (int argc, char* argv[]);

extern "C" int
__wrap_os_main (int argc, char* argv[])
{
  int code = __real_os_main (argc, argv);

  uos_test_end_console (code == 0);
  semi_write0 (code == 0 ? "RESULT: PASS\n" : "RESULT: FAIL\n");
  return code;
}
