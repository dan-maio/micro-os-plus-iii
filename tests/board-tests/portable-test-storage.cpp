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

// ----------------------------------------------------------------------------
//
// The storage of a portable test that uses the SD card (UOS_TESTS_STORAGE).
//
// The card is a µOS++ POSIX I/O block device, uos_test_storage_card(): the
// board's (its device package's SD driver, the host file on the POSIX port)
// as /dev/sd from portable-test-storage-sd.cpp, or the one a test brings
// with its own driver (board_test_sd_posix OWN). Before os_main()
// (portable-test-end.cpp calls uos_test_storage_start()), its first FAT
// partition is mounted at /sd/ with the Chan FatFs file system and /sd/tests/
// is created, so the test itself uses the posix-io calls on paths only:
//
//   os::posix::open ("/sd/tests/num.txt", O_WRONLY | O_CREAT | O_APPEND);
//
// On a boot card the boot files are never touched and nothing is formatted:
// a test keeps its files in /sd/tests/. When there is no card, or no volume
// on it, the reason is printed and /sd/ stays unmounted; the test then fails
// on its first open.

#include <cmsis-plus/rtos/os.h>
#include <cmsis-plus/posix-io/block-device-partition.h>
#include <cmsis-plus/posix-io/chan-fatfs-file-system.h>
#include <cmsis-plus/posix-io/file-descriptors-manager.h>
#include <cmsis-plus/posix-io/file-system.h>

#include <uos-test-storage.h>

#include <cerrno>
#include <cstdint>
#include <cstdio>

#if !defined(__unix__) && !defined(__APPLE__)

#include <sys/time.h>

// Chan FatFs stamps the files it writes with time() (get_fattime()), which
// newlib takes from _gettimeofday(). The platforms' start-up defines it; a
// board test with its own start-up may not, so here is the same clock-less
// one (the epoch), weak, for those. A bare-metal build only: on a host the C
// library has the real one.
extern "C" __attribute__ ((weak)) int
_gettimeofday (struct timeval* tv, void*)
{
  if (tv != nullptr)
    {
      tv->tv_sec = 0;
      tv->tv_usec = 0;
    }
  return 0;
}

#endif

// The partition template is declared `extern` by posix-io; the application
// instantiates the variant it uses (as rtos-apis' test-posix-io-api.cpp does).
template class os::posix::block_device_partition_implementable<>;

namespace
{
  // posix-io gives every open device, file and folder a file descriptor,
  // from a table the application sizes: the three standard streams, the card,
  // its partition, and the files and folders a test keeps open at once.
  os::posix::file_descriptors_manager descriptors_manager{ 16 };

  // FatFs is built without its own locking: the mutex serialises its users
  // (a test's threads, on any core).
  os::rtos::mutex fs_mutex{ "fat" };

  std::uint32_t
  le32 (const std::uint8_t* p)
  {
    return static_cast<std::uint32_t> (p[0])
           | (static_cast<std::uint32_t> (p[1]) << 8)
           | (static_cast<std::uint32_t> (p[2]) << 16)
           | (static_cast<std::uint32_t> (p[3]) << 24);
  }

  bool
  is_fat_type (std::uint8_t t)
  {
    switch (t)
      {
      case 0x01:
      case 0x04:
      case 0x06:
      case 0x0e: // FAT12/FAT16
      case 0x0b:
      case 0x0c:
      case 0x1b:
      case 0x1c: // FAT32
      case 0x2b:
      case 0x2c:
        return true;
      default:
        return false;
      }
  }

  // The first FAT partition of the MBR, or the whole card without one.
  bool
  locate_fat (os::posix::block_device& card, std::uint32_t& start,
              std::uint32_t& count)
  {
    static std::uint8_t mbr[512];
    if (card.read_block (mbr, 0, 1) != 1)
      {
        return false;
      }
    start = 0;
    count = static_cast<std::uint32_t> (card.blocks ());
    if (mbr[510] != 0x55 || mbr[511] != 0xAA)
      {
        return true;
      }
    for (int i = 0; i < 4; ++i)
      {
        const std::uint8_t* e = mbr + 446 + i * 16;
        if (e[4] != 0 && is_fat_type (e[4]))
          {
            start = le32 (e + 8);
            count = le32 (e + 12);
            return true;
          }
      }
    return true;
  }
} // namespace

void
uos_test_storage_start (void)
{
  os::posix::block_device& card = uos_test_storage_card ();
  std::printf ("storage: SD card /dev/%s...\n", card.name ());
  if (card.open () < 0)
    {
      std::printf ("storage: SD init FAILED (errno %d)\n", errno);
      return;
    }
  std::printf ("storage: SD card ready, %u sectors (~%u MiB)\n",
               static_cast<unsigned> (card.blocks ()),
               static_cast<unsigned> (card.blocks () / 2048u));

  std::uint32_t start = 0;
  std::uint32_t count = 0;
  if (!locate_fat (card, start, count))
    {
      std::printf ("storage: reading the partition table FAILED\n");
      return;
    }
  // The FAT volume inside the card, and the file system on it: built on the
  // first call, on the card the test was given.
  static os::posix::block_device_partition_implementable<> sd_partition{
    "sd1", card
  };
  static os::posix::chan_fatfs_file_system_lockable<os::rtos::mutex> fs{
    "fat", sd_partition, fs_mutex
  };
  sd_partition.configure (start, count);
  std::printf ("storage: FAT window LBA %u, %u sectors (%u MiB)\n",
               static_cast<unsigned> (start), static_cast<unsigned> (count),
               static_cast<unsigned> (count / 2048u));

  if (fs.mount ("/sd/") != 0)
    {
      std::printf ("storage: mount /sd/ FAILED (errno %d)\n", errno);
      return;
    }
  if (os::posix::mkdir ("/sd/tests", 0) != 0 && errno != EEXIST)
    {
      std::printf ("storage: mkdir /sd/tests FAILED (errno %d)\n", errno);
      return;
    }
  std::printf ("storage: FAT volume mounted at /sd/, test files in "
               "/sd/tests/\n");
}
