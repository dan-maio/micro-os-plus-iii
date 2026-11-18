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

#ifndef PLATFORM_AARCH64_RPI3B_REFERENCE_CLOCK_H_
#define PLATFORM_AARCH64_RPI3B_REFERENCE_CLOCK_H_

#include <cstdint>

class reference_clock
{
public:
  static constexpr const char* name = "the BCM2837 System Timer (1 MHz)";

  // The System Timer's counter, CLO.
  static std::uint32_t
  now_us (void)
  {
    return *reinterpret_cast<volatile std::uint32_t*> (0x3F003004u);
  }

#if defined(HW_BUILD)
  // The board: real-time cores, a tenth of a tick.
  static constexpr std::uint32_t tolerance_us = 200;
  static constexpr std::uint64_t
  max_wake_gap (std::uint64_t cpt)
  {
    return cpt / 10;
  }
#else
  // QEMU: its cores are not real-time.
  static constexpr std::uint32_t tolerance_us = 20000;
  static constexpr std::uint64_t
  max_wake_gap (std::uint64_t cpt)
  {
    return 2 * cpt;
  }
#endif
};

#endif // PLATFORM_AARCH64_RPI3B_REFERENCE_CLOCK_H_
