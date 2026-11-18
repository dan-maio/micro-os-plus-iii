/*
 * smp-pipeline-test -- µOS++ multi-core pipeline demo.
 *
 * A high-concurrency stress test demonstrating:
 *   - 13 concurrent threads across all the cores:
 *       * 4 Producers       (prio normal)        : generate timestamped sensor records
 *       * 4 Compute Workers (prio normal)        : digital filtering, vector math, CRC32
 *       * 2 SD Writers      (prio normal)        : batch and append records to SD
 *       * 1 SD Auditor      (prio normal)        : reads back from SD, validates CRC & sequence
 *       * 1 Pacer           (prio above_normal)  : the board's LED at a 150 ms cadence
 *       * 1 Telemetry       (prio high)          : periodic 1s status summary
 *   - Heavy usage of os::rtos::this_thread::yield() for cooperative scheduling:
 *       * Queue backpressure yielding
 *       * Cooperative compute chunking in worker loops
 *       * Writer/auditor inter-thread yield points
 *   - Storage: /sd/tests/pipe.dat, through µOS++ POSIX I/O, on the card's
 *     FAT volume (the posix-io block device /dev/sd with Chan FatFs, mounted
 *     at /sd/ before os_main() by board-tests/portable-test-storage.cpp); the
 *     same path on hardware (the boot card, never formatted), under QEMU and
 *     on the host (an MBR + FAT32 image).
 *
 * One copy for every board: it was a copy per board in the architecture
 * ports (test/<board>/), merged in step 6b of the upstream alignment; the
 * number of cores is OS_NCPU.
 *
 * A portable test: os_main() only, the µOS++ interfaces only. The platform brings the board and
 * the secondary cores up before os_main() and prints the RESULT line from its
 * return value (board-tests/portable-test-end.cpp).
 */

#include <cmsis-plus/rtos/os.h>
#include <cmsis-plus/diag/trace.h>

#include <cmsis-plus/posix-io/file-system.h>
#include <cmsis-plus/posix-io/io.h>
#include <cmsis-plus/posix/sys/statvfs.h>

// The board's LED (upstream's blinky interface).
#include <blink-led.h>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cerrno>

#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <atomic>



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

namespace
{

#ifndef RUN_MS
#define RUN_MS 30000
#endif

// pipe.dat, on the card's FAT volume.
static const char kPipeFile[] = "/sd/tests/pipe.dat";

// Mutexes
static mutex g_in_mtx      { "in_queue" };
static mutex g_sd_mtx      { "sd_queue" };
static mutex g_file_mtx    { "file_io" };

// Semaphores for bounded queues
constexpr std::size_t kInCap = 32;
constexpr std::size_t kSdCap = 32;
static semaphore_counting g_in_items  { "in_items",  kInCap, 0 };
static semaphore_counting g_in_spaces { "in_spaces", kInCap, kInCap };

static semaphore_counting g_sd_items  { "sd_items",  kSdCap, 0 };
static semaphore_counting g_sd_spaces { "sd_spaces", kSdCap, kSdCap };

static semaphore_counting g_audit_sem { "audit_sem", 64, 0 };

// System state
static volatile bool g_finish = false;

// ---------------------------------------------------------------------------
// CRC32 standard calculation (IEEE 802.3)
// ---------------------------------------------------------------------------
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
// Pipeline record structure
// ---------------------------------------------------------------------------
struct PipelineRecord
{
  std::uint32_t seq;
  std::uint16_t src;
  std::uint16_t proc_core;
  std::uint32_t timestamp_ms;
  std::uint32_t val;
  std::uint32_t crc;
};

// Ring buffer for input queue
static PipelineRecord g_in_buf[kInCap];
static std::size_t g_in_head = 0;
static std::size_t g_in_tail = 0;
static std::size_t g_in_count = 0;

// Ring buffer for SD queue
static PipelineRecord g_sd_buf[kSdCap];
static std::size_t g_sd_head = 0;
static std::size_t g_sd_tail = 0;
static std::size_t g_sd_count = 0;

// Yield statistics (atomic counters to test cross-core thread safety)
static std::atomic<std::uint32_t> g_yield_prod{0};
static std::atomic<std::uint32_t> g_yield_work{0};
static std::atomic<std::uint32_t> g_yield_compute{0};
static std::atomic<std::uint32_t> g_yield_writer{0};
static std::atomic<std::uint32_t> g_yield_auditor{0};
static std::atomic<std::uint32_t> g_yield_by_core[OS_NCPU]{};

// Throughput and verification statistics
static std::atomic<std::uint32_t> g_total_produced{0};
static std::atomic<std::uint32_t> g_total_processed{0};
static std::atomic<std::uint32_t> g_total_written{0};
static std::atomic<std::uint32_t> g_total_audited{0};
static std::atomic<std::uint32_t> g_crc_errors{0};
static std::atomic<std::uint32_t> g_seq_errors{0};
// Records the writers could not persist. A failed append used to be silent:
// the record was simply dropped and only showed up later as an audit gap.
static std::atomic<std::uint32_t> g_write_errors{0};

static std::atomic<std::uint32_t> g_prod_by_core[OS_NCPU]{};
static std::atomic<std::uint32_t> g_proc_by_core[OS_NCPU]{};

// Audit read window. The auditor streams pipe.dat from its last offset, so
// this bounds one read, NOT the file: both back ends append, and the file grows
// for as long as the test runs.
static constexpr unsigned kAuditWindow = 64 * 1024;
static char g_read_buf[kAuditWindow];

// Console logging helper
// ---------------------------------------------------------------------------
// SD helpers
// ---------------------------------------------------------------------------
bool
sd_prepare (void)
{
  // The volume the storage start-up mounted (it printed why, if it did not).
  struct statvfs vfs;
  if (os::posix::statvfs ("/sd/", &vfs) != 0)
    {
      console ("  no FAT volume mounted at /sd/ (errno %d)\n", errno);
      return false;
    }
  os::posix::unlink (kPipeFile);
  console ("  FAT volume at /sd/, removed previous %s\n", kPipeFile);
  return true;
}

bool
sd_append (const char* text, unsigned len)
{
  os::posix::io* f
      = os::posix::open (kPipeFile, O_WRONLY | O_CREAT | O_APPEND);
  if (f == nullptr)
    {
      return false;
    }
  const bool ok = (f->write (text, len) == static_cast<ssize_t> (len));
  return (f->close () == 0) && ok;
}

// Read up to `cap` bytes of pipe.dat starting at `offset`. Returns false only
// on a real I/O error; at end-of-file it succeeds with len == 0. Reading from
// an offset is what lets the audit follow a file that outgrows any RAM buffer.
bool
sd_read_from (unsigned offset, char* out, unsigned cap, unsigned& len)
{
  len = 0;
  struct stat st;
  if (os::posix::stat (kPipeFile, &st) != 0)
    {
      return false;
    }
  const unsigned size = static_cast<unsigned> (st.st_size);
  if (offset >= size)
    {
      return true;
    }
  unsigned want = size - offset;
  if (want > cap)
    {
      want = cap;
    }
  os::posix::io* f = os::posix::open (kPipeFile, O_RDONLY);
  if (f == nullptr)
    {
      return false;
    }
  bool ok = (f->lseek (static_cast<off_t> (offset), SEEK_SET)
             == static_cast<off_t> (offset));
  ok = ok && (f->read (out, want) == static_cast<ssize_t> (want));
  f->close ();
  len = ok ? want : 0;
  return ok;
}

// ---------------------------------------------------------------------------
// 1. Producer Thread Func (4 instances)
// ---------------------------------------------------------------------------
static void*
producer_thread (void* arg)
{
  const auto src_id = static_cast<std::uint16_t> (reinterpret_cast<std::uintptr_t> (arg));
  std::uint32_t seq = 0;

  while (!g_finish)
    {
      unsigned retries = 0;
      while (!g_finish && g_in_spaces.try_wait () != result::ok)
        {
          g_yield_prod.fetch_add (1, std::memory_order_relaxed);
          g_yield_by_core[port_cpu_id ()].fetch_add (1, std::memory_order_relaxed);
          this_thread::yield ();
          if (++retries > 6)
            {
              sysclock.sleep_for (4);
              retries = 0;
            }
        }
      if (g_finish) break;

      const unsigned core = port_cpu_id ();
      PipelineRecord rec;
      rec.seq = ++seq;
      rec.src = src_id;
      rec.proc_core = 0xFFFF;
      rec.timestamp_ms = static_cast<std::uint32_t> (sysclock.now ());
      rec.val = (seq * 1000u) + (static_cast<std::uint32_t> (src_id) * 100u) + (seq % 97u);
      rec.crc = calc_crc32 (&rec.val, sizeof (rec.val));

      g_in_mtx.lock ();
      g_in_buf[g_in_head] = rec;
      g_in_head = (g_in_head + 1) % kInCap;
      ++g_in_count;
      g_in_mtx.unlock ();

      g_in_items.post ();

      g_total_produced.fetch_add (1, std::memory_order_relaxed);
      g_prod_by_core[core].fetch_add (1, std::memory_order_relaxed);

      sysclock.sleep_for (30 + (src_id * 5));
    }
  return nullptr;
}

// ---------------------------------------------------------------------------
// 2. Compute Worker Thread Func (4 instances)
// ---------------------------------------------------------------------------
static void*
worker_thread (void* arg)
{
  const auto worker_id = static_cast<unsigned> (reinterpret_cast<std::uintptr_t> (arg));
  unsigned local_count = 0;

  while (!g_finish)
    {
      unsigned retries = 0;
      while (!g_finish && g_in_items.try_wait () != result::ok)
        {
          g_yield_work.fetch_add (1, std::memory_order_relaxed);
          g_yield_by_core[port_cpu_id ()].fetch_add (1, std::memory_order_relaxed);
          this_thread::yield ();
          if (++retries > 6)
            {
              sysclock.sleep_for (4);
              retries = 0;
            }
        }
      if (g_finish) break;

      PipelineRecord rec;
      g_in_mtx.lock ();
      rec = g_in_buf[g_in_tail];
      g_in_tail = (g_in_tail + 1) % kInCap;
      --g_in_count;
      g_in_mtx.unlock ();

      g_in_spaces.post ();

      const unsigned core = port_cpu_id ();
      rec.proc_core = static_cast<std::uint16_t> (core);

      rec.val = rec.val + (worker_id * 7u);
      rec.crc = calc_crc32 (&rec.val, sizeof (rec.val));

      if ((++local_count & 0x03) == 0)
        {
          g_yield_compute.fetch_add (1, std::memory_order_relaxed);
          g_yield_by_core[core].fetch_add (1, std::memory_order_relaxed);
          this_thread::yield ();
        }

      retries = 0;
      while (!g_finish && g_sd_spaces.try_wait () != result::ok)
        {
          g_yield_work.fetch_add (1, std::memory_order_relaxed);
          g_yield_by_core[core].fetch_add (1, std::memory_order_relaxed);
          this_thread::yield ();
          if (++retries > 6)
            {
              sysclock.sleep_for (4);
              retries = 0;
            }
        }
      if (g_finish) break;

      g_sd_mtx.lock ();
      g_sd_buf[g_sd_head] = rec;
      g_sd_head = (g_sd_head + 1) % kSdCap;
      ++g_sd_count;
      g_sd_mtx.unlock ();

      g_sd_items.post ();

      g_total_processed.fetch_add (1, std::memory_order_relaxed);
      g_proc_by_core[core].fetch_add (1, std::memory_order_relaxed);
    }
  return nullptr;
}

// ---------------------------------------------------------------------------
// 3. SD Writer Thread Func (2 instances)
// ---------------------------------------------------------------------------
static void*
sd_writer_thread (void* arg)
{
  (void)arg;
  char batch_buf[1024];

  while (!g_finish)
    {
      PipelineRecord batch[8];
      unsigned batch_count = 0;

      while (batch_count < 8)
        {
          if (g_sd_items.try_wait () == result::ok)
            {
              g_sd_mtx.lock ();
              batch[batch_count] = g_sd_buf[g_sd_tail];
              g_sd_tail = (g_sd_tail + 1) % kSdCap;
              --g_sd_count;
              g_sd_mtx.unlock ();

              g_sd_spaces.post ();
              ++batch_count;
            }
          else
            {
              if (batch_count > 0 || g_finish) break;
              this_thread::yield ();
              sysclock.sleep_for (10);
            }
        }

      if (batch_count > 0)
        {
          unsigned off = 0;
          for (unsigned i = 0; i < batch_count; ++i)
            {
              const auto& rec = batch[i];
              int n = std::snprintf (batch_buf + off, sizeof (batch_buf) - off,
                                     "[c%u] seq=%05u src=%u t=%u val=%u crc=%08x\n",
                                     (unsigned)rec.proc_core, (unsigned)rec.seq, (unsigned)rec.src,
                                     (unsigned)rec.timestamp_ms, (unsigned)rec.val, (unsigned)rec.crc);
              if (n > 0 && off + static_cast<unsigned> (n) < sizeof (batch_buf))
                {
                  off += static_cast<unsigned> (n);
                }
            }

          if (off > 0)
            {
              g_file_mtx.lock ();
              bool ok = sd_append (batch_buf, off);
              g_file_mtx.unlock ();
              if (ok)
                {
                  g_total_written.fetch_add (batch_count, std::memory_order_relaxed);
                  g_audit_sem.post ();
                }
              else
                {
                  // Never drop silently: an append that fails is a test failure.
                  g_write_errors.fetch_add (batch_count, std::memory_order_relaxed);
                }
            }
        }

      g_yield_writer.fetch_add (1, std::memory_order_relaxed);
      g_yield_by_core[port_cpu_id ()].fetch_add (1, std::memory_order_relaxed);
      this_thread::yield ();
      sysclock.sleep_for (20);
    }
  return nullptr;
}

// ---------------------------------------------------------------------------
// 4. SD Auditor Thread Func (1 instance)
// ---------------------------------------------------------------------------
static void*
sd_auditor_thread (void* arg)
{
  (void)arg;
  unsigned last_offset = 0;
  // Highest sequence number seen per source. NOT a monotonic gate: see the
  // reorder note at the check below.
  std::uint32_t max_seq_by_src[4] = { 0, 0, 0, 0 };

  while (!g_finish)
    {
      while (!g_finish && g_audit_sem.try_wait () != result::ok)
        {
          this_thread::yield ();
          sysclock.sleep_for (50);
        }
      if (g_finish) break;

      unsigned chunk_len = 0;
      const unsigned base_offset = last_offset; // file offset of g_read_buf[0]
      g_file_mtx.lock ();
      bool rd = sd_read_from (last_offset, g_read_buf, sizeof (g_read_buf),
                              chunk_len);
      g_file_mtx.unlock ();

      if (rd && chunk_len > 0)
        {
          const char* p = g_read_buf;
          const char* end = g_read_buf + chunk_len;

          while (p < end)
            {
              const char* nl = static_cast<const char*> (
                  std::memchr (p, '\n', static_cast<std::size_t> (end - p)));
              if (!nl) break;

              unsigned core_id, seq, src_id, t_ms, val_read, crc_read;
              if (std::sscanf (p, "[c%u] seq=%u src=%u t=%u val=%u crc=%x",
                               &core_id, &seq, &src_id, &t_ms, &val_read, &crc_read) == 6)
                {
                  if (src_id < 4)
                    {
                      // The two SD writer threads batch independently and
                      // append in whichever order they win g_file_mtx, so
                      // records from one source legitimately reach the file out
                      // of order — by at most the SD queue depth plus the two
                      // batches in flight. Demanding a strictly increasing seq
                      // here made the test fail on a normal interleaving.
                      // Flag only a record that arrives impossibly late, which
                      // is what actual loss or corruption looks like.
                      constexpr std::uint32_t kReorderWindow = kSdCap + 2 * 8;
                      if (seq > max_seq_by_src[src_id])
                        {
                          max_seq_by_src[src_id] = seq;
                        }
                      else if (max_seq_by_src[src_id] - seq > kReorderWindow)
                        {
                          g_seq_errors.fetch_add (1, std::memory_order_relaxed);
                        }
                    }

                  std::uint32_t expected_crc = calc_crc32 (&val_read, sizeof (val_read));
                  if (expected_crc != crc_read)
                    {
                      g_crc_errors.fetch_add (1, std::memory_order_relaxed);
                    }
                  g_total_audited.fetch_add (1, std::memory_order_relaxed);
                }

              p = nl + 1;
              last_offset = base_offset + static_cast<unsigned> (p - g_read_buf);

              g_yield_auditor.fetch_add (1, std::memory_order_relaxed);
              g_yield_by_core[port_cpu_id ()].fetch_add (1, std::memory_order_relaxed);
              this_thread::yield ();
            }
        }

      sysclock.sleep_for (40);
    }
  return nullptr;
}

// ---------------------------------------------------------------------------
// 5. LED Pacer Thread (1 instance)
// ---------------------------------------------------------------------------
static blink_led g_led;

static void*
led_thread (void* arg)
{
  (void)arg;
  g_led.power_up ();
  while (!g_finish)
    {
      g_led.blink ();
      sysclock.sleep_for (150);
      this_thread::yield ();
    }
  g_led.turn_on ();
  return nullptr;
}

// ---------------------------------------------------------------------------
// 6. Telemetry Thread (1 instance)
// ---------------------------------------------------------------------------
static void*
telemetry_thread (void* arg)
{
  (void)arg;
  while (!g_finish)
    {
      sysclock.sleep_for (1000);
      if (g_finish) break;

      const std::uint32_t t = static_cast<std::uint32_t> (sysclock.now ());
      const std::uint32_t prod = g_total_produced.load (std::memory_order_relaxed);
      const std::uint32_t proc = g_total_processed.load (std::memory_order_relaxed);
      const std::uint32_t wrt  = g_total_written.load (std::memory_order_relaxed);
      const std::uint32_t aud  = g_total_audited.load (std::memory_order_relaxed);

      const std::uint32_t y_prod = g_yield_prod.load (std::memory_order_relaxed);
      const std::uint32_t y_work = g_yield_work.load (std::memory_order_relaxed);
      const std::uint32_t y_comp = g_yield_compute.load (std::memory_order_relaxed);
      const std::uint32_t y_wrt  = g_yield_writer.load (std::memory_order_relaxed);
      const std::uint32_t y_aud  = g_yield_auditor.load (std::memory_order_relaxed);

      console ("[t=%5u ms] pipe: in_q=%2u sd_q=%2u | prod=%u proc=%u sd=%u aud=%u | yields: P=%u W=%u C=%u S=%u A=%u\n",
               t, (unsigned)g_in_count, (unsigned)g_sd_count, prod, proc, wrt, aud,
               y_prod, y_work, y_comp, y_wrt, y_aud);
    }
  return nullptr;
}

// ---------------------------------------------------------------------------
// Thread Stacks & Instances (13 worker threads)
// ---------------------------------------------------------------------------
static thread::stack::element_t s_prod_stk[4][4096];
static thread::stack::element_t s_work_stk[4][4096];
static thread::stack::element_t s_wrt_stk[2][4096];
static thread::stack::element_t s_aud_stk[4096];
static thread::stack::element_t s_led_stk[2048];
static thread::stack::element_t s_tel_stk[4096];

} // anonymous namespace

// ---------------------------------------------------------------------------
// OS Main
// ---------------------------------------------------------------------------
int
os_main (int, char*[])
{
  console ("\n+== µOS++ SMP PIPELINE TEST ==+\n");
  console ("13 threads, %u cores, shared queues, SD-card persistence & yield() stress\n\n",
           static_cast<unsigned> (OS_NCPU));

  if (!sd_prepare ())
    {
      return 1;
    }

  // Launch 13 threads with attributes & priorities
  thread::attributes a = thread::initializer;

  // Telemetry (High)
  a.th_stack_address = s_tel_stk; a.th_stack_size_bytes = sizeof (s_tel_stk);
  static thread t_tel { "telemetry", telemetry_thread, nullptr, a };
  t_tel.priority (thread::priority::high);

  // LED (Above Normal)
  a.th_stack_address = s_led_stk; a.th_stack_size_bytes = sizeof (s_led_stk);
  static thread t_led { "led", led_thread, nullptr, a };
  t_led.priority (thread::priority::above_normal);

  // 4 Producers (Normal)
  static thread* t_prod[4];
  static const char* prod_names[4] = { "prod0", "prod1", "prod2", "prod3" };
  for (unsigned i = 0; i < 4; ++i)
    {
      a.th_stack_address = s_prod_stk[i];
      a.th_stack_size_bytes = sizeof (s_prod_stk[i]);
      t_prod[i] = new thread (prod_names[i], producer_thread, reinterpret_cast<void*> (static_cast<std::uintptr_t> (i)), a);
      t_prod[i]->priority (thread::priority::normal);
    }

  // 4 Compute Workers (Normal)
  static thread* t_work[4];
  static const char* work_names[4] = { "work0", "work1", "work2", "work3" };
  for (unsigned i = 0; i < 4; ++i)
    {
      a.th_stack_address = s_work_stk[i];
      a.th_stack_size_bytes = sizeof (s_work_stk[i]);
      t_work[i] = new thread (work_names[i], worker_thread, reinterpret_cast<void*> (static_cast<std::uintptr_t> (i)), a);
      t_work[i]->priority (thread::priority::normal);
    }

  // 2 SD Writers (Normal - competing fairly with producers/workers)
  static thread* t_wrt[2];
  static const char* wrt_names[2] = { "sdwrt0", "sdwrt1" };
  for (unsigned i = 0; i < 2; ++i)
    {
      a.th_stack_address = s_wrt_stk[i];
      a.th_stack_size_bytes = sizeof (s_wrt_stk[i]);
      t_wrt[i] = new thread (wrt_names[i], sd_writer_thread, reinterpret_cast<void*> (static_cast<std::uintptr_t> (i)), a);
      t_wrt[i]->priority (thread::priority::normal);
    }

  // 1 SD Auditor (Normal)
  a.th_stack_address = s_aud_stk; a.th_stack_size_bytes = sizeof (s_aud_stk);
  static thread t_aud { "auditor", sd_auditor_thread, nullptr, a };
  t_aud.priority (thread::priority::normal);

  console ("13 pipeline threads successfully started!\n");
  const std::uint32_t run_ms = static_cast<std::uint32_t> (RUN_MS);
  console ("running pipeline for %u ms ...\n", run_ms);

  const std::uint32_t start_ms = static_cast<std::uint32_t> (sysclock.now ());
  while (static_cast<std::uint32_t> (sysclock.now ()) - start_ms < run_ms)
    {
      sysclock.sleep_for (200);
    }

  // Stop threads
  console ("\nstopping pipeline threads...\n");
  g_finish = true;
  sysclock.sleep_for (200);

  // Flush semaphores so blocked threads exit
  for (unsigned i = 0; i < 32; ++i)
    {
      g_in_spaces.post ();
      g_in_items.post ();
      g_sd_spaces.post ();
      g_sd_items.post ();
      g_audit_sem.post ();
    }
  sysclock.sleep_for (200);

  // Statistics verification
  const std::uint32_t prod_total = g_total_produced.load ();
  const std::uint32_t proc_total = g_total_processed.load ();
  const std::uint32_t wrt_total  = g_total_written.load ();
  const std::uint32_t aud_total  = g_total_audited.load ();

  const std::uint32_t y_prod = g_yield_prod.load ();
  const std::uint32_t y_work = g_yield_work.load ();
  const std::uint32_t y_comp = g_yield_compute.load ();
  const std::uint32_t y_wrt  = g_yield_writer.load ();
  const std::uint32_t y_aud  = g_yield_auditor.load ();
  const std::uint32_t y_all  = y_prod + y_work + y_comp + y_wrt + y_aud;

  const std::uint32_t crc_err = g_crc_errors.load ();
  const std::uint32_t seq_err = g_seq_errors.load ();
  const std::uint32_t wrt_err = g_write_errors.load ();

  console ("\n================ Pipeline Test Summary ================\n");
  console ("Records Produced:  %u\n", prod_total);
  console ("Records Processed: %u\n", proc_total);
  console ("Records Written:   %u\n", wrt_total);
  console ("Records Audited:   %u\n", aud_total);
  console ("Errors: CRC=%u, Sequence=%u, Write=%u\n", crc_err, seq_err, wrt_err);
  console ("Yield Calls Breakdown:\n");
  console ("  Producer yield backpressure: %u\n", y_prod);
  console ("  Worker queue wait yields:    %u\n", y_work);
  console ("  Compute chunking yields:     %u\n", y_comp);
  console ("  SD writer turn yields:       %u\n", y_wrt);
  console ("  Auditor chunk read yields:   %u\n", y_aud);
  console ("  Total yield() calls:         %u\n", y_all);
  // One line per counter, every core in it.
  auto per_core = [] (const char* title, const auto& counters)
    {
      char line[128];
      int n = std::snprintf (line, sizeof (line), "%s:", title);
      for (unsigned c = 0; c < OS_NCPU && n > 0 && n < (int)sizeof (line); ++c)
        {
          n += std::snprintf (line + n, sizeof (line) - (unsigned)n, " c%u=%u",
                              c, (unsigned)counters[c].load ());
        }
      console ("%s\n", line);
    };
  per_core ("Yields by Core", g_yield_by_core);
  per_core ("Produced by Core", g_prod_by_core);
  per_core ("Processed by Core", g_proc_by_core);
  console ("=======================================================\n");

  auto some_core_processed = [] ()
    {
      for (unsigned c = 0; c < OS_NCPU; ++c)
        {
          if (g_proc_by_core[c] > 0)
            {
              return true;
            }
        }
      return false;
    };
  const bool pass = (aud_total >= 20)
                    && (crc_err == 0)
                    && (seq_err == 0)
                    && (wrt_err == 0)
                    && (y_all >= 50)
                    && some_core_processed ();

  return pass ? 0 : 1;
}
