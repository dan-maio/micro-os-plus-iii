#!/usr/bin/env python3
#
# This file is part of the µOS++ project (https://micro-os-plus.github.io/).
# Copyright (c) 2026 Liviu Ionescu. All rights reserved.
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose is hereby granted, under the terms of the MIT license.
#
# If a copy of the license was not distributed with this file, it can be
# obtained from https://opensource.org/licenses/mit.

"""The SD card image of an emulated or host run of the storage tests.

    sd-image.py <image> [--seed]

Makes <image>: a 4 GiB card (sparse where the file system allows it) with an
MBR and one FAT32 partition from sector 2048 to the end, the layout of a boot
card. With --seed, the volume also gets /seed.bin, which sd_test reads back
(the "host -> device" phase): 100000 bytes of the same generator the test
uses.

The partition table comes from sfdisk and the file system from mkfs.fat
(dosfstools). seed.bin is written here, directly into the fresh volume: one
root-folder entry and a contiguous cluster chain.
"""

import os
import struct
import subprocess
import sys

CARD_BYTES = 4 << 30
SECTOR = 512
PART_START = 2048  # sectors

SEED_NAME = b"SEED    BIN"  # 8.3; NTRes 0x18 shows it as seed.bin
SEED_SIZE = 100000
SEED_SEED = 0x51A7E51


def pattern(seed, length):
    out = bytearray(length)
    x = seed
    for i in range(length):
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF
        out[i] = x >> 24
    return bytes(out)


def make_card(path):
    with open(path, "wb") as f:
        f.truncate(CARD_BYTES)
    part_sectors = CARD_BYTES // SECTOR - PART_START
    # One primary partition, type 0x0c (FAT32 LBA).
    subprocess.run(
        ["sfdisk", "--quiet", "--no-reread", "--no-tell-kernel", path],
        input=f"label: dos\nstart={PART_START}, size={part_sectors}, type=c\n",
        text=True,
        check=True,
    )
    subprocess.run(
        [
            "mkfs.fat", "-F", "32", "-S", str(SECTOR), "-n", "UOS-TEST",
            "--offset", str(PART_START), path, str(part_sectors * SECTOR // 1024),
        ],
        stdout=subprocess.DEVNULL,
        check=True,
    )


def add_seed(path):
    base = PART_START * SECTOR
    with open(path, "r+b") as f:
        f.seek(base)
        bs = f.read(SECTOR)
        bytes_per_sec, sec_per_clus, rsvd, nfats = struct.unpack_from("<HBHB", bs, 11)
        fat_size, = struct.unpack_from("<I", bs, 36)
        root_clus, fsinfo_sec = struct.unpack_from("<IH", bs, 44)
        assert bytes_per_sec == SECTOR, "unexpected sector size"
        clus_bytes = sec_per_clus * SECTOR
        data_sec = rsvd + nfats * fat_size

        def clus_off(c):
            return base + (data_sec + (c - 2) * sec_per_clus) * SECTOR

        # A fresh volume: the root folder is the only cluster in use, so the
        # file takes the clusters after it.
        nclus = (SEED_SIZE + clus_bytes - 1) // clus_bytes
        first = root_clus + 1
        chain = list(range(first, first + nclus))
        for k in range(nfats):
            fat = base + (rsvd + k * fat_size) * SECTOR
            for i, c in enumerate(chain):
                nxt = chain[i + 1] if i + 1 < len(chain) else 0x0FFFFFFF
                f.seek(fat + 4 * c)
                f.write(struct.pack("<I", nxt))

        f.seek(clus_off(first))
        f.write(pattern(SEED_SEED, SEED_SIZE))

        # The entry: after the volume label mkfs.fat puts first, if any.
        root = clus_off(root_clus)
        for slot in range(clus_bytes // 32):
            f.seek(root + 32 * slot)
            if f.read(1) in (b"\x00", b"\xe5"):
                break
        else:
            sys.exit("sd-image.py: the root folder is full")
        entry = struct.pack(
            "<11sBBBHHHHHHHI",
            SEED_NAME, 0x20, 0x18, 0, 0, 0x21, 0x21,
            first >> 16, 0, 0x21, first & 0xFFFF, SEED_SIZE,
        )
        f.seek(root + 32 * slot)
        f.write(entry)

        # FSInfo: the free count and the next free cluster.
        fsinfo = base + fsinfo_sec * SECTOR
        f.seek(fsinfo + 488)
        free, _ = struct.unpack("<II", f.read(8))
        if free != 0xFFFFFFFF:
            free -= nclus
        f.seek(fsinfo + 488)
        f.write(struct.pack("<II", free, first + nclus))


def main(argv):
    if len(argv) < 2 or argv[1].startswith("-"):
        sys.exit(__doc__)
    path = argv[1]
    make_card(path)
    if "--seed" in argv[2:]:
        add_seed(path)


if __name__ == "__main__":
    main(sys.argv)
