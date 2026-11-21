# -----------------------------------------------------------------------------
# Test executables — µOS++ III AArch64 on the Raspberry Pi 3 B.
#
# The Zero 2 W platform (aarch64-rpi-zero-2w) with BOARD=rpi3b: the same
# BCM2837 and the same port sources, built with -DBOARD_RPI3B (see
# cmake/definitions.cmake), and the board's own tests. Two differences here:
#
#   hwd    runs on the board through OpenOCD, started by CTest
#          (uos_tests_add_hwd below, tests/cmake/uos-hwd.tcl); before each
#          test a CTest fixture resets the board through its PM watchdog
#          (tests/cmake/uos-hwd-reset.cmake), so the hwd cases can run one
#          after another.
#   usb    usb_test gets NO hwd case: it is a DWC2 USB gadget, and on a real
#          Pi 3 B the USB ports sit behind the LAN9514 hub, so the controller
#          can only be a host. Its qemu case stays.
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
# The QEMU binary and machine arguments: raspi3b, image handed to -kernel.
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
    QEMU "${_qemu}" MACHINE -M raspi3b -smp 4
  )

  # Not usb_test: a USB gadget cannot run on the Pi 3 B (see the header).
  if (_app STREQUAL "usb_test")
    continue ()
  endif ()
  # The hardware run: OpenOCD from CTest (cmake/uos-tests-run.cmake,
  # cmake/uos-hwd.tcl), the PM watchdog reset as its fixture.
  uos_tests_add_hwd (
    NAME "${PLATFORM_NAME}-${_app}-hwd" APP "${_app}" ELF "$<TARGET_FILE:${_app}-hwd>"
    CFG "${CMAKE_SOURCE_DIR}/platforms/aarch64-rpi-zero-2w/openocd-probe.cfg" INIT
    ENTRY 0x80000 TARGET_FMT "bcm2837.cpu%d" CORES 0 1 2 3
    SEMIHOST_CORES 0 1 2 3 RESUME pc-first
    RESET_COMMAND "init; targets bcm2837.cpu0; halt; mww 0x3f100024 0x5a000001; mww 0x3f10001c 0x5a000020; shutdown"
    RESET_EXPECT "tap/device found" RESET_WAIT 12
    TIMEOUT 1200
  )
endforeach ()

# -----------------------------------------------------------------------------
# Upstream's suites (UOS_TESTS_SUITES above) are not a special case: the
# tests' builder builds them from test::<suite> on this platform's start-up
# (src/platform-support.cpp; the validator's glue is
# src/cmsis-os-validator-support.cpp), and the loop above registers their
# qemu and hwd cases with every other test's.

# -----------------------------------------------------------------------------
message (STATUS "AArch64 rpi3b: port tests + harness suites registered")
