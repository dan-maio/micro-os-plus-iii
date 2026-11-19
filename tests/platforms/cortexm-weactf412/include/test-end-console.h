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
// How this board prints the RESULT line of an upstream suite on its console
// (board-tests/cortexm/test-end.cpp calls it, then writes the same line to
// semihosting). The suites print through semihosting and never bring the UART up.

#ifndef PLATFORM_CORTEXM_WEACTF412_TEST_END_CONSOLE_H_
#define PLATFORM_CORTEXM_WEACTF412_TEST_END_CONSOLE_H_

#include <uart.hpp>
#include <cmsis-plus/rtos/os.h>

inline void
uos_test_end_console (bool pass)
{
  uart::init (115200);
  uart::write (pass ? "\nRESULT: PASS\n" : "\nRESULT: FAIL\n");
  // DMA-driven: write() queues the line and returns (and adds the '\r'
  // itself); give the DMA the few milliseconds the line takes before
  // std::exit() stops the core.
  os::rtos::sysclock.sleep_for (20);
}

#endif // PLATFORM_CORTEXM_WEACTF412_TEST_END_CONSOLE_H_
