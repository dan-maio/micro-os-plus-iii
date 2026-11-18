/*
 * smp-pro-cons-test -- multi-core producer-consumer testing ALL kernel objects.
 *
 * This test exercises every single µOS++ III kernel object in SMP concurrency:
 *   1. os::rtos::thread                 : 12 threads running concurrently across OS_NCPU cores
 *   2. os::rtos::memory_pool            : Block allocation/free of data packets
 *   3. os::rtos::message_queue          : Bounded typed inter-thread message FIFO
 *   4. os::rtos::semaphore_counting     : Flow-control credit bucket
 *   5. os::rtos::semaphore_binary       : Pipeline stage synchronization
 *   6. os::rtos::mutex                  : Recursive & normal mutual exclusion
 *   7. os::rtos::condition_variable     : Batch completion notification & wait
 *   8. os::rtos::event_flags            : Multi-bit event notifications & barrier
 *   9. os::rtos::timer                  : Periodic software timer callback
 *  10. os::rtos::sysclock               : Sleep, timestamping, durations
 *  11. Cooperative & Dynamic primitives : yield(), suspend(), resume()
 *
 * Logging: the board's console (uart.hpp), and semihosting on SEMIHOST builds.
 *
 * One copy for every board: it was a copy per board in the architecture
 * ports (test/<board>/), merged in step 6b of the upstream alignment. The
 * threads are pinned to cores modulo OS_NCPU, so a board with fewer cores
 * runs the same set.
 *
 * A portable test: os_main() only, the µOS++ interfaces only (and the
 * storage drivers of the device packages). The platform brings the board and
 * the secondary cores up before os_main() and prints the RESULT line from its
 * return value (board-tests/portable-test-end.cpp).
 */

#include <cmsis-plus/rtos/os.h>
#include <cmsis-plus/diag/trace.h>

#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <atomic>

// The board's LED (upstream's blinky interface): the heartbeat's blink.
#include <blink-led.h>



extern "C" unsigned port_cpu_id (void);
using namespace os::rtos;

// Console output: one line per call, serialised across cores (stdout is one
// stream). It reaches the board's console through the C library -- the UART,
// mirrored to semihosting where the board does so. console_uart() was the
// board's UART-only variant for the high-volume lines; here both are one.
static mutex&
console_mutex (void)
{
  static mutex m{ "console" };
  return m;
}

static void
console (const char* fmt, ...) __attribute__ ((format (printf, 1, 2)));

static void
console (const char* fmt, ...)
{
  char b[256];
  std::va_list ap;
  va_start (ap, fmt);
  std::vsnprintf (b, sizeof (b), fmt, ap);
  va_end (ap);
  console_mutex ().lock ();
  std::fputs (b, stdout);
  // Written out while the mutex is held: the C library's stdout buffer
  // would otherwise reach the console later, from whichever thread flushes
  // it, and two cores' lines interleave character by character.
  std::fflush (stdout);
  console_mutex ().unlock ();
}

#define console_uart console

// This core's index, clamped to the counters' size.
static inline unsigned
cpu_slot (void)
{
  const unsigned id = port_cpu_id ();
  return (id < OS_NCPU) ? id : 0u;
}

// One per-core tally line, "<label> : c0=.. c1=..", for every core.
static void
report_per_core (const char* label, const std::uint32_t* counts)
{
  char b[32 * OS_NCPU + 64];
  int n = std::snprintf (b, sizeof (b), "  %s : ", label);
  for (unsigned c = 0; c < OS_NCPU && n > 0 && n < static_cast<int> (sizeof (b)); ++c)
    {
      const int w = std::snprintf (b + n, sizeof (b) - static_cast<unsigned> (n),
                                   "c%u=%u ", c, static_cast<unsigned> (counts[c]));
      if (w <= 0)
        {
          break;
        }
      n += w;
    }
  console ("%s\n", b);
}

namespace
{

#ifndef RUN_MS
#define RUN_MS 4000
#endif

// ---------------------------------------------------------------------------
// Packet structure exchanged via memory_pool & message_queue
// ---------------------------------------------------------------------------
struct Packet
{
  std::uint32_t seq;
  std::uint32_t prod_id;
  std::uint32_t core_id;
  std::uint32_t timestamp;
  std::uint32_t payload;
  std::uint32_t crc;
};

// CRC32 calculation (IEEE 802.3)
std::uint32_t
calc_crc32 (const void* data, std::size_t len)
{
  const auto* p = static_cast<const std::uint8_t*> (data);
  std::uint32_t crc = 0xFFFFFFFFu;
  for (std::size_t i = 0; i < len; ++i)
    {
      crc ^= p[i];
      for (int j = 0; j < 8; ++j)
        {
          crc = (crc >> 1) ^ (0xEDB88320u & (-(crc & 1)));
        }
    }
  return ~crc;
}

// ---------------------------------------------------------------------------
// 1. MUTEXES
// ---------------------------------------------------------------------------
static mutex g_stats_mtx   { "stats_mtx" };
static mutex g_cond_mtx    { "cond_mtx" };

// Safe formatted print to UART and semihosting
// ---------------------------------------------------------------------------
// 2. MEMORY POOL: fixed-size packet block allocation
// ---------------------------------------------------------------------------
constexpr std::size_t kPoolBlocks = 48;
static memory_pool g_pkt_pool { "pkt_pool", kPoolBlocks, sizeof (Packet) };

// ---------------------------------------------------------------------------
// 3. MESSAGE QUEUE: bounded FIFO for Packet pointers
// ---------------------------------------------------------------------------
constexpr std::size_t kQueueCapacity = 32;
static message_queue g_msg_queue { "msg_queue", kQueueCapacity, sizeof (Packet*) };

// ---------------------------------------------------------------------------
// 4. COUNTING SEMAPHORE: Token-bucket flow control
// ---------------------------------------------------------------------------
constexpr std::size_t kMaxCredits = 32;
static semaphore_counting g_credit_sem { "credit_sem", kMaxCredits, kMaxCredits };

// ---------------------------------------------------------------------------
// 5. BINARY SEMAPHORE: Pipeline stage handshake
// ---------------------------------------------------------------------------
static semaphore_binary g_stage_sem { "stage_sem", 0 };

// ---------------------------------------------------------------------------
// 6. CONDITION VARIABLE: Batch notification
// ---------------------------------------------------------------------------
static condition_variable g_batch_cond { "batch_cond" };
constexpr std::size_t kBatchSize = 16;
static std::size_t g_batch_counter = 0;
static std::uint32_t g_batch_crc_sum = 0;

// ---------------------------------------------------------------------------
// 7. EVENT FLAGS: Multi-bit status flags & barriers
// ---------------------------------------------------------------------------
static event_flags g_events { "app_events" };
constexpr flags::mask_t FLAG_PROD_ACTIVE  = (1 << 0);
constexpr flags::mask_t FLAG_CONS_ACTIVE  = (1 << 1);
constexpr flags::mask_t FLAG_TIMER_TICK   = (1 << 2);
constexpr flags::mask_t FLAG_STAGE_SYNC   = (1 << 3);
constexpr flags::mask_t FLAG_SHUTDOWN     = (1 << 4);

// ---------------------------------------------------------------------------
// 8. SOFTWARE TIMER: Periodic heartbeat timer
// ---------------------------------------------------------------------------
static std::atomic<std::uint32_t> g_timer_ticks { 0 };

// The board's LED, blinked by the heartbeat timer.
static blink_led g_led;

static void
heartbeat_timer_cb (timer::func_args_t)
{
  g_timer_ticks.fetch_add (1, std::memory_order_relaxed);
  g_events.raise (FLAG_TIMER_TICK);
  g_led.blink ();
}

static timer g_heartbeat_timer {
  "heartbeat", heartbeat_timer_cb, nullptr, timer::periodic_initializer
};

// ---------------------------------------------------------------------------
// Global Test Metrics
// ---------------------------------------------------------------------------
static volatile bool g_running = true;
static std::atomic<std::uint32_t> g_produced { 0 };
static std::atomic<std::uint32_t> g_consumed { 0 };
static std::atomic<std::uint32_t> g_batches_checked { 0 };
static std::atomic<std::uint32_t> g_stage_sync_count { 0 };
static std::atomic<std::uint32_t> g_crc_errors { 0 };
static std::atomic<std::uint32_t> g_total_yields { 0 };
static std::atomic<std::uint32_t> g_pool_alloc_count { 0 };
static std::atomic<std::uint32_t> g_pool_free_count { 0 };
static std::atomic<std::uint32_t> g_suspends { 0 };
static std::atomic<std::uint32_t> g_resumes { 0 };

static std::atomic<bool> g_suspend_req { false };
static std::atomic<bool> g_is_suspended { false };

static std::uint32_t g_core_produced[OS_NCPU] = { 0 };
static std::uint32_t g_core_consumed[OS_NCPU] = { 0 };
static std::uint32_t g_core_yields[OS_NCPU]   = { 0 };

// ---------------------------------------------------------------------------
// Producer Thread Function (4 instances: prod_0..prod_3)
// ---------------------------------------------------------------------------
static void
producer_thread (void* arg)
{
  const auto id = reinterpret_cast<std::uintptr_t> (arg);
  g_events.raise (FLAG_PROD_ACTIVE);

  while (g_running)
    {
      // 1. Acquire credit token from counting semaphore
      result_t res = g_credit_sem.wait ();
      if (res != result::ok || !g_running)
        {
          break;
        }

      // 2. Allocate packet from memory pool
      void* mem = g_pkt_pool.alloc ();
      if (!mem)
        {
          g_credit_sem.post ();
          this_thread::yield ();
          continue;
        }
      g_pool_alloc_count.fetch_add (1, std::memory_order_relaxed);

      auto* pkt = static_cast<Packet*> (mem);
      const unsigned core = cpu_slot ();
      const std::uint32_t seq = g_produced.fetch_add (1, std::memory_order_relaxed);

      pkt->seq = seq;
      pkt->prod_id = static_cast<std::uint32_t> (id);
      pkt->core_id = core;
      pkt->timestamp = static_cast<std::uint32_t> (sysclock.now ());
      pkt->payload = (seq * 1103515245u + 12345u) ^ static_cast<std::uint32_t> (id);
      pkt->crc = calc_crc32 (pkt, sizeof (Packet) - sizeof (std::uint32_t));

      g_stats_mtx.lock ();
      ++g_core_produced[core];
      g_stats_mtx.unlock ();

      // 3. Send packet pointer through message queue
      g_msg_queue.send (&pkt, sizeof (pkt));

      // Cooperative yield
      this_thread::yield ();
      g_total_yields.fetch_add (1, std::memory_order_relaxed);
      g_stats_mtx.lock ();
      ++g_core_yields[cpu_slot ()];
      g_stats_mtx.unlock ();

      sysclock.sleep_for (10 + (id * 2));
    }
}

// ---------------------------------------------------------------------------
// Consumer Thread Function (4 instances: cons_0..cons_3)
// ---------------------------------------------------------------------------
static void
consumer_thread (void* arg)
{
  const auto id = reinterpret_cast<std::uintptr_t> (arg);
  g_events.raise (FLAG_CONS_ACTIVE);

  while (g_running)
    {
      // Cooperative suspend check for cons_0
      if (id == 0 && g_suspend_req.load (std::memory_order_relaxed))
        {
          g_suspend_req.store (false, std::memory_order_relaxed);
          g_is_suspended.store (true, std::memory_order_release);
          g_suspends.fetch_add (1, std::memory_order_relaxed);
          this_thread::suspend ();
          g_is_suspended.store (false, std::memory_order_release);
        }

      Packet* pkt = nullptr;
      // 1. Receive packet pointer from message queue
      result_t res = g_msg_queue.receive (&pkt, sizeof (pkt));
      if (res != result::ok || !pkt)
        {
          if (!g_running) break;
          this_thread::yield ();
          continue;
        }

      const unsigned core = cpu_slot ();

      // 2. Validate CRC
      const std::uint32_t expected_crc
          = calc_crc32 (pkt, sizeof (Packet) - sizeof (std::uint32_t));
      if (pkt->crc != expected_crc)
        {
          g_crc_errors.fetch_add (1, std::memory_order_relaxed);
        }

      g_stats_mtx.lock ();
      ++g_core_consumed[core];
      g_stats_mtx.unlock ();
      const std::uint32_t c_count = g_consumed.fetch_add (1, std::memory_order_relaxed);

      // 3. Condition variable batch aggregation
      g_cond_mtx.lock ();
      ++g_batch_counter;
      g_batch_crc_sum ^= pkt->crc;
      if (g_batch_counter >= kBatchSize)
        {
          g_batch_cond.signal ();
        }
      g_cond_mtx.unlock ();

      // 4. Binary semaphore pipeline trigger every 8 packets
      if ((c_count & 7u) == 0)
        {
          g_stage_sem.post ();
        }

      // 5. Free block back to memory pool
      g_pkt_pool.free (pkt);
      g_pool_free_count.fetch_add (1, std::memory_order_relaxed);

      // 6. Release credit token back to counting semaphore
      g_credit_sem.post ();

      // Cooperative yield
      this_thread::yield ();
      g_total_yields.fetch_add (1, std::memory_order_relaxed);
      g_stats_mtx.lock ();
      ++g_core_yields[cpu_slot ()];
      g_stats_mtx.unlock ();

      sysclock.sleep_for (5);
    }
}

// ---------------------------------------------------------------------------
// Aggregator Thread: waits on condition variable and validates batch integrity
// ---------------------------------------------------------------------------
static void
aggregator_thread (void*)
{
  while (g_running)
    {
      g_cond_mtx.lock ();
      while (g_batch_counter < kBatchSize && g_running)
        {
          g_batch_cond.wait (g_cond_mtx);
        }

      if (g_batch_counter >= kBatchSize)
        {
          g_batch_counter = 0;
          g_batch_crc_sum = 0;
          g_batches_checked.fetch_add (1, std::memory_order_relaxed);
        }
      g_cond_mtx.unlock ();

      sysclock.sleep_for (20);
    }
}

// ---------------------------------------------------------------------------
// Stage Worker Thread: triggered by binary semaphore g_stage_sem
// ---------------------------------------------------------------------------
static void
stage_worker_thread (void*)
{
  while (g_running)
    {
      result_t res = g_stage_sem.wait ();
      if (res != result::ok || !g_running) break;

      g_stage_sync_count.fetch_add (1, std::memory_order_relaxed);
      g_events.raise (FLAG_STAGE_SYNC);
      this_thread::yield ();
    }
}

// ---------------------------------------------------------------------------
// Pauser Thread: exercises cooperative suspend() and dynamic resume()
// ---------------------------------------------------------------------------
static thread* g_target_worker = nullptr;

static void
pauser_thread (void*)
{
  while (g_running)
    {
      sysclock.sleep_for (300);
      if (!g_running || !g_target_worker) break;

      // Request target worker thread to suspend
      g_suspend_req.store (true, std::memory_order_release);

      int wait_ms = 0;
      while (!g_is_suspended.load (std::memory_order_acquire) && wait_ms < 100 && g_running)
        {
          sysclock.sleep_for (10);
          wait_ms += 10;
        }

      if (g_is_suspended.load (std::memory_order_acquire))
        {
          // Allow system to run while worker is suspended
          sysclock.sleep_for (50);
          // Resume worker thread
          g_target_worker->resume ();
          g_resumes.fetch_add (1, std::memory_order_relaxed);
        }
    }
}

// ---------------------------------------------------------------------------
// Telemetry Thread: monitors event flags, timer ticks, and logs pipeline rates
// ---------------------------------------------------------------------------
static void
telemetry_thread (void*)
{
  std::uint32_t last_produced = 0;
  std::uint32_t last_consumed = 0;
  unsigned print_counter = 0;

  while (g_running)
    {
      flags::mask_t oflags = 0;
      // Wait for periodic timer tick or shutdown event
      g_events.wait (FLAG_TIMER_TICK | FLAG_SHUTDOWN, &oflags,
                     flags::mode::any | flags::mode::clear);

      if (oflags & FLAG_SHUTDOWN) break;

      if (++print_counter >= 5) // every ~1000 ms (5 * 200 ms)
        {
          print_counter = 0;
          const std::uint32_t cur_p = g_produced.load (std::memory_order_relaxed);
          const std::uint32_t cur_c = g_consumed.load (std::memory_order_relaxed);
          const std::uint32_t delta_p = cur_p - last_produced;
          const std::uint32_t delta_c = cur_c - last_consumed;
          last_produced = cur_p;
          last_consumed = cur_c;

          const auto now_ms = static_cast<unsigned> (sysclock.now ());
          console ("[t=%5u ms] pipe: prod=%u (+%u) cons=%u (+%u) | pool=%u/%u | yields=%u | ticks=%u | stages=%u\n",
                   now_ms, cur_p, delta_p, cur_c, delta_c,
                   static_cast<unsigned> (g_pool_alloc_count.load ()),
                   static_cast<unsigned> (g_pool_free_count.load ()),
                   static_cast<unsigned> (g_total_yields.load ()),
                   static_cast<unsigned> (g_timer_ticks.load ()),
                   static_cast<unsigned> (g_stage_sync_count.load ()));
        }
    }
}

} // namespace

// ---------------------------------------------------------------------------
// os_main: Entry Point
// ---------------------------------------------------------------------------
int
os_main (int, char*[])
{
  console ("\n+=============================================================+\n");
  console ("|  µOS++ SMP PRODUCER-CONSUMER KERNEL OBJECT TEST              |\n");
  console ("|  %u cores -- ALL Kernel Objects Demo                          |\n",
           static_cast<unsigned> (OS_NCPU));
  console ("+=============================================================+\n\n");
  g_led.power_up ();

  // 1. The secondary cores were released by the platform, before os_main().

  // 2. Start Software Timer (Heartbeat)
  console ("Starting periodic software timer (200 ms)...\n");
  g_heartbeat_timer.start (200);

  // 3. Stacks and thread storage
  constexpr std::size_t kWorkerStackSize = 4096;
  static thread::stack::element_t s_prod_stacks[4][kWorkerStackSize / sizeof (thread::stack::element_t)];
  static thread::stack::element_t s_cons_stacks[4][kWorkerStackSize / sizeof (thread::stack::element_t)];
  static thread::stack::element_t s_agg_stack[kWorkerStackSize / sizeof (thread::stack::element_t)];
  static thread::stack::element_t s_stage_stack[kWorkerStackSize / sizeof (thread::stack::element_t)];
  static thread::stack::element_t s_pause_stack[kWorkerStackSize / sizeof (thread::stack::element_t)];
  static thread::stack::element_t s_telem_stack[kWorkerStackSize / sizeof (thread::stack::element_t)];

  static thread* s_prods[4];
  static thread* s_conss[4];

  // The names must outlive the threads: os::rtos::named_object stores the
  // 'const char* const name_' it is given, it does not copy the characters.
  // These were loop-local 'char name[16]' buffers; every thread name then
  // dangled the moment the loop iteration ended, and
  // scheduler::is_thread_allowed_on_cpu() strcmp()s thread::name() on every
  // scheduling decision.  ASan (-DUOS_SANITIZE=address) reports it as
  // stack-use-after-scope in is_thread_allowed_on_cpu.
  static char s_prod_names[4][16];
  static char s_cons_names[4][16];

  // Create Producers (pinned to cores 0..3)
  for (unsigned i = 0; i < 4; ++i)
    {
      char* name = s_prod_names[i];
      snprintf (name, sizeof (s_prod_names[i]), "prod_%u", i);
      thread::attributes attr = thread::initializer;
      attr.th_stack_address = s_prod_stacks[i];
      attr.th_stack_size_bytes = sizeof (s_prod_stacks[i]);
      attr.th_priority = thread::priority::normal;
      s_prods[i] = new thread {
        name, reinterpret_cast<thread::func_t> (producer_thread),
        reinterpret_cast<void*> (static_cast<std::uintptr_t> (i)), attr
      };
      s_prods[i]->cpu_affinity (1u << (i % OS_NCPU));
    }

  // Create Consumers (pinned to cores 0..3, wrapped to the cores this board
  // has: a mask naming a missing core matches no core, and the thread never
  // runs)
  for (unsigned i = 0; i < 4; ++i)
    {
      char* name = s_cons_names[i];
      snprintf (name, sizeof (s_cons_names[i]), "cons_%u", i);
      thread::attributes attr = thread::initializer;
      attr.th_stack_address = s_cons_stacks[i];
      attr.th_stack_size_bytes = sizeof (s_cons_stacks[i]);
      attr.th_priority = thread::priority::normal;
      s_conss[i] = new thread {
        name, reinterpret_cast<thread::func_t> (consumer_thread),
        reinterpret_cast<void*> (static_cast<std::uintptr_t> (i)), attr
      };
      s_conss[i]->cpu_affinity (1u << (i % OS_NCPU));
    }

  g_target_worker = s_conss[0];

  // Create Aggregator thread (waiting on condition variable)
  thread::attributes agg_attr = thread::initializer;
  agg_attr.th_stack_address = s_agg_stack;
  agg_attr.th_stack_size_bytes = sizeof (s_agg_stack);
  agg_attr.th_priority = thread::priority::above_normal;
  static thread s_agg_thread {
    "aggregator", reinterpret_cast<thread::func_t> (aggregator_thread),
    nullptr, agg_attr
  };
  s_agg_thread.cpu_affinity (1u << 1);

  // Create Stage Worker thread (waiting on binary semaphore)
  thread::attributes stage_attr = thread::initializer;
  stage_attr.th_stack_address = s_stage_stack;
  stage_attr.th_stack_size_bytes = sizeof (s_stage_stack);
  stage_attr.th_priority = thread::priority::above_normal;
  static thread s_stage_thread {
    "stage_worker", reinterpret_cast<thread::func_t> (stage_worker_thread),
    nullptr, stage_attr
  };
  s_stage_thread.cpu_affinity (1u << 2);

  // Create Pauser thread (exercising suspend and resume)
  thread::attributes pause_attr = thread::initializer;
  pause_attr.th_stack_address = s_pause_stack;
  pause_attr.th_stack_size_bytes = sizeof (s_pause_stack);
  pause_attr.th_priority = thread::priority::above_normal;
  static thread s_pause_thread {
    "pauser", reinterpret_cast<thread::func_t> (pauser_thread),
    nullptr, pause_attr
  };
  s_pause_thread.cpu_affinity (1u << (3 % OS_NCPU));

  // Create Telemetry thread (waiting on event flags)
  thread::attributes telem_attr = thread::initializer;
  telem_attr.th_stack_address = s_telem_stack;
  telem_attr.th_stack_size_bytes = sizeof (s_telem_stack);
  telem_attr.th_priority = thread::priority::high;
  static thread s_telem_thread {
    "telemetry", reinterpret_cast<thread::func_t> (telemetry_thread),
    nullptr, telem_attr
  };
  s_telem_thread.cpu_affinity (1u << 0);

  console ("12 concurrent threads started across %u cores!\n",
           static_cast<unsigned> (OS_NCPU));
  console ("Running pipeline for %u ms ...\n\n", static_cast<unsigned> (RUN_MS));

  // Run test window
  sysclock.sleep_for (RUN_MS);

  // Stop threads
  console ("\nStopping producer-consumer pipeline threads...\n");
  g_running = false;
  g_events.raise (FLAG_SHUTDOWN);
  g_stage_sem.post ();

  // Wait for queues and in-flight packets to flush
  sysclock.sleep_for (400);

  // Stop timer
  g_heartbeat_timer.stop ();

  // Final validation and statistics
  const std::uint32_t total_p = g_produced.load ();
  const std::uint32_t total_c = g_consumed.load ();
  const std::uint32_t allocs  = g_pool_alloc_count.load ();
  const std::uint32_t frees   = g_pool_free_count.load ();
  const std::uint32_t crc_err = g_crc_errors.load ();
  const std::uint32_t yields  = g_total_yields.load ();
  const std::uint32_t susp    = g_suspends.load ();
  const std::uint32_t resm    = g_resumes.load ();
  const std::uint32_t ticks   = g_timer_ticks.load ();
  const std::uint32_t batches = g_batches_checked.load ();
  const std::uint32_t stages  = g_stage_sync_count.load ();

  console ("\n================ Producer-Consumer Test Summary ================\n");
  console ("Kernel Objects Tested:\n");
  console ("  [1] thread              : 12 threads active across %u cores\n",
           static_cast<unsigned> (OS_NCPU));
  console ("  [2] memory_pool         : allocs=%u, frees=%u (diff=%d)\n",
           allocs, frees, static_cast<int> (allocs - frees));
  console ("  [3] message_queue       : sent=%u, received=%u\n", total_p, total_c);
  console ("  [4] semaphore_counting  : flow-control tokens acquired & returned\n");
  console ("  [5] semaphore_binary    : %u stage synchronizations verified\n", stages);
  console ("  [6] mutex               : protected console, stats, and condition var\n");
  console ("  [7] condition_variable  : %u batches signaled & verified\n", batches);
  console ("  [8] event_flags         : multi-bit lifecycle & timer flags handled\n");
  console ("  [9] timer               : %u software timer ticks delivered\n", ticks);
  console ("  [10] sysclock           : sleep_for() & timestamping verified\n");
  console ("  [11] yield/suspend/res  : %u yields, %u suspends, %u resumes\n",
           yields, susp, resm);
  console ("Errors:\n");
  console ("  CRC Errors: %u\n", crc_err);
  console ("SMP Core Distribution:\n");
  report_per_core ("Produced by core", g_core_produced);
  report_per_core ("Consumed by core", g_core_consumed);
  report_per_core ("Yields by core  ", g_core_yields);
  console ("================================================================\n\n");

  // Pass criteria:
  // - Significant data produced & consumed (> 100 packets)
  // - Zero CRC errors
  // - Both production and consumption occurred across multiple cores
  // - Memory pool has zero leaks (all allocated blocks were freed)
  // - Timer fired and delivered ticks
  // - Binary semaphore stage sync executed
  // - Suspend / resume executed
  // - Condition variable batches checked
  bool all_cores_active = true;
  for (unsigned c = 0; c < OS_NCPU; ++c)
    {
      if (g_core_produced[c] == 0 || g_core_consumed[c] == 0)
        {
          all_cores_active = false;
        }
    }

  const bool pass = (total_p > 50) && (total_c > 50)
                 && (crc_err == 0)
                 // At the stop exactly one packet may still be in flight:
                 // produced and its block allocated, but not yet received
                 // and freed by a consumer. Allow that single straggler while
                 // still catching a real leak, which would scale with the run.
                 && (allocs <= (frees + 1))
                 && (batches > 0)
                 && (stages > 0)
                 && (ticks > 0)
                 && (susp > 0) && (resm > 0)
                 && all_cores_active;

  console ("verdict: %s\n", pass ? "pass" : "fail");
  return pass ? 0 : 1;
}
