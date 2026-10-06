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

// fp-switch: the FPU registers survive a preemptive context switch.
//
// Several unpinned threads, at three priorities, each load a pattern of their
// own into all of s0-s31 and the FPSCR flags, spin long enough for the tick to
// preempt them (and, on SMP, for another core to pick them up), then read the
// registers back. A port that does not save the FPU context on a switch hands
// a thread another thread's registers, or another core's: a mismatch.
//
// The registers are loaded and checked in inline assembly, so the result does
// not depend on how the compiler happens to allocate them.

#include <cmsis-plus/rtos/os.h>

#include <cstdio>
#include <cstdint>

using namespace os;
using namespace os::rtos;

#if defined(__ARM_FP)

#if defined(OS_USE_SMP_SCHEDULER)
extern "C" unsigned port_cpu_id (void);
#endif

namespace
{
  constexpr unsigned threads_count = 6;
  constexpr unsigned run_ticks = 3000;
  constexpr unsigned spin_loops = 40000;
  // FPSCR N, Z, C, V: flags only, the rounding and exception bits are left.
  constexpr uint32_t fpscr_flags_mask = 0xF0000000u;

  volatile bool stop;

  struct context
  {
    unsigned id;
    unsigned rounds;
    unsigned bad_rounds;
    unsigned migrated_rounds;
  };

  context contexts[threads_count];

  // Load in[] into s0-s31 and flags into the FPSCR, spin, store the
  // registers to out[] and return the FPSCR flags read back. The caller's
  // FPSCR is restored.
  uint32_t
  hold_fp_registers (const uint32_t* in, uint32_t* out, uint32_t flags)
  {
    uint32_t saved;
    uint32_t read;
    uint32_t n = spin_loops;
    __asm__ volatile (
        " vmrs %[saved], fpscr               \n"
        " vldmia %[in]!, {s0-s15}             \n"
        " vldmia %[in]!, {s16-s31}            \n"
        " bic %[read], %[saved], %[mask]      \n"
        " orr %[read], %[read], %[flags]      \n"
        " vmsr fpscr, %[read]                 \n"
        "1:                                   \n"
        " subs %[n], %[n], #1                 \n"
        " bne 1b                              \n"
        " vmrs %[read], fpscr                 \n"
        " vstmia %[out]!, {s0-s15}            \n"
        " vstmia %[out]!, {s16-s31}           \n"
        " vmsr fpscr, %[saved]                \n"
        : [saved] "=&r"(saved), [read] "=&r"(read), [n] "+r"(n),
          [in] "+r"(in), [out] "+r"(out)
        : [flags] "r"(flags), [mask] "r"(fpscr_flags_mask)
        : "memory", "cc", "s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7",
          "s8", "s9", "s10", "s11", "s12", "s13", "s14", "s15", "s16", "s17",
          "s18", "s19", "s20", "s21", "s22", "s23", "s24", "s25", "s26",
          "s27", "s28", "s29", "s30", "s31");
    return read & fpscr_flags_mask;
  }

  void*
  worker (void* arg)
  {
    context* ctx = static_cast<context*> (arg);
    uint32_t in[32];
    uint32_t out[32];

    while (!stop)
      {
        for (unsigned k = 0; k < 32; ++k)
          {
            in[k] = 0x40000000u | (ctx->id << 16) | ((ctx->rounds & 0xFFu) << 8)
                    | k;
          }
        uint32_t flags = ((ctx->id + ctx->rounds) & 0xFu) << 28;

#if defined(OS_USE_SMP_SCHEDULER)
        unsigned cpu_before = port_cpu_id ();
#endif
        uint32_t flags_read = hold_fp_registers (in, out, flags);
#if defined(OS_USE_SMP_SCHEDULER)
        if (port_cpu_id () != cpu_before)
          {
            ++ctx->migrated_rounds;
          }
#endif

        bool bad = (flags_read != flags);
        for (unsigned k = 0; k < 32; ++k)
          {
            if (out[k] != in[k])
              {
                bad = true;
              }
          }
        if (bad)
          {
            ++ctx->bad_rounds;
          }
        ++ctx->rounds;

        // Sleep now and then, so the higher priority threads wake up in the
        // middle of the lower ones' rounds.
        if (ctx->rounds % (ctx->id + 2) == 0)
          {
            sysclock.sleep_for (1);
          }
      }
    return nullptr;
  }
} // namespace

int
os_main (int argc __attribute__ ((unused)),
         char* argv[] __attribute__ ((unused)))
{
  // The workers spin for most of each tick and at up to normal + 2 they can
  // take the whole CPU. On real silicon a round is about a tick long, so at
  // the default (normal) priority this thread never ran again: it never set
  // `stop` and the test never ended. Keep the controller above the workers.
  this_thread::thread ().priority (thread::priority::high);

  std::printf ("\nFPU context switch test, %u threads, %u ticks\n",
               threads_count, run_ticks);

  thread* threads[threads_count];
  for (unsigned i = 0; i < threads_count; ++i)
    {
      contexts[i].id = i;
      thread::attributes attr;
      attr.th_priority
          = static_cast<thread::priority_t> (thread::priority::normal + i % 3);
      attr.th_stack_size_bytes = 2048;
      threads[i] = new thread ("fp", worker, &contexts[i], attr);
    }

  sysclock.sleep_for (run_ticks);
  stop = true;

  unsigned rounds = 0;
  unsigned bad = 0;
  unsigned migrated = 0;
  for (unsigned i = 0; i < threads_count; ++i)
    {
      threads[i]->join ();
      delete threads[i];
      std::printf ("thread %u: %u rounds, %u bad, %u migrated\n", i,
                   contexts[i].rounds, contexts[i].bad_rounds,
                   contexts[i].migrated_rounds);
      rounds += contexts[i].rounds;
      bad += contexts[i].bad_rounds;
      migrated += contexts[i].migrated_rounds;
    }

  std::printf ("total: %u rounds, %u bad, %u migrated\n", rounds, bad,
               migrated);
  return (bad == 0 && rounds > 0) ? 0 : 1;
}

#else

int
os_main (int argc __attribute__ ((unused)),
         char* argv[] __attribute__ ((unused)))
{
  std::printf ("\nFPU context switch test: no FPU, nothing to test\n");
  return 0;
}

#endif // defined(__ARM_FP)
