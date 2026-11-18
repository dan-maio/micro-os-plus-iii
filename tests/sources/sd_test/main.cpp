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
 * sd_test -- the SD card through the µOS++ POSIX I/O layer.
 *
 * The board's card is the block device /dev/sd; before os_main() its first
 * FAT partition is mounted at /sd/ with the Chan FatFs POSIX I/O file system
 * and /sd/tests/ created (board-tests/portable-test-storage.cpp). The test
 * works through the posix-io calls on paths only (open, read, write, stat,
 * unlink, opendir, statvfs):
 *
 *   Phase A, host -> device: when the volume has /seed.bin (the QEMU card,
 *            made by tests/scripts/fat-image.py), its content is checked
 *            byte for byte against the same generator the host used. A boot
 *            card has none, and the phase is skipped.
 *   Phase B, device -> device: text and pattern files (one of 600 sectors,
 *            for the multi-block commands) are written under /sd/tests/,
 *            read back and compared. On a boot card the boot files are never
 *            touched and nothing is formatted.
 *
 * A portable test: os_main() only, the µOS++ interfaces only. The platform
 * brings the board up before os_main() and prints the RESULT line from its
 * return value (board-tests/portable-test-end.cpp).
 */

#include <cmsis-plus/rtos/os.h>
#include <cmsis-plus/posix-io/directory.h>
#include <cmsis-plus/posix-io/file-system.h>
#include <cmsis-plus/posix-io/io.h>
#include <cmsis-plus/posix/sys/statvfs.h>

#include <fcntl.h>
#include <sys/stat.h>

#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstring>

using namespace os;

namespace
{

  constexpr const char* kMount = "/sd/";

  // -------------------------------------------------------------------------
  // Deterministic pseudo-random content: the LCG the host tool uses, so either
  // side can reproduce byte for byte what the other wrote. Generated in
  // chunks, so a file of any size needs one small buffer.
  // -------------------------------------------------------------------------
  struct pattern
  {
    std::uint32_t x;

    void
    fill (std::uint8_t* buf, std::size_t len)
    {
      for (std::size_t i = 0; i < len; ++i)
        {
          x = x * 1664525u + 1013904223u;
          buf[i] = static_cast<std::uint8_t> (x >> 24);
        }
    }
  };

  // The host tool puts this file on the QEMU card before the run.
  constexpr std::uint32_t kSeedSize = 100000u;
  constexpr std::uint32_t kSeedSeed = 0x51A7E51u;
  constexpr const char* kSeedPath = "/sd/seed.bin";

  // Board-neutral on purpose: a host tool cannot know which board wrote it.
  constexpr const char* kHelloText = "Hello from micro-os-plus-iii posix-io!\n";

  struct file_spec
  {
    const char* name;
    std::uint32_t seed; // the pattern files only
    std::uint32_t size;
    bool is_text;
  };

  constexpr file_spec kWriteSpecs[] = {
    { "hello.txt", 0, 0, true }, // size: strlen (kHelloText)
    { "data1.bin", 0x11111111u, 3000u, false },
    { "data2.bin", 0x22222222u, 70000u, false },
    { "big.bin", 0x33333333u, 307200u, false }, // 600 sectors: CMD18/CMD25
  };

  std::uint8_t g_buf[4096];
  std::uint8_t g_want[sizeof (g_buf)];

  bool g_all_pass = true;

  void
  report (const char* what, bool ok)
  {
    std::printf ("  [%s] %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
      {
        g_all_pass = false;
      }
  }

  std::uint32_t
  spec_size (const file_spec& spec)
  {
    return spec.is_text ? static_cast<std::uint32_t> (std::strlen (kHelloText))
                        : spec.size;
  }

  // -------------------------------------------------------------------------
  // Files, through posix-io.
  // -------------------------------------------------------------------------
  bool
  write_file (const char* path, const file_spec& spec)
  {
    posix::io* f = posix::open (path, O_WRONLY | O_CREAT | O_TRUNC);
    if (f == nullptr)
      {
        std::printf ("    open for write failed (errno %d)\n", errno);
        return false;
      }
    bool ok = true;
    const std::uint32_t size = spec_size (spec);
    if (spec.is_text)
      {
        ok = (f->write (kHelloText, size) == static_cast<ssize_t> (size));
      }
    else
      {
        pattern p{ spec.seed };
        for (std::uint32_t done = 0; ok && done < size;)
          {
            std::size_t n = size - done;
            if (n > sizeof (g_buf))
              {
                n = sizeof (g_buf);
              }
            p.fill (g_buf, n);
            ok = (f->write (g_buf, n) == static_cast<ssize_t> (n));
            done += static_cast<std::uint32_t> (n);
          }
      }
    if (!ok)
      {
        std::printf ("    write failed (errno %d)\n", errno);
      }
    if (f->close () != 0)
      {
        std::printf ("    close failed (errno %d)\n", errno);
        ok = false;
      }
    return ok;
  }

  // Reads the whole file and compares it with the text or the pattern.
  bool
  verify_file (const char* path, const char* text, std::uint32_t seed,
               std::uint32_t size)
  {
    struct stat st;
    if (posix::stat (path, &st) != 0)
      {
        std::printf ("    stat failed (errno %d)\n", errno);
        return false;
      }
    if (static_cast<std::uint32_t> (st.st_size) != size)
      {
        std::printf ("    size %u, expected %u\n",
                     static_cast<unsigned> (st.st_size),
                     static_cast<unsigned> (size));
        return false;
      }
    posix::io* f = posix::open (path, O_RDONLY);
    if (f == nullptr)
      {
        std::printf ("    open for read failed (errno %d)\n", errno);
        return false;
      }
    bool ok = true;
    pattern p{ seed };
    for (std::uint32_t done = 0; ok && done < size;)
      {
        std::size_t n = size - done;
        if (n > sizeof (g_buf))
          {
            n = sizeof (g_buf);
          }
        if (f->read (g_buf, n) != static_cast<ssize_t> (n))
          {
            std::printf ("    read failed (errno %d)\n", errno);
            ok = false;
            break;
          }
        if (text != nullptr)
          {
            std::memcpy (g_want, text + done, n);
          }
        else
          {
            p.fill (g_want, n);
          }
        ok = (std::memcmp (g_buf, g_want, n) == 0);
        done += static_cast<std::uint32_t> (n);
      }
    f->close ();
    return ok;
  }

  // -------------------------------------------------------------------------
  // Phase A: the host-seeded file.
  // -------------------------------------------------------------------------
  void
  phase_host_seed (void)
  {
    std::printf ("\nPhase A: host->device  (seed.bin, written by the host)\n");
    struct stat st;
    if (posix::stat (kSeedPath, &st) != 0)
      {
        std::printf ("  NOTE: %s not present - skipped (a boot card).\n",
                     kSeedPath);
        return;
      }
    const bool ok = verify_file (kSeedPath, nullptr, kSeedSeed, kSeedSize);
    std::printf ("  seed.bin: %u bytes, content %s\n",
                 static_cast<unsigned> (st.st_size), ok ? "OK" : "MISMATCH");
    report ("host-created seed.bin verified on device", ok);
  }

  // -------------------------------------------------------------------------
  // Phase B: write, read back, list.
  // -------------------------------------------------------------------------
  void
  phase_write_and_verify (void)
  {
    std::printf ("\nPhase B: device->device  (files in /sd/tests)\n");

    char path[64];
    for (const auto& spec : kWriteSpecs)
      {
        std::snprintf (path, sizeof (path), "/sd/tests/%s", spec.name);
        posix::unlink (path); // a leftover of an earlier run
        std::printf ("  writing %s (%u B %s)...\n", path,
                     static_cast<unsigned> (spec_size (spec)),
                     spec.is_text ? "text" : "pattern");
        report (spec.name, write_file (path, spec));
      }

    std::printf ("\n  read-back verification:\n");
    for (const auto& spec : kWriteSpecs)
      {
        std::snprintf (path, sizeof (path), "/sd/tests/%s", spec.name);
        const bool ok
            = verify_file (path, spec.is_text ? kHelloText : nullptr,
                           spec.seed, spec_size (spec));
        std::printf ("  [%s] %s read-back verified (%u B)\n",
                     ok ? "PASS" : "FAIL", spec.name,
                     static_cast<unsigned> (spec_size (spec)));
        if (!ok)
          {
            g_all_pass = false;
          }
      }

    struct statvfs vfs;
    if (posix::statvfs (kMount, &vfs) == 0)
      {
        const unsigned long long frsize = vfs.f_frsize;
        std::printf ("  volume: %llu KiB total, %llu KiB free\n",
                     static_cast<unsigned long long> (vfs.f_blocks) * frsize
                         / 1024u,
                     static_cast<unsigned long long> (vfs.f_bfree) * frsize
                         / 1024u);
      }

    std::printf ("\ntests/ contents:\n");
    posix::directory* dir = posix::opendir ("/sd/tests");
    if (dir == nullptr)
      {
        std::printf ("  opendir failed (errno %d)\n", errno);
        report ("tests/ listing", false);
        return;
      }
    unsigned n = 0;
    for (dirent* e = dir->read (); e != nullptr; e = dir->read ())
      {
        std::printf ("    %s\n", e->d_name);
        ++n;
      }
    dir->close ();
    report ("tests/ lists the files written",
            n >= sizeof (kWriteSpecs) / sizeof (kWriteSpecs[0]));
  }

} // namespace

int
os_main (int, char*[])
{
  std::printf ("sd_test: the SD card through µOS++ POSIX I/O and Chan FatFs\n");

  // The volume the storage start-up mounted (it printed why, if it did not).
  struct statvfs vfs;
  if (posix::statvfs (kMount, &vfs) != 0)
    {
      std::printf ("  no FAT volume mounted at %s (errno %d)\n", kMount,
                   errno);
      return 1;
    }
  std::printf ("  FAT volume at %s: %u blocks of %u bytes\n", kMount,
               static_cast<unsigned> (vfs.f_blocks),
               static_cast<unsigned> (vfs.f_frsize));

  phase_host_seed ();
  phase_write_and_verify ();

  std::printf ("\nsd_test: %s\n",
               g_all_pass ? "SD verified" : "FAILED (see above)");
  return g_all_pass ? 0 : 1;
}
