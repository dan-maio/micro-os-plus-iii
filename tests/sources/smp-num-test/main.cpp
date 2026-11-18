/*
 * smp-num-test -- µOS++ multi-thread I/O demo.
 *
 * Five concurrent worker threads with EXPLICIT priorities (highest first):
 *
 *   1. uart-writer      (prio high)          : console tick every 0.5 s
 *   2. led-blinker      (prio above_normal)  : the pacer: 5 blinks of the
 *                                              board's LED per pass, 0.3 s
 *                                              on / 0.3 s off, printing "led
 *                                              on"/"led off" on every edge
 *   3. sd-text-writer   (prio normal)        : 20 lines of ~100 chars appended
 *                                              to num.txt on the SD card
 *   4. fp-compute       (prio below_normal)  : 20 sin/cos/log results appended
 *                                              to num.txt (as chars)
 *   5. sd-reader        (prio low)           : after each writer pass, reads
 *                                              num.txt and streams the new tail
 *
 * Synchronisation: every access to num.txt is serialised with one mutex, and
 * the LED thread paces the passes with a counting semaphore (3 posts per pass:
 * one for each writer, one for the reader).
 *
 * Storage: /sd/tests/num.txt, through µOS++ POSIX I/O, on the card's FAT
 * volume (the posix-io block device /dev/sd with Chan FatFs, mounted at /sd/
 * before os_main() by board-tests/portable-test-storage.cpp). The same path
 * on hardware (the boot card, never formatted), under QEMU and on the host
 * (an MBR + FAT32 image).
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

#include <atomic>
#include <cerrno>
#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>



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

// Serialises console output (uart1 is not re-entrant across cores).

// ---------------------------------------------------------------------------
// Console helpers. console() writes to the UART and (on a SEMIHOST build)
// mirrors to the semihosting channel, so banners/status/LED edges reach the
// emulator or OpenOCD log. console_uart() is UART-only: the high-volume lines
// (file-content streams, per-tick status) would otherwise cost one trap each.
// ---------------------------------------------------------------------------
// Repetitive/high-volume lines (file-content streams, per-tick status).
// ---------------------------------------------------------------------------
// Run control / iteration counts
// ---------------------------------------------------------------------------
// Wall-clock run length in ms (-DRUN_MS=... to change it). 15 s: about five
// passes of the pacer, enough for every thread to write, compute and read
// several times; 60 s made the board run (and its console) needlessly long.
#ifndef RUN_MS
#define RUN_MS 15000
#endif
constexpr unsigned kTextLines = 20;    // SD text lines per pass
constexpr unsigned kComputeLines = 20; // FPU compute lines per pass
constexpr unsigned kLedBlinks = 5;     // LED blinks per pass (0.3 s each)

// ---------------------------------------------------------------------------
// Shared state
// ---------------------------------------------------------------------------
// num.txt, on the card's FAT volume.
static const char kNumFile[] = "/sd/tests/num.txt";

// The board's LED, driven by the led-blinker thread only.
static blink_led g_led;

// All num.txt access serialised by this mutex.
static mutex g_file_mtx { "file" };

// "Pass" beat. The LED thread posts 3 per LED pass (5 blinks); the two writers
// each take one to run their 20-line batch, and the reader takes one to dump
// the newly appended tail. This paces the batches to the LED (~3 s) so num.txt
// growth and console output stay bounded over the whole RUN_MS window.
static semaphore_counting g_beat { "beat", 3, 0 };

// Progress / result flags.
static std::atomic<unsigned> g_text_written{0};
static std::atomic<unsigned> g_calc_written{0};
static std::atomic<unsigned> g_text_fail{0};
static std::atomic<unsigned> g_calc_fail{0};
static std::atomic<unsigned> g_read_fail{0};
static std::atomic<unsigned> g_led_fail{0};

// Set by os_main just before RESULT so the infinite uart thread can exit.
static std::atomic<bool> g_finish{false};

// Whole-file read buffer (reader + final dump): num.txt grows over the
// RUN_MS window, ~1600 lines * ~110 B ~= 176 KB in 2 min; keep headroom.
static char g_read_buf[256 * 1024];

// Per-core count of appended lines (the "[cN]" of each write), for a summary.
static std::atomic<unsigned> g_core_lines[OS_NCPU]{};

// ---------------------------------------------------------------------------
// SD helpers. All called with g_file_mtx held.
// ---------------------------------------------------------------------------
bool
sd_append (const char* text, unsigned len)
{
  // Prepend "[cN] " where N is the core performing this write. sd_append is
  // always called with g_file_mtx held, so this is the core actually doing the
  // file I/O.
  char tagged[160];
  int tn = std::snprintf (tagged, sizeof (tagged), "[c%u] ",
                          (unsigned)port_cpu_id ());
  if (tn < 0)
    {
      tn = 0;
    }
  const unsigned core = (unsigned)port_cpu_id ();
  if (core < OS_NCPU)
    {
      ++g_core_lines[core];
    }
  if (static_cast<unsigned> (tn) + len > sizeof (tagged))
    {
      len = sizeof (tagged) - static_cast<unsigned> (tn);
    }
  std::memcpy (tagged + tn, text, len);

  os::posix::io* f
      = os::posix::open (kNumFile, O_WRONLY | O_CREAT | O_APPEND);
  if (f == nullptr)
    {
      return false;
    }
  const unsigned n = static_cast<unsigned> (tn) + len;
  const bool ok = (f->write (tagged, n) == static_cast<ssize_t> (n));
  return (f->close () == 0) && ok;
}

bool
sd_read_all (char* out, unsigned cap, unsigned& len)
{
  struct stat st;
  if (os::posix::stat (kNumFile, &st) != 0
      || static_cast<unsigned> (st.st_size) > cap)
    {
      return false;
    }
  const unsigned size = static_cast<unsigned> (st.st_size);
  os::posix::io* f = os::posix::open (kNumFile, O_RDONLY);
  if (f == nullptr)
    {
      return false;
    }
  const bool ok = (f->read (out, size) == static_cast<ssize_t> (size));
  f->close ();
  len = ok ? size : 0;
  return ok;
}

void
sd_remove_num ()
{
  // Delete num.txt if present so each run starts from an empty file.
  // A missing file is fine (nothing to remove); a real I/O error is ignored.
  os::posix::unlink (kNumFile);
  console ("  removed previous num.txt (if any)\n");
}

bool
sd_prepare ()
{
  // The volume the storage start-up mounted (it printed why, if it did not).
  struct statvfs vfs;
  if (os::posix::statvfs ("/sd/", &vfs) != 0)
    {
      console ("  no FAT volume mounted at /sd/ (errno %d)\n", errno);
      return false;
    }
  console ("  FAT volume at /sd/, num.txt in /sd/tests/.\n");
  return true;
}

// ---------------------------------------------------------------------------
// Thread 1: uart-writer (prio high)
// ---------------------------------------------------------------------------
static void*
uart_thread (void*)
{
  unsigned tick = 0;
  while (!g_finish)
    {
      console_uart ("[c%u][uart] tick %u  (text=%u calc=%u)\n",
                    (unsigned)port_cpu_id (), tick, (unsigned)g_text_written,
                    (unsigned)g_calc_written);
      ++tick;
      sysclock.sleep_for (500);
    }
  return nullptr;
}

// ---------------------------------------------------------------------------
// Thread 2: led-blinker (prio above_normal) — kLedBlinks blinks @ 0.3 s
// ---------------------------------------------------------------------------
static void*
led_thread (void*)
{
  // One pass = kLedBlinks blinks. After the pass, release one batch slot to
  // each writer and one to the reader (3 posts total), then repeat until the
  // run window ends.
  while (!g_finish)
    {
      for (unsigned i = 0; i < kLedBlinks; ++i)
        {
          g_led.turn_on ();
          console ("[c%u] led on\n", (unsigned)port_cpu_id ());
          sysclock.sleep_for (300);
          g_led.turn_off ();
          console ("[c%u] led off\n", (unsigned)port_cpu_id ());
          sysclock.sleep_for (300);
        }
      g_beat.post ();
      g_beat.post ();
      g_beat.post ();
    }
  console ("[c%u] LED stopped\n", (unsigned)port_cpu_id ());
  return nullptr;
}

// Keeps a worker CPU-bound (no sleeping) for a while so the no-affinity
// scheduler can spread ready threads onto idle cores 2/3, as in smp_test4.
void
cpu_burn_yield ()
{
  volatile float acc = 1.0f;
  for (unsigned k = 0; k < 80000u; ++k)
    {
      acc = acc * 1.000001f + 0.000001f;
    }
  (void)acc;
  this_thread::yield ();
}

// ---------------------------------------------------------------------------
// Thread 3: sd-text-writer (prio normal) — kTextLines ~100-char lines
// ---------------------------------------------------------------------------
static void*
sd_text_thread (void*)
{
  unsigned pass = 0;
  while (!g_finish)
    {
      // Wait for the next LED beat (one text batch per pass).
      while (!g_finish && g_beat.try_wait () != result::ok)
        {
          sysclock.sleep_for (10);
        }
      if (g_finish)
        {
          break;
        }
      for (unsigned i = 0; i < kTextLines; ++i)
        {
          // ~100-char, LETTERS-ONLY body (no digits, so it stays visually
          // distinct from the numeric CALC lines). sd_append() prefixes it
          // with the core tag "[cN] ". Vary by cycling the filler word.
          static const char* const kFill[4]
              = { "lorem", "ipsum", "dolor", "amet" };
          const char* fill = kFill[i & 3u];
          static const char kHead[]
              = "TEXT the quick brown fox jumps over the lazy dog ";
          char line[128];
          unsigned pos = 0;
          const unsigned head_len = sizeof (kHead) - 1u;
          std::memcpy (line, kHead, head_len);
          pos = head_len;
          // Pad with "word-..." until ~96 chars.
          while (pos < 96u)
            {
              for (const char* p = fill; *p && pos < 96u; ++p)
                {
                  line[pos++] = *p;
                }
              if (pos < 96u)
                {
                  line[pos++] = '-';
                }
            }
          // Trim a trailing '-' and append the alphabetic terminator.
          if (pos > 0u && line[pos - 1u] == '-')
            {
              --pos;
            }
          static const char kTail[] = " END\n";
          const unsigned tail_len = sizeof (kTail) - 1u;
          std::memcpy (line + pos, kTail, tail_len);
          pos += tail_len;

          g_file_mtx.lock ();
          bool ok = sd_append (line, pos);
          if (ok)
            {
              ++g_text_written;
            }
          else
            {
              ++g_text_fail;
            }
          g_file_mtx.unlock ();
          // Stay runnable (CPU burn + yield, no sleep) so idle cores 2/3 can
          // claim this thread; sleeping would pin it to core 0.
          cpu_burn_yield ();
        }
      ++pass;
    }
  return nullptr;
}

// ---------------------------------------------------------------------------
// Thread 4: fp-compute (prio below_normal) — kComputeLines sin/cos/log lines
// ---------------------------------------------------------------------------
static void*
compute_thread (void*)
{
  unsigned pass = 0;
  while (!g_finish)
    {
      // Wait for the next LED beat (one compute batch per pass).
      while (!g_finish && g_beat.try_wait () != result::ok)
        {
          sysclock.sleep_for (10);
        }
      if (g_finish)
        {
          break;
        }
      for (unsigned i = 0; i < kComputeLines; ++i)
        {
          const float x = 0.1f + 0.37f * static_cast<float> (i);
          const float s = std::sin (x);
          const float c = std::cos (x);
          const float l = (x > 0.0f) ? std::log (x) : 0.0f;
          char line[160];
          int n = std::snprintf (line, sizeof (line),
                                 "CALC %03u: sin(%.3f)=%+.6f cos(%.3f)=%+.6f "
                                 "log(%.3f)=%+.6f\n",
                                 i, (double)x, (double)s, (double)x, (double)c,
                                 (double)x, (double)l);
          if (n < 0)
            {
              n = 0;
            }
          g_file_mtx.lock ();
          bool ok = sd_append (line, static_cast<unsigned> (n));
          if (ok)
            {
              ++g_calc_written;
            }
          else
            {
              ++g_calc_fail;
            }
          g_file_mtx.unlock ();
          // Stay runnable (CPU burn + yield, no sleep) so idle cores 2/3 can
          // claim this thread; sleeping would keep it on core 0.
          cpu_burn_yield ();
        }
      ++pass;
    }
  return nullptr;
}

// ---------------------------------------------------------------------------
// Thread 5: sd-reader (prio low) — stream the newly appended tail of num.txt
// ---------------------------------------------------------------------------
static void*
reader_thread (void*)
{
  unsigned last_len = 0;
  unsigned pass = 0;
  while (!g_finish)
    {
      // One reader slot per LED pass.
      while (!g_finish && g_beat.try_wait () != result::ok)
        {
          sysclock.sleep_for (10);
        }
      if (g_finish)
        {
          break;
        }
      sysclock.sleep_for (20); // let the writers' last writes land

      unsigned len = 0;
      g_file_mtx.lock ();
      bool ok = sd_read_all (g_read_buf, sizeof (g_read_buf), len);
      g_file_mtx.unlock ();
      if (!ok)
        {
          ++g_read_fail;
          console ("[c%u][reader] read num.txt FAILED\n",
                   (unsigned)port_cpu_id ());
          continue;
        }
      if (len < last_len)
        {
          last_len = 0; // num.txt was removed/recreated: dump from the start
        }
      console ("[c%u][reader] pass %u: num.txt now %u bytes (+%u)\n",
               (unsigned)port_cpu_id (), pass, len, len - last_len);
      // Stream only the newly appended tail to the UART.
      constexpr unsigned kChunk = 128;
      for (unsigned off = last_len; off < len; off += kChunk)
        {
          char tmp[kChunk + 1];
          unsigned n = len - off;
          if (n > kChunk)
            {
              n = kChunk;
            }
          std::memcpy (tmp, g_read_buf + off, n);
          tmp[n] = '\0';
          // Under the console mutex, as every other line: the stream must
          // not interleave with the other threads' output.
          console_mutex ().lock ();
          std::fputs (tmp, stdout);
          std::fflush (stdout);
          console_mutex ().unlock ();
          this_thread::yield ();
        }
      last_len = len;
      ++pass;
    }
  console ("[c%u][reader] stopped after %u dumps\n", (unsigned)port_cpu_id (),
           pass);
  return nullptr;
}

// ---------------------------------------------------------------------------
// Startup scaffolding (idle threads, main trampoline)
// ---------------------------------------------------------------------------
} // namespace (anonymous)

static thread::stack::element_t uart_stk[4096];
static thread::stack::element_t led_stk[4096];
static thread::stack::element_t text_stk[4096];
static thread::stack::element_t calc_stk[8192];
static thread::stack::element_t reader_stk[8192];

int
os_main (int, char*[])
{
  console ("\n+== µOS++ NUM TEST : console + pacer + SD + FPU, %u cores ==+\n\n",
           static_cast<unsigned> (OS_NCPU));
  g_led.power_up ();
  if (!sd_prepare ())
    {
      return 1;
    }
  sd_remove_num ();

  // Threads, with explicit priorities (high -> low as listed above).
  thread::attributes a = thread::initializer;

  a.th_stack_address = uart_stk; a.th_stack_size_bytes = sizeof (uart_stk);
  static thread t_uart { "uart", uart_thread, nullptr, a };
  t_uart.priority (thread::priority::high);

  a.th_stack_address = led_stk; a.th_stack_size_bytes = sizeof (led_stk);
  static thread t_led { "led", led_thread, nullptr, a };
  t_led.priority (thread::priority::above_normal);

  a.th_stack_address = text_stk; a.th_stack_size_bytes = sizeof (text_stk);
  static thread t_text { "sdtext", sd_text_thread, nullptr, a };
  t_text.priority (thread::priority::normal);

  a.th_stack_address = calc_stk; a.th_stack_size_bytes = sizeof (calc_stk);
  static thread t_calc { "compute", compute_thread, nullptr, a };
  t_calc.priority (thread::priority::below_normal);

  a.th_stack_address = reader_stk; a.th_stack_size_bytes = sizeof (reader_stk);
  static thread t_read { "sdread", reader_thread, nullptr, a };
  t_read.priority (thread::priority::low);

  console ("threads started (uart=high, led=above_normal, text=normal, "
           "compute=below_normal, reader=low)\n");

  // Run the repeating passes for the wall-clock window (default 1 minute).
  const std::uint32_t start_ms = static_cast<std::uint32_t> (sysclock.now ());
  const std::uint32_t run_ms = static_cast<std::uint32_t> (RUN_MS);
  console ("running for %u ms ...\n", run_ms);
  while (static_cast<std::uint32_t> (sysclock.now ()) - start_ms < run_ms)
    {
      sysclock.sleep_for (100);
    }

  // Stop the workers.
  g_finish = true;
  sysclock.sleep_for (200); // let threads see the flag and unwind
  g_beat.post ();           // wake any writer/reader still blocked on a beat
  g_beat.post ();
  g_beat.post ();
  sysclock.sleep_for (200);

  // Final dump of num.txt on the UART at the end of the run.
  {
    unsigned len = 0;
    g_file_mtx.lock ();
    const bool rd = sd_read_all (g_read_buf, sizeof (g_read_buf), len);
    g_file_mtx.unlock ();
    if (rd)
      {
        console ("\n---- num.txt on SD (%u bytes, final dump) ----\n", len);
        for (unsigned off = 0; off < len; off += 128)
          {
            char tmp[129];
            unsigned n = len - off;
            if (n > 128)
              {
                n = 128;
              }
            std::memcpy (tmp, g_read_buf + off, n);
            tmp[n] = '\0';
            console_mutex ().lock ();
            std::fputs (tmp, stdout);
            std::fflush (stdout);
            console_mutex ().unlock ();
          }
        console ("---- end num.txt ----\n");
      }
    else
      {
        ++g_read_fail;
        console ("[main] final num.txt read FAILED\n");
      }
  }

  const bool ok = (g_text_written >= kTextLines)
                  && (g_calc_written >= kComputeLines) && (g_text_fail == 0)
                  && (g_calc_fail == 0) && (g_read_fail == 0)
                  && (g_led_fail == 0);
  {
    char line[96];
    int n = std::snprintf (line, sizeof (line), "num.txt lines by core:");
    for (unsigned c = 0; c < OS_NCPU && n > 0 && n < (int)sizeof (line); ++c)
      {
        n += std::snprintf (line + n, sizeof (line) - (unsigned)n, " c%u=%u", c,
                            (unsigned)g_core_lines[c]);
      }
    console ("%s\n", line);
  }
  console ("run %u ms, text=%u calc=%u\n", run_ms, (unsigned)g_text_written,
           (unsigned)g_calc_written);
  return ok ? 0 : 1;
}
