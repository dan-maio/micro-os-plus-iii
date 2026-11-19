# -----------------------------------------------------------------------------
# Platform library — µOS++ III Cortex-M on the Raspberry Pi Pico (RP2040).
#
# micro-os-plus::platform is the port plus the kernel's optional groups the
# board's tests and the harness suites need. The port's own tests link
# micro-os-plus::cortexm directly (through the tests' builder); the harness
# suites link this.
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/platform-library.cmake..."
)

# The board: its facts (cmake/board.cmake) and micro-os-plus::board.
include ("${CMAKE_CURRENT_LIST_DIR}/board.cmake")
include ("${CMAKE_SOURCE_DIR}/cmake/uos-cortexm-board.cmake")
uos_cortexm_board_library ()

add_library (platform-cortexm-pico-interface INTERFACE EXCLUDE_FROM_ALL)

target_include_directories (
  platform-cortexm-pico-interface INTERFACE "include"
)

target_compile_definitions (
  platform-cortexm-pico-interface
  INTERFACE "${xpack_platform_compile_definition}" _GNU_SOURCE
)

target_link_libraries (
  platform-cortexm-pico-interface
  INTERFACE
    # The port core the board names, then the board (its flags and its own
    # sources), then the kernel.
    ${UOS_PORT_LIB}
    micro-os-plus::board
    micro-os-plus::iii
    # The kernel's optional groups the startup and the C library need.
    micro-os-plus::iii-startup
    micro-os-plus::iii-semihosting
    micro-os-plus::iii-newlib-reent
    micro-os-plus::iii-posix-io
)

add_library (micro-os-plus::platform ALIAS platform-cortexm-pico-interface)
message (
  VERBOSE
  "> micro-os-plus::platform -> platform-cortexm-pico-interface"
)
