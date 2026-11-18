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
//     interrupt tests, which raise "NVIC IRQ 0": here BCM2837 Mailbox 1 of the raising core (dispatched by
//     the board's src/rtos/port_isr.cpp);
//   - uos_test_prologue(), run before the suite (portable-test-end.cpp):
//     CMSIS-RTOS v1 assumes one CPU, so the main thread is pinned to core 0.
//
// Carried over from the port's test/<board>/cmsis-os-validator/
// harness-suite.cpp, less the verdict, which portable-test-end.cpp prints.

#include <cstdint>

#include <cmsis-plus/rtos/os.h>

#include <bcm_irq.hpp>

typedef int IRQn_Type;

extern "C" uint32_t SystemCoreClock;
uint32_t SystemCoreClock = 1000000000;

extern "C" void
NVIC_EnableIRQ (IRQn_Type)
{
  for (unsigned c = 0; c < OS_NCPU; ++c)
    {
      // Clear any pending interrupt on Mailbox 1
      bcm::mmio_write (bcm::local::MBOX_RDCLR0 + 0x10u * c + 4u * 1, ~0u);
      // Enable Mailbox 1 IRQ delivery to this core (bit 1 of MBOX_IRQCNTL0)
      uint32_t ctl = bcm::mmio_read (bcm::local::MBOX_IRQCNTL0 + 4u * c);
      bcm::mmio_write (bcm::local::MBOX_IRQCNTL0 + 4u * c, ctl | (1u << 1));
    }
  bcm::dsb ();
}

extern "C" void
NVIC_DisableIRQ (IRQn_Type)
{
  for (unsigned c = 0; c < OS_NCPU; ++c)
    {
      // Disable Mailbox 1 IRQ delivery to this core (bit 1 of MBOX_IRQCNTL0)
      uint32_t ctl = bcm::mmio_read (bcm::local::MBOX_IRQCNTL0 + 4u * c);
      bcm::mmio_write (bcm::local::MBOX_IRQCNTL0 + 4u * c, ctl & ~(1u << 1));
    }
  bcm::dsb ();
}

extern "C" void
NVIC_SetPendingIRQ (IRQn_Type)
{
  unsigned c = bcm_irq::this_core ();
  bcm::mmio_write (bcm::local::MBOX_SET0 + 0x10u * c + 4u * 1, 1u);
  bcm::dsb ();
  bcm::sev ();
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
