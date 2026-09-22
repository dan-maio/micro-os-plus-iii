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

#ifndef PLATFORM_AARCH64_RPI_ZERO_2W_PLATFORM_H_
#define PLATFORM_AARCH64_RPI_ZERO_2W_PLATFORM_H_

// ----------------------------------------------------------------------------

// The AArch64 port supplies the platform specifics through its own headers
// (uart.hpp, led.hpp, smp.hpp, timer_arm.hpp, ...). This header exists only
// to satisfy the <cmsis-plus/platform.h> include from the test's
// os-app-config.h.

// The kernel's semihosting syscalls (c-syscalls-semihosting.cpp) are
// AArch32-only and are deliberately NOT used here; the platform provides its
// own strong semihosting (HLT #0xF000) in src/platform-support.cpp.

// ----------------------------------------------------------------------------

#endif /* PLATFORM_AARCH64_RPI_ZERO_2W_PLATFORM_H_ */
