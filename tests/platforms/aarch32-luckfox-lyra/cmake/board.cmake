# The facts of this board, the platform's since step 4 (they were
# micro-os-plus-iii-aarch32/test/boards/luckfox-lyra/board.cmake). The board's code
# stays in the port's test/boards/ until the board tests move (step 6); its
# linker scripts are in ../device/linker-scripts/.
#
# -----------------------------------------------------------------------------
# Luckfox Lyra B — RK3506, 3x Cortex-A7 (+ a Cortex-M0 that is not one of them).
#
# Three CPUs, not four. The RK3506 also carries a Cortex-M0, but it is a
# different ISA outside the A7 coherency domain: it cannot take an IPI as a
# peer and the scheduler cannot place a thread on it. The board is multi-core;
# the SMP cluster is the three identical A7s.
# -----------------------------------------------------------------------------

# This board's sources are its own.
set (UOS_BOARD_SRC_DIR "${CMAKE_SOURCE_DIR}/platforms/aarch32-luckfox-lyra")

set (UOS_BOARD_FLAGS -mcpu=cortex-a7 -marm -mfloat-abi=hard -mfpu=neon-vfpv4)
set (UOS_BOARD_NCPU  3)

# CAPS is what THIS PORT CAN DRIVE on this board.
#
# `sdcard` is here because the predecessor's cortex-a7 project drove this
# board's microSD -- src/sdcard/sdmmc.cpp, a DesignWare MSHC driver at
# 0xFF480000 -- and that driver is now devices/soc/rk3506/. It is reached
# through micro-os-plus::devices-rk3506-sd-posix: the RK3506 SD host as the
# posix-io block device /dev/sd, under Chan FatFs, as on the Pi.
#
# `usb-device` is here because the predecessor's RK3506 DWC2 gadget stack --
# src/usb/ and include/usb/, 13 sources and 10 headers -- is now usb/ beside
# this file, and smp_test6, smp_test7, smp_test_int3 and smp_test_int4 drive
# it. It is NOT part of the port library; see the source sets below.
set (UOS_BOARD_CAPS  smp sdcard usb-device led)

# One linker script, because there is one place this board runs.
#
# There is deliberately no UOS_BOARD_LINKER_QEMU. QEMU models none of the
# RK3506's own blocks -- the CRU, the GIC-400 at 0xFF58_0000, the DesignWare
# SD host, the DWC2 gadget, the SRAM mailbox, the Cortex-M0 -- so an emulated
# Lyra would be a generic Cortex-A7 wearing the name, and every test that
# makes this board worth having would be exactly the part not modelled.
#
# test/CMakeLists.txt reads the silence: a board with no QEMU linker script
# gets one image per test, `hwd`, and no emulated suite. This board is tested
# on hardware.
set (UOS_BOARD_LINKER_HW "${CMAKE_SOURCE_DIR}/platforms/aarch32-luckfox-lyra/device/linker-scripts/linker.ld")

set (UOS_BOARD_LIBS  "")

# The card as a µOS++ POSIX I/O block device (sd::block_device), with no file
# system of its own: what the portable storage tests (UOS_TESTS_STORAGE) link,
# under @xpacks/chan-fatfs.
set (UOS_BOARD_SD_POSIX  micro-os-plus::devices-rk3506-sd-posix)

# These Cortex-A7 are real OpenOCD `cortex_a` targets, which expect the
# classic AArch32 Angel trap, SVC 0x123456. HLT #0xF000 has no encoding on
# ARMv7-A -- see board-contract.cpp.
# A real GIC-400 SGI. SGI 0 is the lowest software-generated interrupt
     # and is unused by the miniloader.
set (UOS_BOARD_DEFINES
     OS_SMP_IPI_SGI=0
     SOC_RK3506
     SEMIHOST_TRAP_CHOSEN
     "PORT_GREETING=\"µOS++ Luckfox Lyra B (RK3506, Cortex-A7 SMP)\"")

# -----------------------------------------------------------------------------
# Code this board carries FOR ITS TESTS, compiled only by the tests that ask.
#
# None of it goes into the port library, and that is not an optimisation. The
# predecessor's per-test Makefiles each listed exactly which of these files
# they compiled, because several tests ship their OWN copy of one of them:
# smp_test6 and smp_test7 each have a different usb_vendor_gadget.cpp,
# smp_test_int4 a different sdmmc.cpp. Compiling the shared copy into every
# application would be a duplicate definition of the symbols the test means to
# provide itself. platforms/aarch32-luckfox-lyra/tests/tests.cmake names, per test, what it takes
# -- the same list the predecessor's Makefile did.

# The RK3506 DWC2 device (gadget) stack, carried over whole from
# smp-old/.../{include,src}/usb/.
#
# USB_CORE is the eight sources the predecessor's smp_test6 and smp_test7
# Makefiles compiled from src/usb/. The other five are in usb/src/ because
# they are part of the stack as it was written -- board_init.cpp and
# usb1_dev.cpp belong to the predecessor's own demo, and dma_pool.cpp,
# usb_env_stateos.cpp and usb_vendor_gadget.cpp are the three every test
# replaces -- not because anything here builds them.
#
# smp_test_int3 and smp_test_int4 take none of the sources, only the headers:
# their usb/usb1_int3.cpp drives the DWC2 registers directly.
set (UOS_BOARD_USB_INCLUDE "${CMAKE_SOURCE_DIR}/platforms/aarch32-luckfox-lyra/usb/include")
set (UOS_BOARD_USB_CORE_SOURCES
     "${CMAKE_SOURCE_DIR}/platforms/aarch32-luckfox-lyra/usb/src/udc_core.cpp"
     "${CMAKE_SOURCE_DIR}/platforms/aarch32-luckfox-lyra/usb/src/usb_composite.cpp"
     "${CMAKE_SOURCE_DIR}/platforms/aarch32-luckfox-lyra/usb/src/usb_config.cpp"
     "${CMAKE_SOURCE_DIR}/platforms/aarch32-luckfox-lyra/usb/src/usb_endpoint_autoconfig.cpp"
     "${CMAKE_SOURCE_DIR}/platforms/aarch32-luckfox-lyra/usb/src/usb_string_table.cpp"
     "${CMAKE_SOURCE_DIR}/platforms/aarch32-luckfox-lyra/usb/src/dwc2_driver.cpp"
     "${CMAKE_SOURCE_DIR}/platforms/aarch32-luckfox-lyra/usb/src/dwc2_ep0.cpp"
     "${CMAKE_SOURCE_DIR}/platforms/aarch32-luckfox-lyra/usb/src/dwc2_gadget.cpp")

# Two more the board owns, kept out of USB_CORE_SOURCES because only the
# gadget tests want them: smp_test6 and smp_test7 each carried a
# BYTE-IDENTICAL private copy of both until the duplicate gate named them.
set (UOS_BOARD_USB_GADGET_SOURCES
     "${CMAKE_SOURCE_DIR}/platforms/aarch32-luckfox-lyra/usb/src/dma_pool.cpp"
     "${CMAKE_SOURCE_DIR}/platforms/aarch32-luckfox-lyra/usb/src/usb_env_stateos.cpp")

# The register-level USB driver the two interrupt tests drive directly,
# instead of the core sources above. smp_test_int3 and smp_test_int4 carried
# a byte-identical copy each; it now lives with the board, like everything
# else both of them use.
set (UOS_BOARD_USB_INT_SOURCES
     "${CMAKE_SOURCE_DIR}/platforms/aarch32-luckfox-lyra/usb/src/usb1_int3.cpp")

# No SoC folder: the board compiles no SoC code of its own. The RK3506 code it
# needs is the board's own (include/rk3506.hpp: registers, the SRAM mailbox)
# and micro-os-plus-iii-devices-rk3506 (the SD host, micro-os-plus::devices-rk3506,
# for the tests that use the card). Until step 5b the AArch32 port compiled
# the BCM2837 SoC folder here too, unused.
set (UOS_BOARD_SOC_DIR "")

# The port's test folder for this board (test/<BOARD>/), read by its builder.
set (BOARD "luckfox-lyra")
