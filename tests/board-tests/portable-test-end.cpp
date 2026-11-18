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
// This prints the RESULT line the runners look for and ends the run: on the
// board's UART, then, on a SEMIHOST build, semihosting::report_result (),
// which writes the same line to the semihosting console (what the runners
// read) and stops the run with SYS_EXIT. On the host, hw_result gives the
// process exit status; a plain image idles. The verdict reaches semihosting
// even when the board keeps its console on the UART (UOS_CONSOLE_UART_ONLY:
// on a probe where every semihosting call is slow, the Luckfox Lyra's).

#include <cmsis-plus/rtos/os.h>

#include <cstdio>

#include <uart.hpp>
#include <hw_result.hpp>
#if defined(SEMIHOST)
#include <semihosting.hpp>
#endif

extern "C" int
__real_os_main (int argc, char* argv[]);

extern "C" int
__wrap_os_main (int argc, char* argv[]);

// A test that uses the SD card (UOS_TESTS_STORAGE) links
// portable-test-storage.cpp, which mounts the card at /sd/ before the test
// runs; for the others this stays undefined.
extern "C" void
uos_test_storage_start (void) __attribute__ ((weak));

// What a test needs from the platform right before it runs: the platform's
// support file for that test defines it (cmsis-os-validator pins the main
// thread to core 0); for the others this stays undefined.
extern "C" void
uos_test_prologue (void) __attribute__ ((weak));

extern "C" int
__wrap_os_main (int argc, char* argv[])
{
  if (uos_test_storage_start != nullptr)
    {
      uos_test_storage_start ();
    }
  if (uos_test_prologue != nullptr)
    {
      uos_test_prologue ();
    }

  const int code = __real_os_main (argc, argv);

  // The test printed through the C library (printf); its buffered output
  // must reach the console before the run ends.
  std::fflush (nullptr);

  uart::uart1.puts_uart (code == 0 ? "\nRESULT: PASS\n" : "\nRESULT: FAIL\n");
#if defined(SEMIHOST)
  // One semihosted write of the whole line, then SYS_EXIT.
  semihosting::report_result (code == 0);
#else
  if (code == 0)
    {
      hw_result::ok ();
    }
  else
    {
      hw_result::fail ();
    }
#endif

  // Reached only on a plain image (no SEMIHOST): idle.
  for (;;)
    {
      os::rtos::sysclock.sleep_for (1000);
    }
}
