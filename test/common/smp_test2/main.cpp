/*
 * smp_test2 — Raspberry Pi Zero 2W µOS++ Phase-2 4-core SMP test.
 *
 * Brings up all four Cortex-A cores. One worker thread is pinned to each core;
 * every worker bumps a shared counter under a µOS++ mutex ITER times. If the
 * final counter == 4*ITER, the LDREX/STREX kernel lock + cacheable/shareable
 * DRAM mapping are coherent across cores (no lost updates). Each line is tagged
 * with the core it actually ran on (port_cpu_id).
 */
#include <cmsis-plus/rtos/os.h>
#include <cmsis-plus/diag/trace.h>
#include <uart.hpp>
#include <exception_handler.hpp>
#include <smp.hpp>
#include <hw_result.hpp>

// Secondary-core idle stacks, the idle body and smp_install_boot_threads()
// are identical in every SMP test; see test/common/src/test-smp-boot.cpp.
#include <test-smp-boot.hpp>

extern "C" unsigned port_cpu_id(void);

using namespace os::rtos;

static constexpr std::uint32_t ITER = 2000;
static volatile std::uint32_t g_prog[OS_NCPU] = {};

static mutex       g_mutex { "cnt" };
static volatile std::uint32_t g_counter = 0;
static volatile std::uint32_t g_done = 0;

static void* worker (void*)
{
  for (std::uint32_t i = 0; i < ITER; ++i)
    {
      g_mutex.lock();
      std::uint32_t v = g_counter;
      __asm__ volatile("" ::: "memory");
      g_counter = v + 1;                 // read-modify-write under the lock
      g_mutex.unlock();
      g_prog[port_cpu_id() & (OS_NCPU-1)] = i;
      if ((i & 0x7F) == 0)
        this_thread::yield();
    }
  g_mutex.lock();
  uart::uart1 << "[c" << static_cast<int>(port_cpu_id())
              << "] worker done, counter=" << g_counter << "\n";
  ++g_done;
  g_mutex.unlock();
  return nullptr;
}

extern "C"
{
  extern char __heap_start[];
  extern char __heap_end[];
  extern char __fiq_stack_top[];
  extern char __irq_stack_top[];

  void os_startup_initialize_hardware_early (void) { }

  void os_startup_initialize_hardware (void)
  {
    uart::uart1.init();
    uart::uart1 << "\n\n+== " PORT_BANNER_SHORT " µOS++ SMP TEST 2 : 4-core lock coherency ==+\n\n";
    os_startup_initialize_free_store(__heap_start,
                                     static_cast<std::size_t>(__heap_end - __heap_start));
    exception::init();
  }

  [[noreturn]] static void custom_main_trampoline (void)
  {
    int code = os_main (0, nullptr);
    std::exit (code);
  }

  extern void os_startup_create_thread_idle (void);
  extern os::rtos::thread* os_main_thread;

  int main (int, char*[])
  {
#if defined(OS_HAS_INTERRUPTS_STACK)
    os::rtos::interrupts::stack ()->set (
        reinterpret_cast<os::rtos::thread::stack::element_t*>(__fiq_stack_top),
        __irq_stack_top - __fiq_stack_top);
    os::rtos::interrupts::stack ()->initialize ();
#endif
    scheduler::initialize ();

    static thread::stack::element_t main_stack[8192];
    thread::attributes attr = thread::initializer;
    attr.th_stack_address = main_stack;
    attr.th_stack_size_bytes = sizeof(main_stack);
    static thread main_thread { "main",
        reinterpret_cast<thread::func_t> (custom_main_trampoline), nullptr, attr };
    os_main_thread = &main_thread;

    os_startup_create_thread_idle ();
    scheduler::start ();
    return 0;
  }
}

static thread::stack::element_t wstack[OS_NCPU][4096];

int os_main (int, char*[])
{
  using uart::uart1;
  // Unmask IRQs before the scheduler starts. Portable across every
  // port: the architecture supplies the instruction, not the test.
  (void)os::rtos::interrupts::uncritical_section::enter ();

  uart1 << "os_main on core " << static_cast<int>(port_cpu_id()) << "\n";
  smp_install_boot_threads();
  uart1 << "Releasing cores 1..3...\n";
  smp::start_secondary_cores();

  int waited = 0;
  while ((g_core_stage[1] < 3 || g_core_stage[2] < 3 || g_core_stage[3] < 3) && waited < 3000)
    { sysclock.sleep_for(50); waited += 50; }
  uart1 << "join: c1=" << g_core_stage[1] << " c2=" << g_core_stage[2]
        << " c3=" << g_core_stage[3] << " (" << waited << "ms)\n";

  thread::attributes attr = thread::initializer;
  static thread* workers[OS_NCPU];
  static const char* wn[OS_NCPU] = {"w0", "w1", "w2", "w3"};
  for (unsigned c = 0; c < OS_NCPU; ++c)
    {
      attr.th_stack_address = wstack[c];
      attr.th_stack_size_bytes = sizeof(wstack[c]);
      workers[c] = new thread(wn[c], worker, nullptr, attr);
      workers[c]->cpu_affinity(1u << c);
    }

  while (g_done < OS_NCPU)
  {
    sysclock.sleep_for(500);
    uart1 << "progress: w0=" << g_prog[0] << " w1=" << g_prog[1]
          << " w2=" << g_prog[2] << " w3=" << g_prog[3]
          << " done=" << g_done << " counter=" << g_counter << "\n";
  }

  std::uint32_t expected = ITER * OS_NCPU;
  uart1 << "\n==== RESULT ====\n";
  uart1 << "counter = " << g_counter << "  expected = " << expected << "\n";
  uart1 << (g_counter == expected ? "PASS: lock coherent across 4 cores\n"
                                  : "FAIL: lost updates!\n");
  uart1 << "\nRESULT: " << (g_counter == expected ? "PASS" : "FAIL") << "\n";
  if (g_counter == expected)
    {
      hw_result::ok ();
    }
  else
    {
      hw_result::fail ();
    }
  for (;;) sysclock.sleep_for(10000);
}
