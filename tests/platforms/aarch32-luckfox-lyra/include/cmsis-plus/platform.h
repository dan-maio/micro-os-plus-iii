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

#ifndef PLATFORM_AARCH32_LUCKFOX_LYRA_PLATFORM_H_
#define PLATFORM_AARCH32_LUCKFOX_LYRA_PLATFORM_H_

// ----------------------------------------------------------------------------

// The AArch32 port supplies the platform specifics through its own headers
// (uart.hpp, led.hpp, smp.hpp, timer_arm.hpp, ...). This header exists only
// to satisfy the <cmsis-plus/platform.h> include from a test's
// os-app-config.h.

// Enable the kernel's semihosting syscalls (c-syscalls-semihosting.cpp), which
// provide the newlib __posix_* layer the HARNESS suites need (printf,
// gettimeofday, ...). The port's own board tests do not include this header and
// link only the base platform, so they are unaffected; and the port's strong
// _Exit() (src/semihosting-exit.cpp) still owns the exit procedure.
#define OS_USE_SEMIHOSTING_SYSCALLS

// The AArch32 port carries no CMSIS core headers, but the kernel's semihosting
// os_terminate() calls __disable_irq(). Provide it here (the test's
// os-app-config.h includes this header before the semihosting layer is
// compiled).
#if defined(__arm__) && !defined(__disable_irq)
static inline void
__disable_irq (void)
{
  __asm__ volatile ("cpsid i" ::: "memory");
}
static inline void
__enable_irq (void)
{
  __asm__ volatile ("cpsie i" ::: "memory");
}
#endif

// ----------------------------------------------------------------------------

#endif /* PLATFORM_AARCH32_LUCKFOX_LYRA_PLATFORM_H_ */
