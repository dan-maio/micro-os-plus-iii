# -----------------------------------------------------------------------------
# Test executables — µOS++ III AArch32 on the Luckfox Lyra B (RK3506).
#
# The Lyra is HARDWARE ONLY: its board.cmake sets no UOS_BOARD_LINKER_QEMU, so
# the tests' builder emits one image per test, `<app>-hwd`, and there is no
# emulated suite. This platform reuses that builder, so every test the port has
# appears here, and registers each as `<platform>-<app>-hwd`.
#
# hwd tests need the board: they carry the `hwd` label, which the
# configuration's `test` action skips (`ctest -LE hwd`), and run one at
# a time (RUN_SERIAL); a reset fixture precedes each, so no power cycle.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/${PLATFORM_NAME}'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")

# The board facts and micro-os-plus::board come from cmake/platform-library.cmake
# (cmake/board.cmake); the tests' builder below reads them.

# -----------------------------------------------------------------------------
# Build the board's tests with the tests' builder (board-tests/); the images
# land in port-tests/test/.
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
# Upstream's suites this board runs: the same path every other board uses.
set (UOS_TESTS_SUITES mutex-stress)
# The platform start-up's needs (src/platform-support.cpp): the C library's
# system calls (semihosting), its reentrancy and the POSIX I/O layer.
# The console stays on the UART (the board's uart.hpp): every semihosting
# call is a debug halt and a WCH-Link round trip, about a second per line
# (more from cores 1 and 2), and a test that prints much spent its run in the
# debugger (smp-num-test, smp-mat-test: past the 600 s cap; heavy semihosting
# can also drop the link). The verdict still reaches semihosting
# (board-tests/portable-test-end.cpp: semihosting::report_result ()).
set (UOS_TESTS_STARTUP_DEFINES UOS_CONSOLE_UART_ONLY)
set (UOS_TESTS_STARTUP_LIBS micro-os-plus::iii-semihosting
     micro-os-plus::iii-newlib-reent micro-os-plus::iii-posix-io)
# Of those, the ones that use the SD card: the card as the posix-io block
# device /dev/sd, under the Chan FatFs file system.
set (UOS_TESTS_STORAGE sd_test smp-mat-sdcard-test smp-num-test
     smp-pipeline-test)
set (UOS_TESTS_PORT aarch32)
# The board-only tests: this platform's tests/ (tests.cmake, include/, src/,
# one folder per test).
set (UOS_TESTS_BOARD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/tests")
add_subdirectory ("${CMAKE_SOURCE_DIR}/board-tests" "port-tests/test")

# -----------------------------------------------------------------------------
# One CTest case per test the builder built (board-tests/: UOS_TESTS_APPS).
include ("${CMAKE_SOURCE_DIR}/cmake/uos-tests-run.cmake")

# The hardware run's facts (the board's own commands): core 0 alone (the
# secondaries are held in reset until the kernel releases them), resumed at the
# entry with no register touched (the RK3506's loader leaves SVC), 4 MHz SWD,
# the RK3506 full global reset as a fixture, and the pre-load that turns the
# MMU and caches off (the loader leaves them on, and load_image through them
# leaves DRAM holding something else).
set (_lyra_preload [=[if {[catch {
  set _t [target current]
  set _s [$_t arm mrc 15 0 1 0 0]
  $_t arm mcr 15 0 1 0 0 [expr {$_s & ~0x1005}]
  $_t arm mcr 15 0 7 5 0 0
  $_t arm mcr 15 0 7 5 6 0
  $_t arm mcr 15 0 8 7 0 0
} _e]} { echo "SANITIZE-ERR: $_e" } else { echo [format "SANITIZE-OK: SCTLR 0x%08x -> MMU/caches off" $_s] }]=])
function (lyra_add_hwd _test _elf)
  uos_tests_add_hwd (
    NAME "${PLATFORM_NAME}-${_test}-hwd" APP "${_test}" ELF "${_elf}"
    CFG "${CMAKE_CURRENT_SOURCE_DIR}/openocd.cfg"
    ENTRY 0x00200000 TARGET_FMT "rk3506.a7.%d" CORES 0 SEMIHOST_CORES 0
    RESUME entry ADAPTER_KHZ 4000 PRELOAD "${_lyra_preload}"
    RESET_COMMAND "catch { rk3506_reset_full }; shutdown"
    RESET_EXPECT "Triggering RK3506 Full Global Software Reset" RESET_WAIT 3
    TIMEOUT 1200
  )
endfunction ()

foreach (_app IN LISTS UOS_TESTS_APPS)

  lyra_add_hwd ("${_app}" "$<TARGET_FILE:${_app}-hwd>")
endforeach ()

# -----------------------------------------------------------------------------
message (STATUS "AArch32 Luckfox Lyra: port tests + harness suites registered")
