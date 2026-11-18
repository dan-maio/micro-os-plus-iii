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
// The board's card (its device package's SD driver, the host file on the
// POSIX port) as the µOS++ POSIX I/O block device /dev/sd. The test finds it
// by that name (os::posix::device_registry), reads the partition table and
// mounts a file system on it (@xpacks/chan-fatfs): the µOS++ interfaces only.
//
// A block device links itself into the registry when constructed. The card is
// initialised on the first open (the mount), not here.
//
// posix-io gives every open device, file and folder a file descriptor, from a
// table the application sizes: the three standard streams, the card, its
// partition, and the files and folders a test keeps open at once.

#include <cmsis-plus/posix-io/file-descriptors-manager.h>

#include <sd-block-device.h>

namespace
{
  os::posix::file_descriptors_manager descriptors_manager{ 16 };

  sd::block_device sd_card{ "sd" };
} // namespace
