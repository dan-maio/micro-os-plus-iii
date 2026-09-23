/*
 * This file is part of the µOS++ distribution.
 *   (https://github.com/micro-os-plus/)
 * Copyright (c) 2022-2025 Liviu Ionescu. All rights reserved.
 *
 * Permission to use, copy, modify, and/or distribute this software
 * for any purpose is hereby granted, under the terms of the MIT license.
 *
 * If a copy of the license was not distributed with this file, it can be
 * obtained from https://opensource.org/licenses/mit.
 */

/*
 * Memory Spaces Definitions for the QEMU mps2-an521 board (dual Cortex-M33,
 * SSE-200), as modelled by QEMU:
 *
 *   0x00000000 .. 0x003fffff  ssram-0 (4M), the FPGA image's code RAM
 *   0x80000000 .. 0x80ffffff  system RAM (16M, not behind an MPC)
 *
 * Both cores share these regions. Core 0's main stack comes from the linker
 * script's RAM; core 1's handler-mode stack is a static array allocated by
 * the port core (see os-core-m33.cpp), so the linker needs no per-core map.
 *
 * The values below can be addressed in further linker scripts
 * using functions like 'ORIGIN(RAM)' or 'LENGTH(RAM)'.
 */

MEMORY
{
  FLASH (rx) : ORIGIN = 0x10000000, LENGTH = 0x00400000 /* 4M */
  RAM (xrw) : ORIGIN = 0x80000000, LENGTH = 0x01000000 /* 16M */
}
