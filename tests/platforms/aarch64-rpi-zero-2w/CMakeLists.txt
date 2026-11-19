# -----------------------------------------------------------------------------
# Test executables — µOS++ III AArch64 on the Raspberry Pi Zero 2 W.
#
# QEMU: raspi3b, handed the raw image directly (-kernel): QEMU starts its
# Cortex-A53 cores in AArch64, which is the state this port runs in, so there
# is no boot shim.
#
# The board's tests are this platform's tests/<app>/, and the tests' builder
# (board-tests/) compiles each twice -- `qemu` and `hwd` -- so every one
# appears, named `<platform>-<app>-qemu` / `-hwd`.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/${PLATFORM_NAME}'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")
include ("${CMAKE_SOURCE_DIR}/cmake/uos-tests-run.cmake")

# The board facts and micro-os-plus::board come from cmake/platform-library.cmake
# (cmake/board.cmake); the port's builder below reads them.

# -----------------------------------------------------------------------------
# Build every port test (qemu + hwd) by reusing the port's builder.
# The board tests, built by the tests' own builder (board-tests/) from the
# board's test folder (still in the port until the tests move into tests/).
# The portable tests this board runs (tests/sources/).
set (UOS_TESTS_SOURCES smp_test0 smp_test1 smp_test2 smp_test3 smp_test4
     smp-num-test smp-pipeline-test smp-pro-cons-test smp-mat-test sd_test
     smp-mat-sdcard-test clock-test)
# Of those, the ones that are os_main() only (the platform starts them up).
set (UOS_TESTS_PORTABLE smp_test0 smp_test1 smp_test2 smp_test3 smp_test4
     smp-num-test smp-pipeline-test smp-pro-cons-test smp-mat-test sd_test
     smp-mat-sdcard-test clock-test)
# Of those, the ones that use the SD card: the card as the posix-io block
# device /dev/sd, under the Chan FatFs file system.
set (UOS_TESTS_STORAGE sd_test smp-mat-sdcard-test smp-num-test
     smp-pipeline-test)
# Upstream's suites (tests/sources/<suite>/), on the platform's start-up; the
# validator's board glue is src/cmsis-os-validator-support.cpp.
set (UOS_TESTS_SUITES mutex-stress rtos-apis cmsis-os-validator)
set (UOS_TESTS_PORT aarch64)
# The board-only tests: this platform's tests/ (tests.cmake, include/, src/,
# one folder per test).
set (UOS_TESTS_BOARD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/tests")
add_subdirectory ("${CMAKE_SOURCE_DIR}/board-tests" "port-tests/test")

set (_port_bin "${CMAKE_CURRENT_BINARY_DIR}/port-tests/test")
set (_board_hw "${CMAKE_CURRENT_SOURCE_DIR}/hw.sh")

# -----------------------------------------------------------------------------
# The QEMU binary and machine arguments: raspi3b, image handed to -kernel.
file (GLOB _qemu_bins
      "$ENV{HOME}/.local/xPacks/@xpack-dev-tools/qemu-arm/*/.content/bin")
if (_qemu_bins)
  list (SORT _qemu_bins COMPARE NATURAL ORDER DESCENDING)
  list (GET _qemu_bins 0 _qemu_bin)
  set (_qemu "${_qemu_bin}/qemu-system-aarch64")
else ()
  set (_qemu "qemu-system-aarch64")
endif ()

# -----------------------------------------------------------------------------
# One CTest case per (test, variant).
# One CTest case per test the builder built (board-tests/: UOS_TESTS_APPS).
foreach (_app IN LISTS UOS_TESTS_APPS)

  uos_tests_add_qemu (
    NAME "${PLATFORM_NAME}-${_app}-qemu" APP "${_app}"
    IMAGE "${_port_bin}/${_app}-qemu.bin"
    QEMU "${_qemu}" MACHINE -M raspi3b -smp 4
  )

  # The same run through the board's hw.sh (test_smpl/run-hw.sh), label
  # hwsh: kept until the OpenOCD runs are proven on the board (step 7).
  add_test (
    NAME "${PLATFORM_NAME}-${_app}-hwsh"
    COMMAND bash "${_board_hw}" "${_app}" 600
  )
  set_tests_properties (
    "${PLATFORM_NAME}-${_app}-hwsh"
    PROPERTIES ENVIRONMENT "BUILD=${CMAKE_CURRENT_BINARY_DIR}/port-tests;UOS_SMP_DIR=${CMAKE_SOURCE_DIR}/.."
               LABELS "hwsh" TIMEOUT 1200
  )
  # The hardware run: OpenOCD from CTest (cmake/uos-tests-run.cmake,
  # cmake/uos-hwd.tcl), the PM watchdog reset as its fixture.
  uos_tests_add_hwd (
    NAME "${PLATFORM_NAME}-${_app}-hwd" APP "${_app}" ELF "$<TARGET_FILE:${_app}-hwd>"
    CFG "${CMAKE_CURRENT_SOURCE_DIR}/openocd-probe.cfg" INIT
    ENTRY 0x80000 TARGET_FMT "bcm2837.cpu%d" CORES 0 1 2 3
    SEMIHOST_CORES 0 1 2 3 RESUME pc-first
    RESET_COMMAND "init; targets bcm2837.cpu0; halt; mww 0x3f100024 0x5a000001; mww 0x3f10001c 0x5a000020; shutdown"
    RESET_EXPECT "tap/device found" RESET_WAIT 12
    TIMEOUT 1200
  )
endforeach ()

# -----------------------------------------------------------------------------
message (STATUS "AArch64 rpi-zero-2w: port tests + harness suites registered")

