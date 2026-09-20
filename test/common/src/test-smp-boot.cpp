/*
 * test-smp-boot.cpp - see test-smp-boot.hpp.
 */

#include <test-smp-boot.hpp>

#include <cstdio>

using namespace os::rtos;

namespace
{
  thread::stack::element_t idle_stack[OS_NCPU][TEST_IDLE_STACK_WORDS];

  // Thread names must outlive the thread, so they are built once into static
  // storage. Generated rather than listed, so the helper follows OS_NCPU
  // instead of assuming the four cores of a BCM2837.
  char idle_name[OS_NCPU][8];
} // namespace

extern "C" void*
test_secondary_idle_func (void*)
{
  this_thread::thread ().priority (thread::priority::idle);
  for (;;)
    {
      // "dsb sy" is the portable spelling: ARMv8-A requires the domain and
      // ARMv7-A accepts it, so one line serves every ARM port.
      __asm__ volatile ("dsb sy\n wfi" ::: "memory");
      this_thread::yield ();
    }
  return nullptr;
}

extern "C" void
smp_install_boot_threads (void)
{
  for (unsigned c = 1; c < OS_NCPU; ++c)
    {
      std::snprintf (idle_name[c], sizeof (idle_name[c]), "idle%u", c);

      thread::attributes a = thread::initializer;
      a.th_stack_address = idle_stack[c];
      a.th_stack_size_bytes = sizeof (idle_stack[c]);

      scheduler::os_idle_thread_core[c]
          = new thread (idle_name[c], test_secondary_idle_func, nullptr, a);
    }
}
