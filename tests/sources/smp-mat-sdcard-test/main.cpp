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

/*
 * smp-mat-sdcard-test -- the parallel block linear equation solver of
 * smp-mat-test, N x N (default 200, block size B = 20), on OS_NCPU cores,
 * with the MATRICES STORED ON THE SD CARD instead of only in RAM.
 *
 * The coefficient matrix A (N x N float32) and the right-hand side b are
 * files on the card, in /sd/tests/:
 *
 *     A.mat        row-major float32 N x N matrix
 *     b.mat        float32 N-vector
 *     x_block.mat  the block solver's solution, written back
 *     xclassic.mat the classical solver's solution, written back
 *
 * Flow (os_main does all the file I/O; the solver cores work in RAM):
 *   1. check the card's FAT volume at /sd/ (mounted before os_main() on the
 *      posix-io block device /dev/sd with Chan FatFs, by
 *      board-tests/portable-test-storage.cpp); on a boot card the boot files
 *      are never touched and nothing is formatted;
 *   2. a Thread-Pool demo (10 workers, 20 tasks) across the cores;
 *   3. generate a diagonally dominant A and b in RAM, STORE them to A.mat and
 *      b.mat, and LOAD the solver's working copy and the classical solver's
 *      copy back from the card (the solvers' data comes off the SD card);
 *   4. the PARALLEL BLOCK elimination (row blocks round-robin over the cores,
 *      generation-based spin barriers, core 0 doing the diagonal LU and the
 *      back substitution) -> x_block;
 *   5. the CLASSICAL N x N LU solve on core 0, as ground truth -> x_classic;
 *   6. compare the two (max/sum absolute difference), the residuals
 *      ||A x - b||, the times and the speedup, then STORE both solutions on
 *      the card and read x_block back to check the round trip.
 *
 * One copy for the AArch boards: it was a copy per board in the architecture
 * ports (test/<board>/), FatFs R0.15a on hardware and flatfs under QEMU. The
 * card is now reached the same way everywhere, through µOS++ POSIX I/O.
 *
 * A portable test: os_main() only, the µOS++ interfaces only. The platform
 * brings the board and the secondary cores up before os_main() and prints the
 * RESULT line from its return value (board-tests/portable-test-end.cpp).
 */

#include <cmsis-plus/rtos/os.h>
#include <cmsis-plus/posix-io/directory.h>
#include <cmsis-plus/posix-io/file-system.h>
#include <cmsis-plus/posix-io/io.h>
#include <cmsis-plus/posix/sys/statvfs.h>

#include <fcntl.h>
#include <sys/stat.h>

#include <cerrno>


#include <algorithm>
#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

// The board's LED (upstream's blinky interface): it blinks while the
// parallel solver runs.
#include <blink-led.h>


using namespace os::rtos;

extern "C" unsigned port_cpu_id (void);

// ----------------------------------------------------------------------------
// Microsecond clock, from the kernel's high-resolution clock (hrclock).
// Microseconds fit in 32 bits for this test.
// ----------------------------------------------------------------------------
namespace
{
  // The kernel's high-resolution clock: on the AArch ports the ARM generic
  // timer, on the host CLOCK_MONOTONIC. Integer ticks per microsecond, as the
  // test always scaled it.
  std::uint64_t g_ticks_per_us = 1; // set in timer_init()

  void
  timer_init (void)
  {
    const std::uint64_t f = hrclock.input_clock_frequency_hz ();
    g_ticks_per_us = (f >= 1000000U) ? (f / 1000000U) : 1U;
  }

  inline std::uint32_t
  timer_us32 (void)
  {
    return static_cast<std::uint32_t> (hrclock.now () / g_ticks_per_us);
  }

  // ---- Console helpers -----------------------------------------------------
  // stdout is one stream for every core: the pool workers print too.
  mutex&
  out_mutex (void)
  {
    static mutex m{ "out" };
    return m;
  }

  void
  write_str (const char* s)
  {
    out_mutex ().lock ();
    std::fputs (s, stdout);
    // Written out while the mutex is held (two cores' lines would otherwise
    // interleave when the C library flushes its buffer later).
    std::fflush (stdout);
    out_mutex ().unlock ();
  }

  void
  write_fmt (const char* fmt, ...)
  {
    char b[96];
    std::va_list args;
    va_start (args, fmt);
    int n = std::vsnprintf (b, sizeof (b), fmt, args);
    va_end (args);
    if (n < 0)
      {
        n = 0;
      }
    if (n > static_cast<int> (sizeof (b)) - 1)
      {
        n = static_cast<int> (sizeof (b)) - 1;
      }
    write_str (b);
  }

  void
  print_float (float val)
  {
    char b[32];
    if (val < 0.0f)
      {
        write_str ("-");
        val = -val;
      }
    int int_part = static_cast<int> (val);
    int frac_part
        = static_cast<int> ((val - int_part) * 1000000.0f + 0.5f);
    if (frac_part >= 1000000)
      {
        int_part = int_part + 1;
        frac_part = frac_part - 1000000;
      }
    int n = std::snprintf (b, sizeof (b), "%d.%06d", int_part, frac_part);
    write_str (b);
  }

  void
  print_time_us (double time_us)
  {
    char b[32];
    int int_part = static_cast<int> (time_us);
    int frac_part
        = static_cast<int> ((time_us - int_part) * 1000.0 + 0.5);
    if (frac_part >= 1000)
      {
        int_part = int_part + 1;
        frac_part = frac_part - 1000;
      }
    int n = std::snprintf (b, sizeof (b), "%d.%03d us", int_part, frac_part);
    write_str (b);
  }

  void
  print_ratio (double ratio)
  {
    char b[32];
    int int_part = static_cast<int> (ratio);
    int frac_part
        = static_cast<int> ((ratio - int_part) * 1000.0 + 0.5);
    if (frac_part >= 1000)
      {
        int_part = int_part + 1;
        frac_part = frac_part - 1000;
      }
    int n = std::snprintf (b, sizeof (b), "%d.%03d", int_part, frac_part);
    write_str (b);
  }
}

// ----------------------------------------------------------------------------
// Solver dimensions
// ----------------------------------------------------------------------------
// The problem size; a platform with more memory sets a bigger one (the host).
#ifndef SMP_MAT_N
#define SMP_MAT_N 200
#endif
#ifndef SMP_MAT_B
#define SMP_MAT_B 20
#endif
#define N SMP_MAT_N
#define B SMP_MAT_B

// ----------------------------------------------------------------------------
// Generation-based spin barrier. On the Cortex-A53 the global exclusive monitor
// makes LDREX/STREX genuinely cross-core, so the internal lock is a plain
// __atomic_test_and_set flag (compiles to ldaxrb/stlxrb) — no SIO spinlock.
// ----------------------------------------------------------------------------
class Barrier
{
public:
  void
  init (int count, std::uint32_t /*unused_slot*/)
  {
    target_count = count;
    current_count = 0;
    generation = 0;
    lock_ = 0;
  }

  void
  wait (void)
  {
    // A full barrier. __atomic_thread_fence emits exactly "dmb ish" on
    // ARMv8-A and "dmb" on ARMv7-A -- the same instruction this line always
    // was -- and the right one on a host, which has no such mnemonic. The
    // lock below is already a GCC atomic builtin; this makes the pair of
    // fences around it the same kind of thing.
    __atomic_thread_fence (__ATOMIC_SEQ_CST);
    int gen = generation;

    while (__atomic_test_and_set (&lock_, __ATOMIC_ACQUIRE))
      {
        this_thread::yield ();
      }

    current_count = current_count + 1;
    if (current_count == target_count)
      {
        current_count = 0;
        generation = generation + 1;
        __atomic_clear (&lock_, __ATOMIC_RELEASE);
      }
    else
      {
        __atomic_clear (&lock_, __ATOMIC_RELEASE);
        while (generation == gen)
          {
            this_thread::yield ();
          }
      }

    // A full barrier. __atomic_thread_fence emits exactly "dmb ish" on
    // ARMv8-A and "dmb" on ARMv7-A -- the same instruction this line always
    // was -- and the right one on a host, which has no such mnemonic. The
    // lock below is already a GCC atomic builtin; this makes the pair of
    // fences around it the same kind of thing.
    __atomic_thread_fence (__ATOMIC_SEQ_CST);
  }

private:
  int target_count;
  volatile int current_count;
  volatile int generation;
  volatile unsigned char lock_;
};

// ----------------------------------------------------------------------------
// Thread Pool (10 workers, cross-core tasks)
// ----------------------------------------------------------------------------
typedef void (*task_t) (void* arg);

struct Task
{
  task_t func;
  void* arg;
};

#define POOL_SIZE 10
#define TASK_QUEUE_SIZE 32

class ThreadPool
{
public:
  ThreadPool ()
      : sem_tasks_ ("pool_tasks", TASK_QUEUE_SIZE, 0),
        sem_free_ ("pool_free", TASK_QUEUE_SIZE, TASK_QUEUE_SIZE)
  {
    head_ = 0;
    tail_ = 0;
    count_ = 0;
  }

  void start ();
  bool submit (task_t func, void* arg);
  void worker_loop ();

private:
  Task queue_[TASK_QUEUE_SIZE];
  int head_;
  int tail_;
  int count_;

  mutex mutex_;
  semaphore_counting sem_tasks_;
  semaphore_counting sem_free_;
};

static ThreadPool g_pool;
static char pool_thread_names[POOL_SIZE][16];
static thread::stack::element_t pool_stacks[POOL_SIZE][512];
static thread* pool_threads[POOL_SIZE];

static void*
pool_worker_func (void* arg)
{
  ThreadPool* pool = static_cast<ThreadPool*> (arg);
  pool->worker_loop ();
  return nullptr;
}

void
ThreadPool::start ()
{
  for (int i = 0; i < POOL_SIZE; ++i)
    {
      thread::attributes attr = thread::initializer;
      attr.th_stack_address = pool_stacks[i];
      attr.th_stack_size_bytes = sizeof (pool_stacks[i]);

      std::snprintf (pool_thread_names[i], 16, "pool_%02d", i);

      pool_threads[i]
          = new thread (pool_thread_names[i], pool_worker_func, this, attr);
      // Alternate workers across the two cores.
      pool_threads[i]->cpu_affinity (1u << (i % OS_NCPU));
    }
}

bool
ThreadPool::submit (task_t func, void* arg)
{
  sem_free_.wait ();

  mutex_.lock ();
  queue_[tail_].func = func;
  queue_[tail_].arg = arg;
  tail_ = (tail_ + 1) % TASK_QUEUE_SIZE;
  count_ = count_ + 1;
  mutex_.unlock ();

  sem_tasks_.post ();
  return true;
}

void
ThreadPool::worker_loop ()
{
  while (true)
    {
      sem_tasks_.wait ();

      mutex_.lock ();
      Task task = queue_[head_];
      head_ = (head_ + 1) % TASK_QUEUE_SIZE;
      count_ = count_ - 1;
      mutex_.unlock ();

      sem_free_.post ();

      if (task.func)
        {
          task.func (task.arg);
        }
    }
}

static volatile int g_pool_task_count = 0;
static mutex g_pool_print_mutex;

static void
pool_demo_task (void* arg)
{
  int id = static_cast<int> (reinterpret_cast<intptr_t> (arg));
  volatile int sum = 0;
  for (int i = 0; i < 10000; ++i)
    {
      sum = sum + i;
    }
  g_pool_print_mutex.lock ();
  write_fmt ("Thread Pool: Worker executed task %d on CPU %u\n", id,
             port_cpu_id ());
  g_pool_task_count = g_pool_task_count + 1;
  g_pool_print_mutex.unlock ();
}

// ----------------------------------------------------------------------------
// Solver globals
// ----------------------------------------------------------------------------
static Barrier g_barrier_lu;
static Barrier g_barrier_step;
static volatile bool g_solver_done = false;
static volatile std::uint32_t g_block_start_us = 0;
static volatile std::uint32_t g_block_end_us = 0;

static float A[N][N];
static float b[N];

static float A_block[N][N];
static float b_block[N];
static float x_block[N];

static float x_classic[N];

// The classical solver's copy, also loaded from the SD card.
static float A_classic[N][N];
static float b_classic[N];

static float LU_k_T[B][B];
static int pivot_k_T[B];

static thread::stack::element_t solver_stacks[OS_NCPU][1024];
static thread* solver_threads[OS_NCPU];
static char solver_thread_names[OS_NCPU][16];

// ----------------------------------------------------------------------------
// LU utilities for B x B blocks
// ----------------------------------------------------------------------------
static bool
lu_decompose (const float M[B][B], float LU[B][B], int pivot[B])
{
  for (int i = 0; i < B; ++i)
    {
      for (int j = 0; j < B; ++j)
        {
          LU[i][j] = M[i][j];
        }
      pivot[i] = i;
    }
  for (int i = 0; i < B; ++i)
    {
      float max_val = 0.0f;
      int max_row = i;
      for (int r = i; r < B; ++r)
        {
          float val = std::abs (LU[r][i]);
          if (val > max_val)
            {
              max_val = val;
              max_row = r;
            }
        }
      if (max_val < 1e-9f)
        {
          return false; // Singular
        }
      if (max_row != i)
        {
          std::swap (pivot[i], pivot[max_row]);
          for (int c = 0; c < B; ++c)
            {
              std::swap (LU[i][c], LU[max_row][c]);
            }
        }
      for (int r = i + 1; r < B; ++r)
        {
          float factor = LU[r][i] / LU[i][i];
          LU[r][i] = factor;
          for (int c = i + 1; c < B; ++c)
            {
              LU[r][c] = LU[r][c] - factor * LU[i][c];
            }
        }
    }
  return true;
}

static void
lu_solve (const float LU[B][B], const int pivot[B], const float Y[B],
          float X[B])
{
  float temp[B];
  for (int i = 0; i < B; ++i)
    {
      temp[i] = Y[pivot[i]];
      for (int j = 0; j < i; ++j)
        {
          temp[i] = temp[i] - LU[i][j] * temp[j];
        }
    }
  for (int i = B - 1; i >= 0; --i)
    {
      X[i] = temp[i];
      for (int j = i + 1; j < B; ++j)
        {
          X[i] = X[i] - LU[i][j] * X[j];
        }
      X[i] = X[i] / LU[i][i];
    }
}

// Solve A_T * M_T = Src_T and transpose the result back to Dest.
static void
solve_block_transpose (const float LU_T[B][B], const int pivot_T[B],
                       const float Src[B][B], float Dest[B][B],
                       float Src_T[B][B], float M_T[B][B])
{
  for (int i = 0; i < B; ++i)
    {
      for (int j = 0; j < B; ++j)
        {
          Src_T[i][j] = Src[j][i];
        }
    }
  for (int col = 0; col < B; ++col)
    {
      float y[B];
      float x[B];
      for (int r = 0; r < B; ++r)
        {
          y[r] = Src_T[r][col];
        }
      lu_solve (LU_T, pivot_T, y, x);
      for (int r = 0; r < B; ++r)
        {
          M_T[r][col] = x[r];
        }
    }
  for (int i = 0; i < B; ++i)
    {
      for (int j = 0; j < B; ++j)
        {
          Dest[i][j] = M_T[j][i];
        }
    }
}

static void
mat_mul_sub (const float M[B][B], const float X[B][B], float Dest[B][B])
{
  for (int i = 0; i < B; ++i)
    {
      for (int j = 0; j < B; ++j)
        {
          float sum = 0.0f;
          for (int k = 0; k < B; ++k)
            {
              sum = sum + M[i][k] * X[k][j];
            }
          Dest[i][j] = Dest[i][j] - sum;
        }
    }
}

static void
vec_mul_sub (const float M[B][B], const float v[B], float Dest[B])
{
  for (int i = 0; i < B; ++i)
    {
      float sum = 0.0f;
      for (int k = 0; k < B; ++k)
        {
          sum = sum + M[i][k] * v[k];
        }
      Dest[i] = Dest[i] - sum;
    }
}

static void
get_matrix_block (const float Src[N][N], int br, int bc, float Dest[B][B])
{
  for (int i = 0; i < B; ++i)
    {
      for (int j = 0; j < B; ++j)
        {
          Dest[i][j] = Src[br * B + i][bc * B + j];
        }
    }
}

static void
set_matrix_block (float Dest[N][N], int br, int bc, const float Src[B][B])
{
  for (int i = 0; i < B; ++i)
    {
      for (int j = 0; j < B; ++j)
        {
          Dest[br * B + i][bc * B + j] = Src[i][j];
        }
    }
}

// ----------------------------------------------------------------------------
// Per-core solver worker (block parallel elimination)
// ----------------------------------------------------------------------------
static void*
solver_thread_func (void* arg)
{
  int core_id = static_cast<int> (reinterpret_cast<intptr_t> (arg));
  int num_blocks = N / B;

  // Per-core workspace (static to keep thread stacks tiny). A_kj doubles as
  // the A_ik scratch: it is only needed again after solve_block_transpose.
  static float workspace_Src_T[OS_NCPU][B][B];
  static float workspace_M_T[OS_NCPU][B][B];
  static float M_local[OS_NCPU][B][B];
  static float A_kj[OS_NCPU][B][B];
  static float A_ij[OS_NCPU][B][B];

  if (core_id == 0)
    {
      g_block_start_us = timer_us32 ();
    }

  for (int k = 0; k < num_blocks - 1; ++k)
    {
      if (core_id == 0)
        {
          // Core 0: LU-decompose the diagonal block A_kk (transposed layout).
          static float A_kk_T[B][B];
          for (int i = 0; i < B; ++i)
            {
              for (int j = 0; j < B; ++j)
                {
                  A_kk_T[i][j] = A_block[k * B + j][k * B + i];
                }
            }
          lu_decompose (A_kk_T, LU_k_T, pivot_k_T);
        }

      g_barrier_lu.wait ();

      // All cores: compute multipliers + update their assigned row blocks.
      for (int i = k + 1; i < num_blocks; ++i)
        {
          if ((i - (k + 1)) % OS_NCPU == core_id)
            {
              // A_ik = A_block[i][k]
              get_matrix_block (A_block, i, k, A_kj[core_id]);
              solve_block_transpose (
                  LU_k_T, pivot_k_T, A_kj[core_id], M_local[core_id],
                  workspace_Src_T[core_id], workspace_M_T[core_id]);

              // A_ij = A_ij - M_ik * A_kj  for j > k
              for (int j = k + 1; j < num_blocks; ++j)
                {
                  get_matrix_block (A_block, k, j, A_kj[core_id]);
                  get_matrix_block (A_block, i, j, A_ij[core_id]);
                  mat_mul_sub (M_local[core_id], A_kj[core_id],
                               A_ij[core_id]);
                  set_matrix_block (A_block, i, j, A_ij[core_id]);
                }

              // b_i = b_i - M_ik * b_k
              vec_mul_sub (M_local[core_id], &b_block[k * B],
                           &b_block[i * B]);
            }
        }

      g_barrier_step.wait ();
    }

  // Final block k = num_blocks - 1: sequential back substitution (core 0).
  if (core_id == 0)
    {
      static float A_ii[B][B];
      static float LU_ii[B][B];
      static float A_ij_temp[B][B];
      static int pivot_ii[B];
      static float temp_bi[B];

      for (int i = num_blocks - 1; i >= 0; --i)
        {
          for (int r = 0; r < B; ++r)
            {
              temp_bi[r] = b_block[i * B + r];
            }
          for (int j = i + 1; j < num_blocks; ++j)
            {
              get_matrix_block (A_block, i, j, A_ij_temp);
              for (int r = 0; r < B; ++r)
                {
                  for (int c = 0; c < B; ++c)
                    {
                      temp_bi[r] = temp_bi[r]
                                   - A_ij_temp[r][c] * x_block[j * B + c];
                    }
                }
            }
          get_matrix_block (A_block, i, i, A_ii);
          lu_decompose (A_ii, LU_ii, pivot_ii);
          lu_solve (LU_ii, pivot_ii, temp_bi, &x_block[i * B]);
        }

      g_block_end_us = timer_us32 ();
      g_solver_done = true;
    }

  g_barrier_lu.wait (); // sync all cores at exit

  for (;;)
    {
      sysclock.sleep_for (10000);
    }
  return nullptr;
}

// ----------------------------------------------------------------------------
// Classical N x N LU solve (ground truth, core 0)
// ----------------------------------------------------------------------------
static bool
solve_classical (const float src_A[N][N], const float src_b[N],
                 float dest_x[N])
{
  static float LU[N][N];
  static int pivot[N];
  float temp[N];

  for (int i = 0; i < N; ++i)
    {
      for (int j = 0; j < N; ++j)
        {
          LU[i][j] = src_A[i][j];
        }
      pivot[i] = i;
    }

  for (int i = 0; i < N; ++i)
    {
      float max_val = 0.0f;
      int max_row = i;
      for (int r = i; r < N; ++r)
        {
          float val = std::abs (LU[r][i]);
          if (val > max_val)
            {
              max_val = val;
              max_row = r;
            }
        }
      if (max_val < 1e-9f)
        {
          return false; // Singular
        }
      if (max_row != i)
        {
          std::swap (pivot[i], pivot[max_row]);
          for (int c = 0; c < N; ++c)
            {
              std::swap (LU[i][c], LU[max_row][c]);
            }
        }
      for (int r = i + 1; r < N; ++r)
        {
          float factor = LU[r][i] / LU[i][i];
          LU[r][i] = factor;
          for (int c = i + 1; c < N; ++c)
            {
              LU[r][c] = LU[r][c] - factor * LU[i][c];
            }
        }
    }

  // Forward substitution (L * temp = b_pivoted).
  for (int i = 0; i < N; ++i)
    {
      temp[i] = src_b[pivot[i]];
      for (int j = 0; j < i; ++j)
        {
          temp[i] = temp[i] - LU[i][j] * temp[j];
        }
    }

  // Backward substitution (U * x = temp).
  for (int i = N - 1; i >= 0; --i)
    {
      dest_x[i] = temp[i];
      for (int j = i + 1; j < N; ++j)
        {
          dest_x[i] = dest_x[i] - LU[i][j] * dest_x[j];
        }
      dest_x[i] = dest_x[i] / LU[i][i];
    }

  return true;
}

// ----------------------------------------------------------------------------
// The SD card matrix store, through µOS++ POSIX I/O: the card's FAT volume,
// mounted at /sd/ before os_main() (board-tests/portable-test-storage.cpp).
// Only os_main uses it.
// ----------------------------------------------------------------------------

namespace
{
  constexpr const char* kFileA = "/sd/tests/A.mat";
  constexpr const char* kFileB = "/sd/tests/b.mat";
  constexpr const char* kFileXb = "/sd/tests/x_block.mat";
  constexpr const char* kFileXc = "/sd/tests/xclassic.mat";

  bool
  sd_mounted (void)
  {
    struct statvfs vfs;
    if (os::posix::statvfs ("/sd/", &vfs) != 0)
      {
        write_fmt ("  no FAT volume mounted at /sd/ (errno %d)\n", errno);
        return false;
      }
    write_fmt ("  FAT volume at /sd/: %u blocks of %u bytes, files in "
               "/sd/tests.\n",
               static_cast<unsigned> (vfs.f_blocks),
               static_cast<unsigned> (vfs.f_frsize));
    return true;
  }

  bool
  sd_store (const char* path, const void* data, std::size_t bytes)
  {
    os::posix::io* f = os::posix::open (path, O_WRONLY | O_CREAT | O_TRUNC);
    if (f == nullptr)
      {
        write_fmt ("    SD store %s: open failed (errno %d)\n", path, errno);
        return false;
      }
    const bool ok = (f->write (data, bytes) == static_cast<ssize_t> (bytes));
    if (!ok)
      {
        write_fmt ("    SD store %s: write failed (errno %d)\n", path, errno);
      }
    return (f->close () == 0) && ok;
  }

  bool
  sd_load (const char* path, void* data, std::size_t bytes)
  {
    struct stat st;
    if (os::posix::stat (path, &st) != 0
        || static_cast<std::size_t> (st.st_size) != bytes)
      {
        write_fmt ("    SD load %s: wrong/missing file\n", path);
        return false;
      }
    os::posix::io* f = os::posix::open (path, O_RDONLY);
    if (f == nullptr)
      {
        write_fmt ("    SD load %s: open failed (errno %d)\n", path, errno);
        return false;
      }
    const bool ok = (f->read (data, bytes) == static_cast<ssize_t> (bytes));
    f->close ();
    if (!ok)
      {
        write_fmt ("    SD load %s: read failed\n", path);
      }
    return ok;
  }

  void
  sd_list (void)
  {
    write_str ("\ntests/ contents:\n");
    os::posix::directory* dir = os::posix::opendir ("/sd/tests");
    if (dir == nullptr)
      {
        write_str ("    (opendir failed)\n");
        return;
      }
    for (dirent* e = dir->read (); e != nullptr; e = dir->read ())
      {
        write_fmt ("    %s\n", e->d_name);
      }
    dir->close ();
  }
} // namespace

// ----------------------------------------------------------------------------
// Main
// ----------------------------------------------------------------------------
// Create the per-core idle threads for the secondaries before releasing them.
int
os_main (int /*argc*/, char* /*argv*/[])
{
  using namespace os::rtos;

  this_thread::thread ().cpu_affinity (1u << 0);

  timer_init ();

  g_barrier_lu.init (OS_NCPU, 0);
  g_barrier_step.init (OS_NCPU, 0);
  g_solver_done = false;

  write_str ("\n");
  write_str ("=============================================\n");
  write_str ("  micro-os-plus-iii  smp-mat-sdcard-test\n");
  write_str ("  parallel block linear solver, matrices on SD\n");
  write_fmt ("  N = %d, B = %d, cores = %d\n", N, B, OS_NCPU);
  write_str ("=============================================\n");

  // ---- The SD card ---------------------------------------------------------
  write_str ("Checking the SD card...\n");
  if (!sd_mounted ())
    {
      write_str ("FATAL: SD card not available\n");
      return 1;
    }

  // ---- Thread Pool demo ----------------------------------------------------
  write_str ("Starting Thread Pool of 10 worker threads...\n");
  g_pool.start ();

  write_str ("Submitting 20 tasks to the Thread Pool...\n");
  for (int i = 0; i < 20; ++i)
    {
      g_pool.submit (pool_demo_task, reinterpret_cast<void*> (i));
    }

  while (g_pool_task_count < 20)
    {
      sysclock.sleep_for (10);
    }
  write_str ("Thread Pool demo finished. All 20 tasks executed successfully.\n\n");

  // ---- Validate blocks / generate the diagonally dominant system -----------
  if (N % B != 0)
    {
      write_fmt ("ERROR: N (%d) must be divisible by B (%d)!\n", N, B);
      return 1;
    }
  int num_blocks = N / B;
  // NOTE: num_blocks need NOT be a multiple of OS_NCPU — the round-robin row
  // assignment ((i-(k+1)) % OS_NCPU == core_id) simply distributes the blocks
  // unevenly. With N=200, B=20 -> 10 blocks over OS_NCPU cores.
  if (num_blocks % OS_NCPU != 0)
    {
      write_fmt ("NOTE: %d blocks over %d cores (uneven round-robin split).\n",
                 num_blocks, OS_NCPU);
    }

  write_fmt ("Generating diagonally dominant %d x %d matrix...\n", N, N);
  srand (42);
  for (int i = 0; i < N; ++i)
    {
      for (int j = 0; j < N; ++j)
        {
          A[i][j]
              = -5.0f + static_cast<float> (rand ())
                            / (static_cast<float> (RAND_MAX) / 10.0f);
        }
    }
  for (int i = 0; i < N; ++i)
    {
      float sum = 0.0f;
      for (int j = 0; j < N; ++j)
        {
          if (i != j)
            {
              sum = sum + std::abs (A[i][j]);
            }
        }
      A[i][i] = sum + 5.0f; // strictly diagonally dominant
      b[i] = 1.0f;
    }

  write_str ("  matrix generated.\n");

  // Store the generated system on the card, then load the solvers' working
  // copies back from it.
  write_str ("Storing A and b on the SD card (A.mat, b.mat)...\n");
  if (!sd_store (kFileA, A, sizeof (A)) || !sd_store (kFileB, b, sizeof (b)))
    {
      write_str ("FATAL: storing the matrices failed\n");
      return 1;
    }
  write_fmt ("  stored A.mat (%u bytes), b.mat (%u bytes)\n",
             static_cast<unsigned> (sizeof (A)),
             static_cast<unsigned> (sizeof (b)));

  write_str ("Loading A_block/b_block from the SD card (solver working set)...\n");
  if (!sd_load (kFileA, A_block, sizeof (A_block))
      || !sd_load (kFileB, b_block, sizeof (b_block)))
    {
      write_str ("FATAL: loading the solver's working set failed\n");
      return 1;
    }
  write_str ("Loading A/b for the classical solve from the SD card...\n");
  if (!sd_load (kFileA, A_classic, sizeof (A_classic))
      || !sd_load (kFileB, b_classic, sizeof (b_classic)))
    {
      write_str ("FATAL: loading the classical working set failed\n");
      return 1;
    }
  write_str ("  both working sets loaded from SD.\n\n");

  // ---- Launch the parallel solver threads ----------------------------------
 write_fmt ("Starting parallel %d -core block elimination...\n",OS_NCPU);
  for (int c = 0; c < OS_NCPU; ++c)
    {
      thread::attributes attr = thread::initializer;
      attr.th_stack_address = solver_stacks[c];
      attr.th_stack_size_bytes = sizeof (solver_stacks[c]);

      std::snprintf (solver_thread_names[c], 16, "solver_c%d", c);

      solver_threads[c]
          = new thread (solver_thread_names[c], solver_thread_func,
                        reinterpret_cast<void*> (c), attr);
      solver_threads[c]->cpu_affinity (1u << c);
    }

  static blink_led led;
  led.power_up ();
  while (!g_solver_done)
    {
      sysclock.sleep_for (100);
      led.blink ();
    }
  led.power_down ();
  write_str ("Block elimination finished.\n");

  // ---- Classical solve (ground truth) --------------------------------------
  write_str ("Solving full system using classical elimination...\n");
  std::uint32_t classic_start = timer_us32 ();
  solve_classical (A_classic, b_classic, x_classic);
  std::uint32_t classic_end = timer_us32 ();
  write_str ("Classical elimination finished.\n\n");

  // ---- Performance + comparison --------------------------------------------
  std::uint32_t block_us = g_block_end_us - g_block_start_us;
  std::uint32_t classic_us = classic_end - classic_start;

  write_str ("+---------------------------------------------------+\n");
  write_str ("| COMPARING BLOCK ELIMINATION VS CLASSICAL SOLVER  |\n");
  write_str ("+---------------------------------------------------+\n");
  float max_diff = 0.0f;
  float sum_diff = 0.0f;
  for (int i = 0; i < N; ++i)
    {
      float diff = std::abs (x_block[i] - x_classic[i]);
      sum_diff = sum_diff + diff;
      if (diff > max_diff)
        {
          max_diff = diff;
        }
      // A representative sample, not all N rows.
      if (i % (N / 40 + 1) != 0)
        {
          continue;
        }
      write_str ("x[");
      write_fmt ("%d", i);
      write_str ("] Block = ");
      print_float (x_block[i]);
      write_str (" | Classic = ");
      print_float (x_classic[i]);
      write_str (" | Abs Diff = ");
      print_float (diff);
      write_str ("\n");
    }
  write_str ("-----------------------------------------------------\n");
  write_str ("Total Absolute Difference (Sum): ");
  print_float (sum_diff);
  write_str ("\n");
  write_str ("Max Absolute Difference:        ");
  print_float (max_diff);
  write_str ("\n");
  write_str ("-----------------------------------------------------\n");
  write_str ("Performance Metrics:\n");
  write_str ("  Parallel Block Solver: ");
  print_time_us (static_cast<double> (block_us));
  write_str ("\n");
  write_str ("  Classical Solver:      ");
  print_time_us (static_cast<double> (classic_us));
  write_str ("\n");
  write_str ("  Speedup Ratio:         ");
  print_ratio (classic_us > 0
                   ? static_cast<double> (classic_us)
                         / static_cast<double> (block_us)
                   : 0.0);
  write_str ("x\n");
  write_str ("+---------------------------------------------------+\n");

  // Residuals ||A x - b||_inf against the original A and b (still in RAM).
  float res_block = 0.0f;
  float res_classic = 0.0f;
  for (int i = 0; i < N; ++i)
    {
      float sb = 0.0f;
      float sc = 0.0f;
      for (int j = 0; j < N; ++j)
        {
          sb = sb + A[i][j] * x_block[j];
          sc = sc + A[i][j] * x_classic[j];
        }
      res_block = std::max (res_block, std::abs (b[i] - sb));
      res_classic = std::max (res_classic, std::abs (b[i] - sc));
    }
  write_str ("Residual ||A*x_block - b||_inf:   ");
  print_float (res_block);
  write_str ("\n");
  write_str ("Residual ||A*x_classic - b||_inf: ");
  print_float (res_classic);
  write_str ("\n");

  // Both solutions back to the card, and x_block read back.
  static float x_chk[N];
  write_str ("Storing solutions on the SD card (x_block.mat, xclassic.mat)...\n");
  bool sd_ok = sd_store (kFileXb, x_block, sizeof (x_block))
               && sd_store (kFileXc, x_classic, sizeof (x_classic))
               && sd_load (kFileXb, x_chk, sizeof (x_chk))
               && (std::memcmp (x_chk, x_block, sizeof (x_block)) == 0);
  write_fmt ("  solution round-trip to/from SD: %s\n", sd_ok ? "OK" : "FAILED");
  sd_list ();

  // Tolerances: float32, a well-conditioned diagonally dominant system.
  const float tol_diff = 0.05f;
  const float tol_res = 0.05f;
  bool pass = (max_diff < tol_diff) && (res_block < tol_res)
              && (res_classic < tol_res) && sd_ok;
  write_fmt ("verdict: %s\n",
             pass ? "pass (block == classical within tolerance, SD round-trip OK)"
                  : "FAIL");
  write_str ("---------------------------------------------\n");
  return pass ? 0 : 1;
}
