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

// The storage start-up of the tests that use the SD card (UOS_TESTS_STORAGE,
// board-tests/portable-test-storage.cpp).
//
// uos_test_storage_start() opens the card (uos_test_storage_card(), the
// board's /dev/sd unless the test brings its own), mounts its first
// FAT partition at /sd/ with the Chan FatFs POSIX I/O file system and creates
// /sd/tests/; it prints the reason when it cannot, and /sd/ then stays
// unmounted. A portable test gets it before os_main(); a board test, which
// has its own start-up, calls it once from a thread (os_main or later).

#ifndef UOS_TEST_STORAGE_H_
#define UOS_TEST_STORAGE_H_

#if defined(__cplusplus)
extern "C"
{
#endif

  void
  uos_test_storage_start (void);

#if defined(__cplusplus)
}
#endif

#if defined(__cplusplus)

#include <cmsis-plus/posix-io/block-device.h>

// The card uos_test_storage_start() mounts: the board's /dev/sd
// (portable-test-storage-sd.cpp), or, for a test that drives the card with its
// own driver (board_test_sd_posix OWN), the block device the test defines
// here.
os::posix::block_device&
uos_test_storage_card (void);

#endif

#endif // UOS_TEST_STORAGE_H_
