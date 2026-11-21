# -----------------------------------------------------------------------------
# Test executables — µOS++ III AArch64 on the Raspberry Pi 4 B.
#
# BOARD=rpi4b of the AArch64 port: BCM2711, 4x Cortex-A72, GIC-400. The
# board's own sources are this platform's include/ and src/, its tests
# tests/ (the Pi 3 B's tests carried over, without usb_test).
#
#   hwd    runs on the board through OpenOCD, started by CTest
#          (uos_tests_add_hwd below, tests/cmake/uos-hwd.tcl); before each
#          test a CTest fixture resets the board through its PM watchdog
#          (tests/cmake/uos-hwd-reset.cmake), so the hwd cases can run one
#          after another.
#   qemu   raspi4b (QEMU >= 9.0), handed the raw image directly (-kernel):
#          QEMU enters it at EL2 in AArch64 and holds cores 1-3 in the
#          spin-table, like the Pi 4 firmware's armstub8.
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
# (cmake/board.cmake); the tests' builder below reads them.

# -----------------------------------------------------------------------------
# Build every test (qemu + hwd) with the tests' builder (board-tests/).
# The board tests, built by the tests' own builder (board-tests/) from the
# board's test folder (this platform's tests/).
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

# -----------------------------------------------------------------------------
# The QEMU binary and machine arguments: raspi4b, image handed to -kernel.
unset (_qemu CACHE)
find_program (
  _qemu qemu-system-aarch64
  HINTS "${CMAKE_BINARY_DIR}/xpacks/.bin"
)
if (NOT _qemu)
  set (_qemu "qemu-system-aarch64")
endif ()

# -----------------------------------------------------------------------------
# One CTest case per (test, variant).
# One CTest case per test the builder built (board-tests/: UOS_TESTS_APPS).
foreach (_app IN LISTS UOS_TESTS_APPS)

  uos_tests_add_qemu (
    NAME "${PLATFORM_NAME}-${_app}-qemu" APP "${_app}"
    IMAGE "${_port_bin}/${_app}-qemu.bin"
    QEMU "${_qemu}" MACHINE -M raspi4b -smp 4
  )

  # The hardware run: OpenOCD from CTest (cmake/uos-tests-run.cmake,
  # cmake/uos-hwd.tcl), the PM watchdog reset as its fixture.
  uos_tests_add_hwd (
    NAME "${PLATFORM_NAME}-${_app}-hwd" APP "${_app}" ELF "$<TARGET_FILE:${_app}-hwd>"
    CFG "${CMAKE_CURRENT_SOURCE_DIR}/openocd-cmsis-dap-rpi4b.cfg" INIT
    ENTRY 0x80000 TARGET_FMT "bcm2711.cpu%d" CORES 0
    SEMIHOST_CORES 0 1 2 3 RESUME pc-first
    RESET_COMMAND "init; targets bcm2711.cpu0; halt; catch {mww 0xfe100024 0x5a000001}; catch {mww 0xfe10001c 0x5a000020}; shutdown"
    RESET_EXPECT "tap/device found" RESET_WAIT 10
    TIMEOUT 2400
  )
endforeach ()

# -----------------------------------------------------------------------------
# Upstream's suites (UOS_TESTS_SUITES above) are not a special case: the
# tests' builder builds them from test::<suite> on this platform's start-up
# (src/platform-support.cpp; the validator's glue is
# src/cmsis-os-validator-support.cpp), and the loop above registers their
# qemu and hwd cases with every other test's.

# -----------------------------------------------------------------------------
message (STATUS "AArch64 rpi4b: port tests + harness suites registered")
