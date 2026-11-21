# -----------------------------------------------------------------------------
# Test executables — µOS++ III AArch32 on the Raspberry Pi Zero 2 W.
#
# The board's tests are this platform's tests/<app>/; the tests' builder
# (board-tests/) compiles each of them twice -- `qemu` for the emulator and
# `hwd` for the probe -- and this platform registers the targets it produced,
# one CTest case per (test, variant).
#
# CTest runs QEMU and, for the hwd cases, OpenOCD itself
# (tests/cmake/uos-tests-run.cmake). The names carry
# the variant: `<platform>-<app>-qemu` and `<platform>-<app>-hwd`.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/${PLATFORM_NAME}'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")
include ("${CMAKE_SOURCE_DIR}/cmake/uos-tests-run.cmake")

# The board facts and micro-os-plus::board come from cmake/platform-library.cmake
# (cmake/board.cmake); the tests' builder below reads them.

# -----------------------------------------------------------------------------
# Build the board's tests with the tests' builder (board-tests/). It emits, per test
# directory, <app>-qemu and <app>-hwd (this board has both linker scripts),
# plus the AArch64->AArch32 QEMU boot shim (target `qemu-shim`).
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
# The platform start-up's needs (src/platform-support.cpp): the C library's
# system calls (semihosting), its reentrancy and the POSIX I/O layer.
set (UOS_TESTS_STARTUP_LIBS micro-os-plus::iii-semihosting
     micro-os-plus::iii-newlib-reent micro-os-plus::iii-posix-io)
# Of those, the ones that use the SD card: the card as the posix-io block
# device /dev/sd, under the Chan FatFs file system.
set (UOS_TESTS_STORAGE sd_test smp-mat-sdcard-test smp-num-test
     smp-pipeline-test)
# Upstream's suites (tests/sources/<suite>/), on the platform's start-up; the
# validator's board glue is src/cmsis-os-validator-support.cpp.
set (UOS_TESTS_SUITES mutex-stress rtos-apis cmsis-os-validator)
set (UOS_TESTS_PORT aarch32)
# The board-only tests: this platform's tests/ (tests.cmake, include/, src/,
# one folder per test).
set (UOS_TESTS_BOARD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/tests")
add_subdirectory ("${CMAKE_SOURCE_DIR}/board-tests" "port-tests/test")

set (_port_bin "${CMAKE_CURRENT_BINARY_DIR}/port-tests/test")
set (_shim_img "${_port_bin}/shim8.img")

# -----------------------------------------------------------------------------
# The QEMU binary and machine arguments: raspi3b + the shim, image at 0x10000.
unset (_qemu CACHE)
find_program (
  _qemu qemu-system-aarch64
  HINTS "${CMAKE_BINARY_DIR}/xpacks/.bin"
)
if (NOT _qemu)
  set (_qemu "qemu-system-aarch64")
endif ()

# -----------------------------------------------------------------------------
# One CTest case per test the builder built (board-tests/: UOS_TESTS_APPS).
foreach (_app IN LISTS UOS_TESTS_APPS)

  # --- qemu --------------------------------------------------------------
  uos_tests_add_qemu (
    NAME "${PLATFORM_NAME}-${_app}-qemu" APP "${_app}"
    IMAGE "${_port_bin}/${_app}-qemu.bin"
    QEMU "${_qemu}" MACHINE -M raspi3b -smp 4
    SHIM "${_shim_img}" LOAD_ADDRESS 0x10000
  )

  # --- hwd ---------------------------------------------------------------
  # The hardware run: OpenOCD from CTest (cmake/uos-tests-run.cmake,
  # cmake/uos-hwd.tcl), the PM watchdog reset as its fixture.
  uos_tests_add_hwd (
    NAME "${PLATFORM_NAME}-${_app}-hwd" APP "${_app}" ELF "$<TARGET_FILE:${_app}-hwd>"
    CFG "${CMAKE_CURRENT_SOURCE_DIR}/openocd-probe.cfg" INIT
    ENTRY 0x1003c TARGET_FMT "bcm2837.cpu%d" CORES 0 1 2 3
    SEMIHOST_CORES 0 1 2 3 RESUME cpsr-first
    RESET_COMMAND "init; targets bcm2837.cpu0; halt; mww 0x3f100024 0x5a000001; mww 0x3f10001c 0x5a000020; shutdown"
    RESET_EXPECT "tap/device found" RESET_WAIT 12
    TIMEOUT 1200
  )
endforeach ()

# -----------------------------------------------------------------------------
message (
  STATUS
    "AArch32 rpi-zero-2w: port tests + harness suites registered (${PLATFORM_NAME})"
)

