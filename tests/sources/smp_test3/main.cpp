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
 * smp_test3 -- µOS++ message_queue producer/consumer across cores.
 *
 * A producer on core 0 sends numbers through a message queue to a consumer
 * on core 1, which classifies them (prime/composite); a logger on core 2
 * prints the counts once per second. The run passes if numbers were consumed
 * and each thread ran on the core it was pinned to. The core numbers wrap
 * modulo OS_NCPU.

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

// A slot of at least sizeof(void*): AArch64 needs it.
static message_queue g_mq{ "mq", 8, sizeof (void*) };
static mutex g_print{ "print" }; // stdout is one stream for all cores
static std::atomic<std::uint32_t> g_produced{ 0 }, g_consumed{ 0 }, g_primes{ 0 };
static std::atomic<int> g_prod_core{ -1 }, g_cons_core{ -1 }, g_log_core{ -1 };
static std::atomic<bool> g_running{ true };

static constexpr unsigned PROD_CORE = 0;
static constexpr unsigned CONS_CORE = 1 % OS_NCPU;
static constexpr unsigned LOG_CORE = 2 % OS_NCPU;

static bool
is_prime (std::uint32_t n)
{
  if (n < 2)
    {
      return false;
    }
  for (std::uint32_t i = 2; i * i <= n; ++i)
    {
      if (n % i == 0)
        {
          return false;
        }
    }
  return true;
}

static void*
producer (void*)
{
  std::uint32_t v = 2;
  while (g_running)
    {
      g_prod_core = static_cast<int> (port_cpu_id ());
      g_mq.send (&v, sizeof (v), 0);
      ++g_produced;
      ++v;
      sysclock.sleep_for (20);
    }
  return nullptr;
}

static void*
consumer (void*)
{
  std::uint32_t v;
  while (g_running)
    {
      if (g_mq.receive (&v, sizeof (v), nullptr) == result::ok)
        {
          g_cons_core = static_cast<int> (port_cpu_id ());
          ++g_consumed;
          const bool p = is_prime (v);
          if (p)
            {
              ++g_primes;
            }
          g_print.lock ();
          if (g_running)
            {
              std::printf ("[c%u] recv %u %s\n", port_cpu_id (),
                           static_cast<unsigned> (v),
                           p ? "PRIME" : "composite");
            }
          g_print.unlock ();
        }
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
          std::printf ("[c%u] produced=%u consumed=%u primes=%u t=%u ms\n",
                       port_cpu_id (), g_produced.load (), g_consumed.load (),
                       g_primes.load (),
                       static_cast<unsigned> (sysclock.now ()));
        }
      g_print.unlock ();
      sysclock.sleep_for (1000);
    }
  return nullptr;
}

static thread::stack::element_t s_prod[4096], s_cons[4096], s_log[4096];

int
os_main (int, char*[])
{
  std::printf ("smp_test3: message_queue producer/consumer on %u cores\n",
               static_cast<unsigned> (OS_NCPU));

  thread::attributes a = thread::initializer;
  a.th_stack_address = s_prod;
  a.th_stack_size_bytes = sizeof (s_prod);
  static thread t_prod{ "producer", producer, nullptr, a };
  a.th_stack_address = s_cons;
  a.th_stack_size_bytes = sizeof (s_cons);
  static thread t_cons{ "consumer", consumer, nullptr, a };
  a.th_stack_address = s_log;
  a.th_stack_size_bytes = sizeof (s_log);
  static thread t_log{ "logger", logger, nullptr, a };
  t_prod.cpu_affinity (1u << PROD_CORE);
  t_cons.cpu_affinity (1u << CONS_CORE);
  t_log.cpu_affinity (1u << LOG_CORE);

  for (unsigned b = 0; b < 10; ++b)
    {
      sysclock.sleep_for (1000);
    }

  const bool ok = (g_consumed > 0)
                  && (g_prod_core == static_cast<int> (PROD_CORE))
                  && (g_cons_core == static_cast<int> (CONS_CORE))
                  && (g_log_core == static_cast<int> (LOG_CORE));

  // Stop the threads before the verdict, and give them time to leave.
  g_running = false;
  sysclock.sleep_for (50);

  g_print.lock ();
  std::printf ("produced=%u consumed=%u primes=%u; producer on c%d (want "
               "c%u), consumer on c%d (want c%u), logger on c%d (want c%u)\n",
               g_produced.load (), g_consumed.load (), g_primes.load (),
               g_prod_core.load (), PROD_CORE, g_cons_core.load (), CONS_CORE,
               g_log_core.load (), LOG_CORE);
  g_print.unlock ();
  return ok ? 0 : 1;
}
