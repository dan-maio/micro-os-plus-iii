# -----------------------------------------------------------------------------
# Test executables — µOS++ III Cortex-M on the ST Nucleo-F411RE (STM32F411RE).
#
# The board's tests are this platform's tests/<app>/, built by the tests' builder
# (board-tests/). This board is hardware-only -- it is programmed over
# its ST-Link and run on the desk -- so the builder emits `hwd` alone and this
# platform registers what it produced, named `<platform>-<app>-hwd`.
#
# hwd tests are NOT run by a plain `ctest`: they need the board. They carry the
# `hwd` label.
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
# Upstream's suites (tests/sources/<suite>/), on the platform's start-up
# (board-tests/cortexm/test-end.cpp, include/test-end-console.h), with the
# system calls they use (semihosting, the newlib reentrancy, POSIX I/O).
set (UOS_TESTS_SUITES rtos-apis mutex-stress cmsis-os-validator)
set (UOS_TESTS_STARTUP_LIBS micro-os-plus::iii-semihosting
     micro-os-plus::iii-newlib-reent micro-os-plus::iii-posix-io)
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
     "init" "reset halt" "program {@ELF@}" "arm semihosting enable"
     "reset run")

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
message (STATUS "Cortex-M nucleof411: port tests registered (${PLATFORM_NAME})")
