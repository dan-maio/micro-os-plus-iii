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

// The platform's reference clock, for tests/sources/clock-test: a time
// source independent of the kernel's clocks (sysclock, hrclock), which the
// test measures them against. As blink-led.h for blinky, each platform has
// its own; the test includes it by name.
//
//   reference_clock::now_us ()          microseconds, free running (wraps)
//   reference_clock::name               what the reference is
//   reference_clock::tolerance_us       the error a measurement may have
//   reference_clock::max_wake_gap (cpt) how late a woken thread may run,
//                                       in hrclock cycles (cpt: cycles per
//                                       tick)

#ifndef PLATFORM_NATIVE_REFERENCE_CLOCK_H_
#define PLATFORM_NATIVE_REFERENCE_CLOCK_H_

#include <cstdint>

#include <time.h>

class reference_clock
{
public:
  static constexpr const char* name = "the host's CLOCK_MONOTONIC";

  static std::uint32_t
  now_us (void)
  {
    timespec tp;
    ::clock_gettime (CLOCK_MONOTONIC, &tp);
    return static_cast<std::uint32_t> (
        static_cast<std::uint64_t> (tp.tv_sec) * 1000000u
        + static_cast<std::uint64_t> (tp.tv_nsec) / 1000u);
  }

  // A host is not real-time: its threads may wait for the host's scheduler.
  // The wake: 5 ms of hrclock (1 MHz), what the native test always allowed;
  // not counted in ticks, as the POSIX port's cycles_per_tick is not the
  // tick period in hrclock cycles.
  static constexpr std::uint32_t tolerance_us = 20000;
  static constexpr std::uint64_t
  max_wake_gap (std::uint64_t)
  {
    return 5000;
  }
};

#endif // PLATFORM_NATIVE_REFERENCE_CLOCK_H_
