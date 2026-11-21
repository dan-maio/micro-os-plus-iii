/**
 * @file  hw_result.hpp
 * @brief Bounded "done" helper: how a test ends a run with a verdict.
 *
 * Shared by both silicon ports. It was two copies, aarch32/include/ and
 * aarch64/include/, whose CODE was identical and whose comments differed
 * only in which board they happened to name.
 *
 * The POSIX host port does NOT use this file: a host process always has an
 * exit status and must flush stdio on the way out, so there is no
 * "without SEMIHOST" case to fall through to. See
 * posix-arch/include/hw_result.hpp.
 *
 * The hardware (hw.sh / SEMIHOST) builds are debug-in-RAM runs: after the
 * test prints its RESULT line we must STOP, not loop forever, so OpenOCD /
 * hw.sh sees the run end with a semihosted SYS_EXIT carrying PASS/FAIL.
 *
 * In the QEMU / SD-boot builds (no SEMIHOST) these helpers compile to nothing
 * and the tests keep their original idle behaviour, so QEMU runs are
 * unchanged.
 *
 * Pattern in a test:
 *
 *     // bounded LED / heartbeat loop, e.g. 15 iterations, then:
 *     if (all_ok) { write_str ("RESULT: PASS\n"); hw_result::ok (); }
 *     else        { write_str ("RESULT: FAIL\n"); hw_result::fail (); }
 *     for (;;) sysclock.sleep_for (1000);   // never reached on SEMIHOST
 */
#pragma once

#if defined(SEMIHOST)
#include "semihosting.hpp"
#endif

namespace hw_result
{
  // Stop the run reporting SUCCESS. On SEMIHOST builds this never returns
  // (SYS_EXIT stops the core); on QEMU builds it is a no-op.
  inline void
  ok () noexcept
  {
#if defined(SEMIHOST)
    semihosting::exit_success ();
#endif
  }

  // Stop the run reporting FAILURE. Never returns on SEMIHOST builds.
  inline void
  fail () noexcept
  {
#if defined(SEMIHOST)
    semihosting::exit_failure ();
#endif
  }
} // namespace hw_result
