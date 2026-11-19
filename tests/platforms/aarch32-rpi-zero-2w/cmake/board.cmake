# The facts of this board, the platform's since step 4 (they were
# micro-os-plus-iii-aarch32/test/boards/rpi-zero-2w/board.cmake). The board's code
# stays in the port's test/boards/ until the board tests move (step 6); its
# linker scripts are in ../device/linker-scripts/.
#
# -----------------------------------------------------------------------------
# Raspberry Pi Zero 2 W — BCM2837, 4x Cortex-A53 running in AArch32.
#
# One file per board, discovered by the presence of this file. Nothing in the
# port's own CMakeLists knows this board exists.
# -----------------------------------------------------------------------------

# This board's own sources. rpi3b is the same silicon and the same code, so
# its board.cmake points back here rather than copying any of it.
set (UOS_BOARD_SRC_DIR "${CMAKE_SOURCE_DIR}/platforms/aarch32-rpi-zero-2w")

set (UOS_BOARD_FLAGS -mcpu=cortex-a53 -marm -mfloat-abi=hard -mfpu=neon-fp-armv8)
set (UOS_BOARD_NCPU  4)

# What this board can do. The test matrix asks about capabilities; it never
# asks which board it is building for.
set (UOS_BOARD_CAPS  smp sdcard usb-device led)

set (UOS_BOARD_LINKER_HW   "${CMAKE_SOURCE_DIR}/platforms/aarch32-rpi-zero-2w/device/linker-scripts/linker.ld")
set (UOS_BOARD_LINKER_QEMU "${CMAKE_SOURCE_DIR}/platforms/aarch32-rpi-zero-2w/device/linker-scripts/linker.ld")

set (UOS_BOARD_LIBS  micro-os-plus::soc-bcm2837)

# The card as a µOS++ POSIX I/O block device (sd::block_device), with no file
# system of its own: what the portable storage tests (UOS_TESTS_STORAGE) link,
# under @xpacks/chan-fatfs.
set (UOS_BOARD_SD_POSIX  micro-os-plus::devices-sd-posix)

# The onboard green ACT LED is a plain SoC GPIO, number 29. led.hpp's own
# fallback is GPIO16 -- header pin 36, for an externally wired LED -- which
# blinks nothing on a bare board.
set (LED_PIN 29 CACHE STRING "GPIO driven as the user LED")

# SEMIHOST_TRAP_HLT is about the DEBUGGER, not the CPU. These Cortex-A53 are
# declared as OpenOCD `aarch64` targets even for this 32-bit port, because the
# ARMv7 `cortex_a` target does not support the -cti option the BCM2837 needs
# (see bcm2837-aarch32.cfg). An `aarch64` target expects HLT #0xF000.
# BCM2837 has no GIC and no SGIs: a cross-core reschedule is a write to
     # the target core's local mailbox 0. Named OS_SMP_IPI_SGI for source
     # compatibility with the GIC boards.
set (UOS_BOARD_DEFINES
     OS_SMP_IPI_SGI=0
     SOC_BCM2837
     SEMIHOST_TRAP_CHOSEN SEMIHOST_TRAP_HLT
     LED_PIN=${LED_PIN}
     "PORT_GREETING=\"µOS++ Raspberry Pi Zero 2W (BCM2837, Cortex-A53 AArch32 SMP)\"")

# The SoC folder (in a device package) whose include/ and src/ the board
# target compiles.
set (UOS_BOARD_SOC_DIR "${UOS_DEVICES_BCM283X_ROOT}/soc/bcm2837")

# The port's test folder for this board (test/<BOARD>/), read by its builder.
set (BOARD "rpi-zero-2w")
