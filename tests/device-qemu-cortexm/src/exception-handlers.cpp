/*
 * This file is part of the µOS++ project (https://micro-os-plus.github.io/).
 * Copyright (c) 2023-2025 Liviu Ionescu. All rights reserved.
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose is hereby granted, under the terms of the MIT license.
 *
 * If a copy of the license was not distributed with this file, it can be
 * obtained from https://opensource.org/licenses/mit.
 */

// ----------------------------------------------------------------------------

#if defined(OS_USE_OS_APP_CONFIG_H)
#include <cmsis-plus/os-app-config.h>
#endif

#include <cmsis-plus/cortexm/exception-handlers.h>
#include <cmsis-plus/rtos/os-c-decls.h>

// The SMP Cortex-M33 port provides its own, per-core SysTick handler (only
// core 0 may advance the RTOS clock); compiling this one in as well would be a
// duplicate definition.
#if !defined(OS_USE_SMP_SCHEDULER)
void __attribute__ ((section (".after_vectors")))
SysTick_Handler (void)
{
  // DO NOT loop, just return.
  // Useful in case someone (like STM HAL) always enables SysTick.

  os_systick_handler ();
}
#endif

// ----------------------------------------------------------------------------
