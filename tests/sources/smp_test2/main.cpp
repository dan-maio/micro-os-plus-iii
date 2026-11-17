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
 * smp_test2 -- µOS++ lock coherency across all cores.
 *
 * One worker per core, pinned to it, increments a shared counter under a
 * mutex ITER times; the total must be exactly ITER x OS_NCPU. A lost update
 * means the mutex does not serialise across cores.
 *
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

static constexpr std::uint32_t ITER = 2000;
static volatile std::uint32_t g_prog[OS_NCPU] = {};

// Serialises the counter and, as stdout is one stream for all cores, every
// line printed while the workers run.
static mutex g_mutex{ "cnt" };
static volatile std::uint32_t g_counter = 0;
static std::atomic<std::uint32_t> g_done{ 0 };

static void*
worker (void*)
{
  for (std::uint32_t i = 0; i < ITER; ++i)
    {
      g_mutex.lock ();
      std::uint32_t v = g_counter;
      __asm__ volatile("" ::: "memory");
      g_counter = v + 1; // read-modify-write under the lock
      g_mutex.unlock ();
      const unsigned me = port_cpu_id ();
      if (me < OS_NCPU)
        {
          g_prog[me] = i;
        }
      if ((i & 0x7F) == 0)
        {
          this_thread::yield ();
        }
    }
  g_mutex.lock ();
  std::printf ("[c%u] worker done, counter=%u\n", port_cpu_id (),
               static_cast<unsigned> (g_counter));
  ++g_done;
  g_mutex.unlock ();
  return nullptr;
}

static thread::stack::element_t wstack[OS_NCPU][4096];

int
os_main (int, char*[])
{
  std::printf ("smp_test2: %u-core lock coherency, os_main on core %u\n",
               static_cast<unsigned> (OS_NCPU), port_cpu_id ());

  thread::attributes attr = thread::initializer;
  static thread* workers[OS_NCPU];
  // Names must outlive the thread, and there is one per CPU, so they are
  // generated rather than listed.
  static char wn[OS_NCPU][4];
  for (unsigned c = 0; c < OS_NCPU; ++c)
    {
      wn[c][0] = 'w';
      wn[c][1] = static_cast<char> ('0' + c);
      wn[c][2] = '\0';
      attr.th_stack_address = wstack[c];
      attr.th_stack_size_bytes = sizeof (wstack[c]);
      workers[c] = new thread (wn[c], worker, nullptr, attr);
      workers[c]->cpu_affinity (1u << c);
    }

  while (g_done < OS_NCPU)
    {
      sysclock.sleep_for (500);
      g_mutex.lock ();
      std::printf ("progress:");
      for (unsigned c = 0; c < OS_NCPU; ++c)
        {
          std::printf (" %s=%u", wn[c], static_cast<unsigned> (g_prog[c]));
        }
      std::printf (" done=%u counter=%u\n", g_done.load (),
                   static_cast<unsigned> (g_counter));
      g_mutex.unlock ();
    }

  const std::uint32_t expected = ITER * OS_NCPU;
  const bool ok = (g_counter == expected);
  std::printf ("counter = %u  expected = %u: %s\n",
               static_cast<unsigned> (g_counter),
               static_cast<unsigned> (expected),
               ok ? "lock coherent across all cores" : "LOST UPDATES");
  return ok ? 0 : 1;
}
