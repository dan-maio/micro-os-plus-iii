# -----------------------------------------------------------------------------
# Test executables — µOS++ III Cortex-M on the Raspberry Pi Pico (RP2040).
#
# The port owns its tests (test/pico/<app>/) and its own builder
# (test/CMakeLists.txt), which compiles each test as `-hwd` for the probe (the
# JTAGprobe, SWD; see the board's hw.sh) and,
# for the tests the board can run emulated, `-qemu`. This platform reuses that
# builder and registers what it produced, so every test the port has appears,
# named `<platform>-<app>-<variant>`.
#
# hwd tests are NOT run by a plain `ctest`: they need the board, one test per
# power cycle. They carry the `hwd` label.
#
# The `qemu` images end themselves: each test prints a RESULT line and, under
# QEMU_BUILD, exits through the strong semihosting _Exit() (see the port's
# test/boards/shared/hw_result.hpp), so CTest reads a real exit code and needs
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
set (UOS_TESTS_BOARD_DIR "${UOS_CORTEXM_DIR}/test/${BOARD}")
add_subdirectory ("${CMAKE_SOURCE_DIR}/board-tests" "port-tests/test")

set (_port_bin "${CMAKE_CURRENT_BINARY_DIR}/port-tests")
set (_port_test_dir "${UOS_CORTEXM_DIR}/test/${BOARD}")
set (_board_hw "${UOS_CORTEXM_DIR}/test/boards/${BOARD}/hw.sh")

# The QEMU binary, for the tests the board can run emulated. QEMU has no
# RP2040 and no Cortex-M0 machine; the images are built for the Cortex-M0
# (ARMv6-M, a subset of what the M3 runs) and run on QEMU's mps2-an385 with a
# Cortex-M3, as the harness's qemu-cortex-m0 platform does. The RP2040-only
# blocks (SIO, USB) are listed HWD_ONLY and never get a `qemu` image.
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
foreach (_app IN LISTS UOS_TESTS_APPS)

  if (TARGET "${_app}-qemu")
    add_test (
      NAME "${PLATFORM_NAME}-${_app}-qemu"
      COMMAND
        "${_qemu}" -M mps2-an385 -cpu cortex-m3
        -kernel "${_port_bin}/test/${_app}-qemu.elf" --nographic -d
        unimp,guest_errors --semihosting-config enable=on,target=native
    )
    set_tests_properties (
      "${PLATFORM_NAME}-${_app}-qemu"
      PROPERTIES LABELS "qemu" TIMEOUT 300
    )
  endif ()

  # A board run gets 4 minutes (hw.sh's own limit); CTest's allows one more
  # for flashing and tear-down, so hw.sh reports the TIMEOUT, not CTest.
  add_test (
    NAME "${PLATFORM_NAME}-${_app}-hwd"
    COMMAND bash "${_board_hw}" "${_app}" 240
  )
  set_tests_properties (
    "${PLATFORM_NAME}-${_app}-hwd"
    PROPERTIES ENVIRONMENT "BUILD=${_port_bin}" LABELS "hwd" TIMEOUT 300
  )
endforeach ()

# -----------------------------------------------------------------------------
message (STATUS "Cortex-M pico: port tests registered (${PLATFORM_NAME})")
