# -----------------------------------------------------------------------------
# Test executables — µOS++ III Cortex-M on the WeAct RP2350B (16 MB + PSRAM).
#
# The board's tests are this platform's tests/<app>/, built by the tests' builder
# (board-tests/), which compiles each test as `-hwd` for the probe and,
# for the tests the board can run emulated, `-qemu`. This platform reuses that
# builder and registers what it produced, named `<platform>-<app>-<variant>`.
#
# hwd tests are NOT run by a plain `ctest`: they need the board, one test per
# power cycle. They carry the `hwd` label.
#
# The `qemu` images end themselves: each test prints a RESULT line and, under
# QEMU_BUILD, exits through the strong semihosting _Exit() (see the port's
# platforms/cortexm-pico2/tests/include/hw_result.hpp), so CTest reads a real exit code and needs
# no runner script.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/${PLATFORM_NAME}'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")

# The board facts and micro-os-plus::board come from cmake/platform-library.cmake
# (cmake/board.cmake); the port's builder below reads them.

# Build the port's tests by reusing the port's builder. The binary dir ends in
# `test`, which is what the board's hw.sh expects ($BUILD/test/<app>-hwd).
# The board tests, built by the tests' own builder (board-tests/) from the
# board's test folder (still in the port until the tests move into tests/).
set (UOS_TESTS_PORT cortexm)
# Upstream's suites (tests/sources/<suite>/), on the platform's start-up
# (board-tests/cortexm/test-end.cpp, include/test-end-console.h), with the
# system calls they use (semihosting, the newlib reentrancy, POSIX I/O).
set (UOS_TESTS_SUITES fp-switch)
set (UOS_TESTS_STARTUP_LIBS micro-os-plus::iii-semihosting
     micro-os-plus::iii-newlib-reent micro-os-plus::iii-posix-io)
# The board-only tests: this platform's tests/ (tests.cmake, include/, src/,
# one folder per test).
set (UOS_TESTS_BOARD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/tests")
add_subdirectory ("${CMAKE_SOURCE_DIR}/board-tests" "port-tests/test")

set (_port_bin "${CMAKE_CURRENT_BINARY_DIR}/port-tests")
set (_board_hw "${CMAKE_CURRENT_SOURCE_DIR}/hw.sh")

# The QEMU binary, for the tests the board can run emulated. The RP2350's
# Cortex-M33 is close enough to QEMU's generic mps2-an500 Cortex-M7 for the
# core bring-up and kernel-object tests; the RP2350-only blocks (SIO, PSRAM,
# ADC) are listed HWD_ONLY and never get a `qemu` image.
file (GLOB _qemu_bins
      "$ENV{HOME}/.local/xPacks/@xpack-dev-tools/qemu-arm/*/.content/bin")
if (_qemu_bins)
  list (SORT _qemu_bins COMPARE NATURAL ORDER DESCENDING)
  list (GET _qemu_bins 0 _qemu_bin)
  set (_qemu "${_qemu_bin}/qemu-system-arm")
else ()
  set (_qemu "qemu-system-arm")
endif ()

# -----------------------------------------------------------------------------
# One CTest case per (test, variant). The port's builder emits <app>-hwd for
# every test and <app>-qemu only for the ones the board can run emulated (its
# tests.cmake lists the rest HWD_ONLY), so the qemu case is registered only
# when the target exists.
# One CTest case per test the builder built (board-tests/: UOS_TESTS_APPS).
include ("${CMAKE_SOURCE_DIR}/cmake/uos-tests-run.cmake")

# The hardware run's OpenOCD commands (they were the board's hw.sh): program,
# reset, semihosting on, run.
set (_hwd_flash
     "init" "reset init" "program {@ELF@} verify" "reset init"
     "targets rp2350.cm1" "arm semihosting enable" "resume"
     "targets rp2350.cm0" "arm semihosting enable" "resume")

foreach (_app IN LISTS UOS_TESTS_APPS)

  if (TARGET "${_app}-qemu")
    add_test (
      NAME "${PLATFORM_NAME}-${_app}-qemu"
      COMMAND
        "${_qemu}" -M mps2-an500 -cpu cortex-m7
        -kernel "${_port_bin}/test/${_app}-qemu.elf" --nographic -d
        unimp,guest_errors --semihosting-config enable=on,target=native
    )
    set_tests_properties (
      "${PLATFORM_NAME}-${_app}-qemu"
      PROPERTIES LABELS "qemu" TIMEOUT 300
    )
  endif ()

  # The same run through the board's hw.sh, label hwsh: kept until the
  # OpenOCD runs are proven on the board (step 7).
  add_test (
    NAME "${PLATFORM_NAME}-${_app}-hwsh"
    COMMAND bash "${_board_hw}" "${_app}" 600
  )
  set_tests_properties (
    "${PLATFORM_NAME}-${_app}-hwsh"
    PROPERTIES ENVIRONMENT "BUILD=${_port_bin}" LABELS "hwsh" TIMEOUT 1200
  )
  # The hardware run: OpenOCD from CTest (cmake/uos-tests-run.cmake), the
  # board's commands above.
  uos_tests_add_openocd (
    NAME "${PLATFORM_NAME}-${_app}-hwd" APP "${_app}"
    ELF "$<TARGET_FILE:${_app}-hwd>" CFG "${CMAKE_CURRENT_SOURCE_DIR}/openocd.cfg"
    COMMANDS ${_hwd_flash} TIMEOUT 1200
  )
endforeach ()

# -----------------------------------------------------------------------------
message (STATUS
         "Cortex-M pico2-rp2350b-psram: port tests registered (${PLATFORM_NAME})")
