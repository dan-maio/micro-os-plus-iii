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
// What upstream's cmsis-os-validator (tests/sources/cmsis-os-validator)
// needs from this platform, compiled into that suite only (board-tests/,
// UOS_TESTS_SUITES):
//
//   - the CMSIS core symbols a Cortex-M device would have: SystemCoreClock,
//     and NVIC_EnableIRQ/DisableIRQ/SetPendingIRQ for the validator's
//     interrupt tests, which raise "NVIC IRQ 0": here a GIC-400 SGI 1 to the raising core (dispatched by the board's
//     src/rtos/port_isr.cpp);
//   - uos_test_prologue(), run before the suite (portable-test-end.cpp):
//     CMSIS-RTOS v1 assumes one CPU, so the main thread is pinned to core 0.
//
// Carried over from the port's test/<board>/cmsis-os-validator/
// harness-suite.cpp, less the verdict, which portable-test-end.cpp prints.

#include <cstdint>

#include <cmsis-plus/rtos/os.h>

#include <gic400.hpp>

typedef int IRQn_Type;

extern "C" uint32_t SystemCoreClock;
uint32_t SystemCoreClock = 1500000000;

// Shared with rtos/port_isr.cpp (UOS_CMSIS_OS_VALIDATOR builds only).
extern "C" volatile bool uos_validator_irq_enabled;
extern "C" volatile bool uos_validator_irq_pending;
volatile bool uos_validator_irq_enabled = false;
volatile bool uos_validator_irq_pending = false;

extern "C" void
NVIC_EnableIRQ (IRQn_Type)
{
  uos_validator_irq_enabled = true;
  __asm__ volatile("dmb ish" ::: "memory");
  if (uos_validator_irq_pending)
    {
      uos_validator_irq_pending = false;
      gic::send_sgi (1u, gic::this_core ());
    }
}

extern "C" void
NVIC_DisableIRQ (IRQn_Type)
{
  uos_validator_irq_enabled = false;
  __asm__ volatile("dmb ish" ::: "memory");
}

extern "C" void
NVIC_SetPendingIRQ (IRQn_Type)
{
  gic::send_sgi (1u, gic::this_core ());
}

extern "C" void
uos_test_prologue (void);

extern "C" void
uos_test_prologue (void)
{
  // CMSIS-RTOS v1 assumes one CPU: a thread of higher priority preempts its
  // creator at once. The kernel's CMSIS wrapper pins every thread it creates
  // to core 0 (os-c-wrapper.cpp, osThreadCreate); the main thread, which runs
  // the validator, is not created there, so pin it too, and yield so that the
  // scheduler moves it to core 0 before the first test. Without it the main
  // thread keeps running on another core in parallel with the threads it has
  // just created (TC_ThreadGetId fails, TC_ThreadPriority hangs).
  os::rtos::this_thread::thread ().cpu_affinity (1u << 0);
  os::rtos::this_thread::yield ();
}
