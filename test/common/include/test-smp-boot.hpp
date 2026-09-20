/*
 * test-smp-boot.hpp - secondary-core bring-up shared by the SMP tests.
 *
 * Every multi-core test needs the same three things before it can start its
 * own threads: idle stacks, an idle body that parks a secondary core, and an
 * smp_install_boot_threads() that registers one idle thread per CPU. Each
 * application used to carry its own copy; they live here once.
 *
 * ISA-neutral: the only machine instructions involved are "dsb sy" and "wfi",
 * both of which assemble on ARMv7-A and ARMv8-A alike. Everything else goes
 * through the kernel API.
 */

#ifndef UOS_TEST_SMP_BOOT_HPP_
#define UOS_TEST_SMP_BOOT_HPP_

#include <cmsis-plus/rtos/os.h>

namespace os
{
  namespace rtos
  {
    namespace scheduler
    {
      // Defined by the kernel in src/rtos/os-core.cpp, which publishes no
      // header for it; declaring it here keeps the tests from each repeating
      // the extern and keeps the kernel tree merge-clean against upstream.
      extern thread* os_idle_thread_core[OS_NCPU];
    } // namespace scheduler
  } // namespace rtos
} // namespace os

// Stack words per secondary idle thread. Override per application with
// -DTEST_IDLE_STACK_WORDS=<n> when a port needs deeper idle stacks.
#ifndef TEST_IDLE_STACK_WORDS
#define TEST_IDLE_STACK_WORDS 512
#endif

// Idle body for a secondary core: drop to idle priority, then wait for an
// interrupt and yield forever.
extern "C" void*
test_secondary_idle_func (void*);

// Creates an idle thread for CPUs 1..OS_NCPU-1 and registers each one in
// os_idle_thread_core[]. The port's start-up path calls this by name, before
// smp::start_secondary_cores() releases the secondaries.
extern "C" void
smp_install_boot_threads (void);

#endif /* UOS_TEST_SMP_BOOT_HPP_ */
