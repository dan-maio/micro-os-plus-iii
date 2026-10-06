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

#ifndef MICRO_OS_PLUS_PLATFORM_CORTEXM_NUCLEOF411_PLATFORM_H_
#define MICRO_OS_PLUS_PLATFORM_CORTEXM_NUCLEOF411_PLATFORM_H_

// ----------------------------------------------------------------------------

// cmsis-os-validator raises IRQ 0 (NVIC_SetPendingIRQ((IRQn_Type)0)) to call
// the RTOS from an ISR. On the STM32F411 IRQ 0 is the window watchdog: name
// the validator's handler after that vector, as the upstream nucleo-f411re
// platform does. Without it the vector is the weak Default_Handler loop and
// the run stops at TC_ThreadInterrupts.
#define ARM_CMSIS_VALIDATOR_IRQHandler WWDG_IRQHandler

#define OS_USE_SEMIHOSTING_SYSCALLS

// ----------------------------------------------------------------------------

#endif /* MICRO_OS_PLUS_PLATFORM_CORTEXM_NUCLEOF411_PLATFORM_H_ */
