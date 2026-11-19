# The facts of this board, the platform's since step 4 (they were
# micro-os-plus-iii-cortexm/test/boards/weactf412/board.cmake). The board's code
# is in this platform's folder since step 6;
# its linker scripts are in ../device/linker-scripts/.
#
# -----------------------------------------------------------------------------
# WeAct Studio F412RE -- STM32F412RE, one Cortex-M4F.
#
# A different part from the two F411 boards, not just a different board: its
# vector table is its own (vectors_stm32f412rx.c), and its crystal is 8 MHz,
# which ST's system_stm32f4xx.c reads from HSE_VALUE.
# -----------------------------------------------------------------------------

set (UOS_BOARD_SRC_DIR "${CMAKE_SOURCE_DIR}/platforms/cortexm-weactf412")

set (UOS_BOARD_FLAGS -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16)
set (UOS_BOARD_NCPU  1)

set (UOS_BOARD_CAPS  led uart)

set (UOS_BOARD_LINKER_HW "${CMAKE_SOURCE_DIR}/platforms/cortexm-weactf412/device/linker-scripts/linker.ld")

set (UOS_BOARD_LIBS  micro-os-plus::soc-stm32f412rx
                     # Upstream's generic startup -- these boards use it;
                     # the RP2350 has its own boot.S and does not.
                     micro-os-plus::iii-startup
                     micro-os-plus::iii-trace-semihosting)

# HSE_VALUE is the board's crystal, read by ST's clock bring-up. It is a
# board fact that reaches SoC code, which is why it is here and not in
# devices/.
set (UOS_BOARD_DEFINES
     STM32F412Rx
     HSE_VALUE=8000000
     OS_USE_OS_APP_CONFIG_H
     "PORT_GREETING=\"µOS++ WeAct F412RE (STM32F412RE, Cortex-M4F)\"")

# The port's test folder for this board (test/<BOARD>/), read by its builder.
set (BOARD "weactf412")
