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

/*
 * smp_test0 -- µOS++ scheduler and system tick.
 *
 * The scheduler runs a thread that sleeps on the system clock: ten
 * one-second heartbeats prove the 1 ms tick and the scheduler. (It was the
 * phase-1 bring-up of each board, with the secondary cores parked; the
 * platform now starts them, and this test does not use them.)

 * A portable test: os_main() only, the µOS++ interfaces only. The platform
 * brings the board and the secondary cores up before os_main() and prints the
 * RESULT line from its return value (board-tests/portable-test-end.cpp).
 */

#include <cmsis-plus/rtos/os.h>

#include <atomic>
#include <cstdint>
#include <cstdio>

// The port's "which CPU am I on", as the kernel itself uses it.
extern "C" unsigned port_cpu_id (void);

using namespace os::rtos;

int
os_main (int, char*[])
{
  std::printf ("smp_test0: scheduler + tick, os_main on core %u\n",
               port_cpu_id ());

  for (std::uint32_t beat = 0; beat < 10; ++beat)
    {
      std::printf ("[tick] heartbeat %u  sysclock=%u ms\n",
                   static_cast<unsigned> (beat),
                   static_cast<unsigned> (sysclock.now ()));
      sysclock.sleep_for (1000);
    }
  std::printf ("10 heartbeats on core %u\n", port_cpu_id ());
  return 0;
}
