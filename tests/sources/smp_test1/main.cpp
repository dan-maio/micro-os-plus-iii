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
 * smp_test1 -- µOS++ semaphore ping-pong across cores.
 *
 * Two threads bounce a token back and forth through two binary semaphores,
 * the pinger pinned to core 0 and the ponger to core 1; a logger on core 2
 * prints the round count once per second. The run passes if the token went
 * round and each thread ran on the core it was pinned to (which also proves
 * those cores joined). The core numbers wrap modulo OS_NCPU.

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

static semaphore_binary g_ping{ "ping", 1 }; // starts signalled
static semaphore_binary g_pong{ "pong", 0 };
static mutex g_print{ "print" }; // stdout is one stream for all cores
static std::atomic<std::uint32_t> g_rounds{ 0 };
static std::atomic<int> g_ping_core{ -1 }, g_pong_core{ -1 }, g_log_core{ -1 };
static std::atomic<bool> g_running{ true };

static constexpr unsigned PING_CORE = 0;
static constexpr unsigned PONG_CORE = 1 % OS_NCPU;
static constexpr unsigned LOG_CORE = 2 % OS_NCPU;

static void*
pinger (void*)
{
  while (g_running)
    {
      g_ping.wait ();
      if (!g_running)
        {
          break;
        }
      g_ping_core = static_cast<int> (port_cpu_id ());
      ++g_rounds;
      g_pong.post ();
    }
  return nullptr;
}

static void*
ponger (void*)
{
  while (g_running)
    {
      g_pong.wait ();
      if (!g_running)
        {
          break;
        }
      g_pong_core = static_cast<int> (port_cpu_id ());
      g_ping.post ();
    }
  return nullptr;
}

static void*
logger (void*)
{
  while (g_running)
    {
      g_log_core = static_cast<int> (port_cpu_id ());
      g_print.lock ();
      if (g_running)
        {
          std::printf ("[c%u] rounds=%u  ping@c%d pong@c%d  t=%u ms\n",
                       port_cpu_id (), g_rounds.load (), g_ping_core.load (),
                       g_pong_core.load (),
                       static_cast<unsigned> (sysclock.now ()));
        }
      g_print.unlock ();
      sysclock.sleep_for (1000);
    }
  return nullptr;
}

static thread::stack::element_t s_ping[4096], s_pong[4096], s_log[4096];

int
os_main (int, char*[])
{
  std::printf ("smp_test1: semaphore ping-pong on %u cores\n",
               static_cast<unsigned> (OS_NCPU));

  thread::attributes a = thread::initializer;
  a.th_stack_address = s_ping;
  a.th_stack_size_bytes = sizeof (s_ping);
  static thread t_ping{ "ping", pinger, nullptr, a };
  a.th_stack_address = s_pong;
  a.th_stack_size_bytes = sizeof (s_pong);
  static thread t_pong{ "pong", ponger, nullptr, a };
  a.th_stack_address = s_log;
  a.th_stack_size_bytes = sizeof (s_log);
  static thread t_log{ "logger", logger, nullptr, a };
  t_ping.cpu_affinity (1u << PING_CORE);
  t_pong.cpu_affinity (1u << PONG_CORE);
  t_log.cpu_affinity (1u << LOG_CORE);

  for (std::uint32_t beats = 0; beats < 10; ++beats)
    {
      sysclock.sleep_for (1000);
    }

  const bool ok = (g_rounds > 0)
                  && (g_ping_core == static_cast<int> (PING_CORE))
                  && (g_pong_core == static_cast<int> (PONG_CORE))
                  && (g_log_core == static_cast<int> (LOG_CORE));

  // Stop the threads before the verdict, and give them time to leave.
  g_running = false;
  g_ping.post ();
  g_pong.post ();
  sysclock.sleep_for (50);

  g_print.lock ();
  std::printf ("rounds=%u, ping on c%d (want c%u), pong on c%d (want c%u), "
               "logger on c%d (want c%u)\n",
               g_rounds.load (), g_ping_core.load (), PING_CORE,
               g_pong_core.load (), PONG_CORE, g_log_core.load (), LOG_CORE);
  g_print.unlock ();
  return ok ? 0 : 1;
}
