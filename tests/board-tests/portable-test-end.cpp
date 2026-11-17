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
// The end of a portable test (tests/sources/<test>/).
//
// A portable test is os_main() and nothing else: it uses the µOS++ interfaces
// only and returns its verdict (0 = pass). The platform's start-up
// (platforms/<P>/src/platform-support.cpp) brings the board up, releases the
// secondary cores and calls os_main(); the test is linked with
// -Wl,--wrap=os_main, so that call lands here.
//
// This prints the RESULT line the runners look for and ends the run, the way
// the board tests always did: the console's puts() (mirrored to semihosting
// on SEMIHOST builds), then hw_result -- the semihosting SYS_EXIT on a
// SEMIHOST build, the process exit status on the host, nothing on a plain
// image, which then idles.

#include <cmsis-plus/rtos/os.h>

#include <uart.hpp>
#include <hw_result.hpp>

extern "C" int
__real_os_main (int argc, char* argv[]);

extern "C" int
__wrap_os_main (int argc, char* argv[]);

extern "C" int
__wrap_os_main (int argc, char* argv[])
{
  const int code = __real_os_main (argc, argv);

  // A single puts() is a single semihosted write: the line cannot be
  // interleaved with another core's output.
  uart::uart1.puts (code == 0 ? "\nRESULT: PASS\n" : "\nRESULT: FAIL\n");
  if (code == 0)
    {
      hw_result::ok ();
    }
  else
    {
      hw_result::fail ();
    }

  // Reached only on a plain image (no SEMIHOST): idle.
  for (;;)
    {
      os::rtos::sysclock.sleep_for (1000);
    }
}
