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

// The card of a storage test (UOS_TESTS_STORAGE) when the board's driver
// serves it: the device package's SD driver (the host file on the POSIX port)
// as the µOS++ POSIX I/O block device /dev/sd. A block device links itself
// into the registry when constructed; the card is initialised on its first
// open (the mount, in portable-test-storage.cpp), not here.
//
// A test that drives the card with its own driver (board_test_sd_posix OWN)
// does not get this file and defines uos_test_storage_card() itself.

#include <sd-block-device.h>
#include <uos-test-storage.h>

namespace
{
  sd::block_device sd_card{ "sd" };
} // namespace

os::posix::block_device&
uos_test_storage_card (void)
{
  return sd_card;
}
