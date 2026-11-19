/*
 * clock-test (Pico 2 / RP2350, SMP) -- the kernel's clocks against TIMER0.
 *
 * On both cores: sysclock and hrclock keep TIMER0's time (2000 ticks), and
 * hrclock.sleep_until (now () + 100 ms) lasts 100 ms (+1 tick), hrclock.now()
 * being within two ticks of the steady count its sleeps are measured
 * against. It guards three port faults found and fixed together: hrclock's
 * steady count advanced in CPU cycles while now() reads TIMER0 microseconds
 * (a sleep ~150 times too short); now() counted from TIMER0's reset, not
 * from the kernel's tick; and SysTick, latching one pending interrupt, lost
 * the ticks of every masked stretch (3-10 ms at the start-up), which the
 * port now catches up from TIMER0.
 *
 * The console is the UART; the same lines go to semihosting at the end (so
 * they reach the runner's log), not as they are printed: a semihosting call
 * halts the core in the middle of the measurements.
 */
#include <cmsis-plus/rtos/os.h>
#include <bsp/led.hpp>
#include <bsp/multicore.hpp>
#include <bsp/uart.hpp>
#include <hw_result.hpp>
#include <cstdio>
#include <cstdint>
#include <cstdarg>

using namespace os::rtos;

extern "C"
{
  void port_smp_secondary_start (void);
  unsigned port_core1_stack_top (void);
  unsigned port_cpu_id (void);
  void port_smp_core0_ipi_enable (void);
}

namespace os { namespace rtos { namespace scheduler { extern thread* os_idle_thread_core[OS_NCPU]; } } }

namespace
{
  char g_log[2048];
  unsigned g_log_len = 0;
  void say (const char* fmt, ...) __attribute__ ((format (printf, 1, 2)));
  void say (const char* fmt, ...)
  {
    char b[160];
    va_list ap;
    va_start (ap, fmt);
    int n = std::vsnprintf (b, sizeof (b), fmt, ap);
    va_end (ap);
    uart::write (b, static_cast<std::size_t> (n));
    // Kept for the runner's log, sent through semihosting only at the end:
    // a semihosting call halts the core, and SysTick loses the ticks of the
    // halt, which would show as an offset the probe is measuring.
    for (int i = 0; i < n && g_log_len + 1 < sizeof (g_log); ++i)
      g_log[g_log_len++] = b[i];
    g_log[g_log_len] = '\0';
  }

  unsigned g_bad = 0;
  void ok (bool c, const char* what) { say ("  [%s] %s\n", c ? "ok" : "BAD", what); if (!c) ++g_bad; }

  // TIMER0's raw microsecond count: the reference, independent of hrclock's origin.
  std::uint64_t ref_us (void) { return port::timer0_us (); }

  struct probe { std::uint32_t sleep_us; std::uint32_t gap; unsigned cpu; };
  probe g_p[2];
  volatile bool g_p1_done = false;

  void measure (probe& p)
  {
    sysclock.sleep_for (2);
    p.cpu = port_cpu_id ();
    p.gap = static_cast<std::uint32_t> (hrclock.now () - hrclock.steady_now ());
    const std::uint64_t t = ref_us ();
    hrclock.sleep_until (hrclock.now () + 100000u); // 100 ms, in hrclock's microseconds
    p.sleep_us = static_cast<std::uint32_t> (ref_us () - t);
  }

  void* on_core1 (void*) { measure (g_p[1]); g_p1_done = true; return nullptr; }

  thread::stack::element_t idle1_stack[512];
  thread::stack::element_t probe_stack[1024];

  void* secondary_idle_func (void*)
  {
    this_thread::thread ().priority (thread::priority::idle);
    while (true)
      {
        __asm__ volatile ("dsb" ::: "memory");
        __asm__ volatile ("wfi");
        this_thread::yield ();
      }
    return nullptr;
  }
}

int
os_main (int, char*[])
{
  this_thread::thread ().cpu_affinity (1u << 0);
  led::init ();
  say ("\n== clock-test (RP2350, SMP) ==\n");
  {
    thread::attributes attr = thread::initializer;
    attr.th_stack_address = idle1_stack;
    attr.th_stack_size_bytes = sizeof (idle1_stack);
    os::rtos::scheduler::os_idle_thread_core[1] = new thread ("idle1", secondary_idle_func, nullptr, attr);
  }
  multicore::launch_core1 (port_smp_secondary_start, port_core1_stack_top ());
  port_smp_core0_ipi_enable ();

  say ("hrclock %lu Hz, cycles_per_tick %lu\n", static_cast<unsigned long> (hrclock.input_clock_frequency_hz ()),
       static_cast<unsigned long> (port::clock_highres::cycles_per_tick ()));

  // The tick against TIMER0.
  sysclock.sleep_for (1);
  const clock::timestamp_t s0 = sysclock.now ();
  const std::uint64_t r0 = ref_us ();
  const clock::timestamp_t h0 = hrclock.now ();
  sysclock.sleep_for (2000);
  const std::uint32_t r = static_cast<std::uint32_t> (ref_us () - r0);
  const std::uint32_t h = static_cast<std::uint32_t> (hrclock.now () - h0);
  say ("2000 ticks: sysclock +%lu, TIMER0 %lu us, hrclock %lu us\n", static_cast<unsigned long> (sysclock.now () - s0),
       static_cast<unsigned long> (r), static_cast<unsigned long> (h));
  ok (r + 200 >= 2000000 && r <= 2000000 + 200, "the tick keeps TIMER0's time (within 200 us in 2 s)");
  ok (h + 200 >= r && r + 200 >= h, "hrclock keeps TIMER0's time");

  measure (g_p[0]);
  {
    thread::attributes attr = thread::initializer;
    attr.th_stack_address = probe_stack;
    attr.th_stack_size_bytes = sizeof (probe_stack);
    attr.th_cpu_affinity = 1u << 1;
    static thread t1{ "core1", on_core1, nullptr, attr };
    for (unsigned i = 0; i < 50 && !g_p1_done; ++i)
      sysclock.sleep_for (100);
  }
  ok (g_p1_done, "the core-1 probe finished");
  for (unsigned c = 0; c < 2; ++c)
    {
      const probe& p = g_p[c];
      say ("core %u (ran on %u): hrclock.sleep_until(now + 100 ms) %lu us; now - steady_now %lu us\n", c, p.cpu,
           static_cast<unsigned long> (p.sleep_us), static_cast<unsigned long> (p.gap));
      ok (p.sleep_us >= 99900 && p.sleep_us <= 101300, c == 0 ? "hrclock sleep lasted 100 ms (+1 tick) (core 0)" : "hrclock sleep lasted 100 ms (+1 tick) (core 1)");
      ok (p.gap <= 2000, c == 0 ? "hrclock.now() within two ticks of its steady count (core 0)" : "hrclock.now() within two ticks of its steady count (core 1)");
    }
  say ("\nRESULT: %s (clock-test, %u failed checks)\n", g_bad == 0 ? "PASS" : "FAIL", g_bad);
  hw_result::semi_write0 (g_log);
  if (g_bad == 0)
    hw_result::ok ();
  else
    hw_result::fail ();
  for (;;)
    sysclock.sleep_for (10000);
}
