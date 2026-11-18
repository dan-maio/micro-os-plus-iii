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
 * clock-test -- the kernel's clocks against the platform's reference clock.
 *
 * The reference is independent of the kernel's clocks: each platform says
 * what it is in its include/reference-clock.h (the BCM System Timer on the
 * Raspberry Pis, the raw generic-timer counter on the Luckfox Lyra, the
 * host's CLOCK_MONOTONIC on native), as blink-led.h does for blinky.
 *
 *   - 5000 ticks of sysclock, and hrclock over them, keep the reference's
 *     time;
 *   - hrclock.sleep_until (now () + 100 ms) lasts 100 ms (+1 tick) on core 0
 *     and on core 1;
 *   - the thread wakes promptly after core 0's tick on both cores
 *     (now () - steady_now () small).
 *
 * It guards the port faults fixed together: the tick re-armed one period
 * from now in its interrupt (the clocks lost the handler's latency every
 * tick); hrclock.now () counting from power-on while its sleeps count from
 * the tick's start; the frequency recalibrated by every core; and (kernel)
 * the cross-core IPI of thread::resume () never sent, so a thread made ready
 * for core 1 waited for core 1's own tick.
 *
 * One copy for the AArch boards and the host: it was a copy per board in the
 * architecture ports (test/<board>/), each with its own reference.
 *
 * A portable test: os_main () only, the µOS++ interfaces and the platform's
 * reference-clock.h. The platform brings the board and the secondary cores
 * up before os_main () and prints the RESULT line from its return value
 * (board-tests/portable-test-end.cpp).
 */

#include <cmsis-plus/rtos/os.h>

#include <reference-clock.h>

#include <cstdint>
#include <cstdio>

using namespace os::rtos;

namespace
{
  unsigned g_bad = 0;

  void
  check (bool c, const char* what)
  {
    std::printf ("  [%s] %s\n", c ? "ok" : "BAD", what);
    if (!c)
      {
        ++g_bad;
      }
  }

  struct probe
  {
    std::uint32_t sleep_us;
    clock::timestamp_t gap;
  };

  probe g_p1;

  void
  measure (probe& p)
  {
    const std::uint64_t f = hrclock.input_clock_frequency_hz ();
    hrclock.sleep_for (1);
    const std::uint32_t u = reference_clock::now_us ();
    hrclock.sleep_until (hrclock.now () + f / 10);
    p.sleep_us = reference_clock::now_us () - u;
    p.gap = hrclock.now () - hrclock.steady_now ();
  }

  void*
  on_core1 (void*)
  {
    measure (g_p1);
    return nullptr;
  }
} // namespace

int
os_main (int, char*[])
{
  const std::uint32_t tol = reference_clock::tolerance_us;
  const std::uint64_t f = hrclock.input_clock_frequency_hz ();
  const std::uint64_t cpt = port::clock_highres::cycles_per_tick ();
  std::printf ("clock-test: the kernel's clocks against %s\n",
               reference_clock::name);
  std::printf ("hrclock %lu Hz, cycles_per_tick %lu\n",
               static_cast<unsigned long> (f), static_cast<unsigned long> (cpt));

  // ---- 5000 ticks --------------------------------------------------------
  sysclock.sleep_for (1);
  const clock::timestamp_t s0 = sysclock.now ();
  const clock::timestamp_t h0 = hrclock.now ();
  const std::uint32_t u0 = reference_clock::now_us ();
  sysclock.sleep_for (5000);
  const std::uint32_t ref = reference_clock::now_us () - u0;
  const std::uint32_t hr
      = static_cast<std::uint32_t> ((hrclock.now () - h0) * 1000000u / f);
  std::printf ("5000 ticks: sysclock +%lu, reference %lu us, hrclock %lu us\n",
               static_cast<unsigned long> (sysclock.now () - s0),
               static_cast<unsigned long> (ref),
               static_cast<unsigned long> (hr));
  check (ref + tol >= 5000000 && ref <= 5000000 + tol,
         "the tick keeps the reference's time");
  check (hr + tol >= ref && ref + tol >= hr,
         "hrclock keeps the reference's time");

  // ---- 100 ms sleeps, and the wake, on cores 0 and 1 ---------------------
  probe p0;
  measure (p0);
  thread::attributes a = thread::initializer;
  a.th_stack_size_bytes = 8 * 1024;
  a.th_cpu_affinity = 1u << 1;
  thread* t = new thread ("core1", on_core1, nullptr, a);
  t->join ();
  delete t;
  for (unsigned c = 0; c < 2; ++c)
    {
      const probe& p = c == 0 ? p0 : g_p1;
      std::printf ("core %u: hrclock.sleep_until(now + 100 ms) %lu us, "
                   "now - steady_now %lu cycles\n",
                   c, static_cast<unsigned long> (p.sleep_us),
                   static_cast<unsigned long> (p.gap));
      check (p.sleep_us + tol >= 100000 && p.sleep_us <= 101000 + tol,
             c == 0 ? "hrclock sleep 100 ms (core 0)"
                    : "hrclock sleep 100 ms (core 1)");
      check (p.gap <= reference_clock::max_wake_gap (cpt),
             c == 0 ? "woken promptly after the tick (core 0)"
                    : "woken promptly after core 0's tick (core 1)");
    }

  std::printf ("clock-test: %s\n",
               g_bad == 0 ? "tick, hrclock and cross-core wake ok"
                          : "FAILED (see above)");
  return g_bad == 0 ? 0 : 1;
}
