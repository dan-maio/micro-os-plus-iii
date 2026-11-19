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
// semihosting). The suites print through semihosting and never bring the UART up; the
// board's driver is polled, so starting it here is enough for one line.

#ifndef PLATFORM_CORTEXM_WEACTF411_TEST_END_CONSOLE_H_
#define PLATFORM_CORTEXM_WEACTF411_TEST_END_CONSOLE_H_

#include <uart.hpp>

inline void
uos_test_end_console (bool pass)
{
  uart::init (115200);
  uart::write (pass ? "\r\nRESULT: PASS\r\n" : "\r\nRESULT: FAIL\r\n");
}

#endif // PLATFORM_CORTEXM_WEACTF411_TEST_END_CONSOLE_H_
