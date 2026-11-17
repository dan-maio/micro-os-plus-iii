# The facts of this board, the platform's since step 4 (they were
# micro-os-plus-iii-aarch64/test/boards/rpi-zero-2w/board.cmake). The board's code
# stays in the port's test/boards/ until the board tests move (step 6); its
# linker scripts are in ../device/linker-scripts/.
#
# -----------------------------------------------------------------------------
# Raspberry Pi Zero 2 W — BCM2837, 4x Cortex-A53, ARMv8-A.
#
# One file per board, discovered by the presence of this file. Nothing in the
# port's own CMakeLists knows this board exists.
# -----------------------------------------------------------------------------

# This board's own sources. rpi3b is the same silicon and the same code, so
# its board.cmake points back here rather than copying any of it.
set (UOS_BOARD_SRC_DIR "${UOS_AARCH64_ROOT}/test/boards/rpi-zero-2w")

set (UOS_BOARD_FLAGS -mcpu=cortex-a53)
set (UOS_BOARD_NCPU  4)

# What this board can do. The test matrix asks about capabilities; it never
# asks which board it is building for.
set (UOS_BOARD_CAPS  smp sdcard usb-device led)

set (UOS_BOARD_LIBS  micro-os-plus::soc-bcm2837)

# The driver set an application links when it needs the SD card or USB:
# the BCM2837 SD host and DWC2, which is what these tests always linked.
set (UOS_BOARD_DEVICES  micro-os-plus::devices)

set (UOS_BOARD_LINKER_HW   "${CMAKE_SOURCE_DIR}/platforms/aarch64-rpi-zero-2w/device/linker-scripts/linker.ld")
set (UOS_BOARD_LINKER_QEMU "${CMAKE_SOURCE_DIR}/platforms/aarch64-rpi-zero-2w/device/linker-scripts/linker.ld")

# The onboard green ACT LED is a plain SoC GPIO, number 29. led.hpp's own
# fallback is GPIO16 -- header pin 36, for an externally wired LED -- which
# blinks nothing on a bare board.
set (LED_PIN 29 CACHE STRING "GPIO driven as the user LED")

# These Cortex-A53 are OpenOCD `aarch64` targets, which expect HLT #0xF000.
set (UOS_BOARD_DEFINES
     SOC_BCM2837
     SEMIHOST_TRAP_CHOSEN SEMIHOST_TRAP_HLT
     OS_SMP_IPI_SGI=0
     LED_PIN=${LED_PIN}
     "PORT_GREETING=\"µOS++ Raspberry Pi Zero 2W (BCM2837, 4x Cortex-A53)\"")

# The SoC folder whose include/ and src/ the board target compiles.
set (UOS_BOARD_SOC bcm2837)

# The port's test folder for this board (test/<BOARD>/), read by its builder.
set (BOARD "rpi-zero-2w")
