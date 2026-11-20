# -----------------------------------------------------------------------------
# Test executables — µOS++ III Cortex-M on the Pi-Zero RP2350B (16 MB flash).
#
# The board's tests are this platform's tests/<app>/, built by the tests' builder
# (board-tests/). This board is hardware-only -- QEMU has no Cortex-M33
# and the board is built ARMv8-M -- so the builder emits `hwd` alone and this
# platform registers what it produced, named `<platform>-<app>-hwd`.
#
# hwd tests need the board: they carry the `hwd` label, which the
# configuration's `test` action skips (`ctest -LE hwd`), and run one at
# a time (RUN_SERIAL); OpenOCD programs and resets the board for each.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/${PLATFORM_NAME}'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")

# The board facts and micro-os-plus::board come from cmake/platform-library.cmake
# (cmake/board.cmake); the tests' builder below reads them.

# Build the board's tests with the tests' builder (board-tests/); the images
# land in port-tests/test/.
# The board tests, built by the tests' own builder (board-tests/) from the
# board's test folder (this platform's tests/).
set (UOS_TESTS_PORT cortexm)
# The board-only tests: this platform's tests/ (tests.cmake, include/, src/,
# one folder per test).
set (UOS_TESTS_BOARD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/tests")
add_subdirectory ("${CMAKE_SOURCE_DIR}/board-tests" "port-tests/test")

set (_port_bin "${CMAKE_CURRENT_BINARY_DIR}/port-tests")

# -----------------------------------------------------------------------------
# One CTest case per test. Every one is `hwd`: the board has no `qemu` image.
# One CTest case per test the builder built (board-tests/: UOS_TESTS_APPS).
include ("${CMAKE_SOURCE_DIR}/cmake/uos-tests-run.cmake")

# The hardware run's OpenOCD commands (the board's own commands): program,
# reset, semihosting on, run.
set (_hwd_flash
     "init" "reset init" "program {@ELF@} verify" "reset init"
     "targets rp2350.cm1" "arm semihosting enable" "resume"
     "targets rp2350.cm0" "arm semihosting enable" "resume")

foreach (_app IN LISTS UOS_TESTS_APPS)

  # The hardware run: OpenOCD from CTest (cmake/uos-tests-run.cmake), the
  # board's commands above.
  uos_tests_add_openocd (
    NAME "${PLATFORM_NAME}-${_app}-hwd" APP "${_app}"
    ELF "$<TARGET_FILE:${_app}-hwd>" CFG "${CMAKE_CURRENT_SOURCE_DIR}/openocd.cfg"
    COMMANDS ${_hwd_flash} TIMEOUT 1200
  )
endforeach ()

# -----------------------------------------------------------------------------
message (STATUS "Cortex-M pico2-pizero: port tests registered (${PLATFORM_NAME})")
