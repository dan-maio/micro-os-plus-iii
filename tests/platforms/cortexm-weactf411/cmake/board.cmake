# The facts of this board, the platform's since step 4 (they were
# micro-os-plus-iii-cortexm/test/boards/weactf411/board.cmake). The board's code
# is in this platform's folder since step 6;
# its linker scripts are in ../device/linker-scripts/.
#
# -----------------------------------------------------------------------------
# WeAct Studio F411CE -- STM32F411CE, one Cortex-M4F.
#
# Same silicon as the Nucleo above, a different board: its own pinout, its own
# console pins, and a SPI NOR flash the Nucleo does not have. It shares no
# source file with the Nucleo -- only the SoC support, which is why that is a
# devices/ target and not board code.
# -----------------------------------------------------------------------------

set (UOS_BOARD_SRC_DIR "${CMAKE_SOURCE_DIR}/platforms/cortexm-weactf411")

set (UOS_BOARD_FLAGS -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16)
set (UOS_BOARD_NCPU  1)

# `spi-flash` and `flatfs` are this board's own: bsp/spi.cpp drives the SPI
# NOR part, and bsp/flatfs.cpp is a flat filesystem over it. Both are board
# code here rather than devices/ drivers, because they were written against
# this board's wiring and have never been compiled for another.
set (UOS_BOARD_CAPS  led uart spi-flash flatfs)

set (UOS_BOARD_LINKER_HW "${CMAKE_SOURCE_DIR}/platforms/cortexm-weactf411/device/linker-scripts/linker.ld")

set (UOS_BOARD_LIBS  micro-os-plus::soc-stm32f411xe
                     # Upstream's generic startup -- these boards use it;
                     # the RP2350 has its own boot.S and does not.
                     micro-os-plus::iii-startup)

set (UOS_BOARD_DEFINES
     STM32F411xE
     OS_USE_OS_APP_CONFIG_H
     "PORT_GREETING=\"µOS++ WeAct F411CE (STM32F411CE, Cortex-M4F)\"")

# The port's test folder for this board (test/<BOARD>/), read by its builder.
set (BOARD "weactf411")
