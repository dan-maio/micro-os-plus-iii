# The facts of this board, the platform's since step 4 (they were
# micro-os-plus-iii-aarch32/test/boards/rpi3b/board.cmake). The board's code
# stays in the port's test/boards/ until the board tests move (step 6); its
# linker scripts are in ../device/linker-scripts/.
#
# -----------------------------------------------------------------------------
# Raspberry Pi 3 B — BCM2837, 4x Cortex-A53 running in AArch32.
#
# Same silicon and the same sources as rpi-zero-2w, selected by BOARD_RPI3B
# exactly as the predecessor's `make BOARD=rpi3b` did. That define is the whole
# difference, and it reaches four places:
#
#   include/led.hpp   a DIFFERENT LED driver -- the ACT LED is not a SoC GPIO
#                     on this board but VideoCore expander GPIO 130, driven
#                     through the ARM<->VC mailbox property channel
#                     (tag 0x00038041). 91 lines, against 36 for a plain GPIO.
#   include/uart.hpp  the banner strings.
#   include/smp.hpp   PORT_RAM_END, the window a stack pointer is validated
#                     against -- 1 GB here, 512 MiB on the Zero 2 W.
#   src/mmu.cpp       the top of the Normal-memory mapping, the same number.
#
# plus linker-rpi3b.ld, whose RAM region is that number again. Those last three
# are ONE fact written three times; they must be changed together.
# -----------------------------------------------------------------------------

set (UOS_BOARD_SRC_DIR "${CMAKE_SOURCE_DIR}/platforms/aarch32-rpi-zero-2w")

set (UOS_BOARD_FLAGS -mcpu=cortex-a53 -marm -mfloat-abi=hard -mfpu=neon-fp-armv8)
set (UOS_BOARD_NCPU  4)
set (UOS_BOARD_CAPS  smp sdcard usb-device led)

set (UOS_BOARD_LINKER_HW   "${CMAKE_SOURCE_DIR}/platforms/aarch32-rpi3b/device/linker-scripts/linker-rpi3b.ld")
set (UOS_BOARD_LINKER_QEMU "${CMAKE_SOURCE_DIR}/platforms/aarch32-rpi3b/device/linker-scripts/linker-rpi3b.ld")

set (UOS_BOARD_LIBS  micro-os-plus::soc-bcm2837)

# The card as a µOS++ POSIX I/O block device (sd::block_device), with no file
# system of its own: what the portable storage tests (UOS_TESTS_STORAGE) link,
# under @xpacks/chan-fatfs.
set (UOS_BOARD_SD_POSIX  micro-os-plus::devices-sd-posix)

# BCM2837 has no GIC and no SGIs: a cross-core reschedule is a write to
     # the target core's local mailbox 0.
set (UOS_BOARD_DEFINES
     OS_SMP_IPI_SGI=0
     SOC_BCM2837 BOARD_RPI3B
     SEMIHOST_TRAP_CHOSEN SEMIHOST_TRAP_HLT
     "PORT_GREETING=\"µOS++ Raspberry Pi 3 B (BCM2837, Cortex-A53 AArch32 SMP)\"")

# The SoC folder (in a device package) whose include/ and src/ the board
# target compiles.
set (UOS_BOARD_SOC_DIR "${UOS_DEVICES_BCM283X_ROOT}/soc/bcm2837")

# The port's test folder for this board (test/<BOARD>/), read by its builder.
set (BOARD "rpi3b")
