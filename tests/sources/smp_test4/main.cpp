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
 * smp_test4 -- µOS++ no-affinity load balancing.
 *
 * Eight workers with no CPU affinity burn CPU and yield; a reporter on core
 * 0 prints, per worker, on which cores it ran. The run passes if the work
 * reached every core (which also proves every core joined).

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

static constexpr unsigned NWORK = 8;
static mutex g_con{ "con" }; // stdout is one stream for all cores
static std::atomic<std::uint32_t> hist[NWORK][OS_NCPU]{};
static std::atomic<bool> g_running{ true };

static void*
worker (void* arg)
{
  const unsigned id = static_cast<unsigned> (reinterpret_cast<std::uintptr_t> (arg));
  while (g_running)
    {
      const unsigned c = port_cpu_id ();
      if (c < OS_NCPU)
        {
          hist[id][c]++;
        }
      // Burn a little CPU, so the scheduler has something to migrate.
      volatile std::uint32_t x = 0;
      for (std::uint32_t i = 0; i < 200000; ++i)
        {
          x = x + i;
        }
      (void)x;
      this_thread::yield ();
    }
  return nullptr;
}

static void*
reporter (void*)
{
  while (g_running)
    {
      g_con.lock ();
      if (g_running)
        {
          for (unsigned w = 0; w < NWORK; ++w)
            {
              std::printf ("w%u [", w);
              for (unsigned c = 0; c < OS_NCPU; ++c)
                {
                  std::printf (" c%u=%u", c, hist[w][c].load ());
                }
              std::printf (" ]\n");
            }
          std::printf ("-- reporter on c%u t=%u ms --\n", port_cpu_id (),
                       static_cast<unsigned> (sysclock.now ()));
        }
      g_con.unlock ();
      sysclock.sleep_for (1000);
    }
  return nullptr;
}

static thread::stack::element_t wstk[NWORK][4096];
static thread::stack::element_t rstk[4096];

int
os_main (int, char*[])
{
  std::printf ("smp_test4: %u workers, no affinity, on %u cores\n", NWORK,
               static_cast<unsigned> (OS_NCPU));

  thread::attributes a = thread::initializer;
  static thread* workers[NWORK];
  static char wn[NWORK][4];
  for (unsigned w = 0; w < NWORK; ++w)
    {
      wn[w][0] = 'w';
      wn[w][1] = static_cast<char> ('0' + w);
      wn[w][2] = '\0';
      a.th_stack_address = wstk[w];
      a.th_stack_size_bytes = sizeof (wstk[w]);
      // No cpu_affinity(): the scheduler balances the load.
      workers[w] = new thread (wn[w], worker,
                               reinterpret_cast<void*> (static_cast<std::uintptr_t> (w)), a);
    }
  a.th_stack_address = rstk;
  a.th_stack_size_bytes = sizeof (rstk);
  static thread t_rep{ "reporter", reporter, nullptr, a };
  t_rep.cpu_affinity (1u << 0); // keep the console on core 0

  for (std::uint32_t beats = 0; beats < 10; ++beats)
    {
      sysclock.sleep_for (1000);
    }

  // The load must have reached every core.
  bool ok = true;
  for (unsigned c = 0; c < OS_NCPU; ++c)
    {
      std::uint32_t tot = 0;
      for (unsigned w = 0; w < NWORK; ++w)
        {
          tot += hist[w][c];
        }
      if (tot == 0)
        {
          ok = false;
        }
    }

  // Stop the threads before the verdict, and give them time to leave.
  g_running = false;
  sysclock.sleep_for (50);
  return ok ? 0 : 1;
}
