# -----------------------------------------------------------------------------
# Test executables — µOS++ III Cortex-M on the Raspberry Pi Pico (RP2040).
#
# The board's tests are this platform's tests/<app>/, built by the tests' builder
# (board-tests/), which compiles each test as `-hwd` for the probe (the
# JTAGprobe, SWD; see openocd.cfg) and,
# for the tests the board can run emulated, `-qemu`. This platform
# registers what it produced, every test named `<platform>-<app>-<variant>`.
#
# hwd tests need the board: they carry the `hwd` label, which the
# configuration's `test` action skips (`ctest -LE hwd`), and run one at
# a time (RUN_SERIAL); OpenOCD programs and resets the board for each.
#
# The `qemu` images end themselves: each test prints a RESULT line and, under
# QEMU_BUILD, exits through the strong semihosting _Exit() (see the port's
# board-tests/cortexm/hw_result.hpp), so CTest reads a real exit code and needs
# no runner script.
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
set (UOS_TESTS_SUITES rtos-apis mutex-stress cmsis-os-validator fp-switch)
set (UOS_TESTS_STARTUP_LIBS micro-os-plus::iii-semihosting
     micro-os-plus::iii-newlib-reent micro-os-plus::iii-posix-io)
# The board-only tests: this platform's tests/ (tests.cmake, include/, src/,
# one folder per test).
set (UOS_TESTS_BOARD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/tests")
add_subdirectory ("${CMAKE_SOURCE_DIR}/board-tests" "port-tests/test")

set (_port_bin "${CMAKE_CURRENT_BINARY_DIR}/port-tests")

# The QEMU binary, for the tests the board can run emulated. QEMU has no
# RP2040 and no Cortex-M0 machine; the images are built for the Cortex-M0
# (ARMv6-M, a subset of what the M3 runs) and run on QEMU's mps2-an385 with a
# Cortex-M3, as the harness's qemu-cortex-m0 platform does. The RP2040-only
# blocks (SIO, USB) are listed HWD_ONLY and never get a `qemu` image.
unset (_qemu CACHE)
find_program (
  _qemu qemu-system-arm
  HINTS "${CMAKE_BINARY_DIR}/xpacks/.bin"
)
if (NOT _qemu)
  set (_qemu "qemu-system-arm")
endif ()

# -----------------------------------------------------------------------------
# One CTest case per (test, variant). The port's builder emits <app>-hwd for
# every test and <app>-qemu only for the ones the board can run emulated (its
# tests.cmake lists the rest HWD_ONLY), so the qemu case is registered only
# when the target exists.
# One CTest case per test the builder built (board-tests/: UOS_TESTS_APPS).
include ("${CMAKE_SOURCE_DIR}/cmake/uos-tests-run.cmake")

# The hardware run's OpenOCD commands (the board's own commands): program,
# reset, semihosting on, run.
set (_hwd_flash
     "init" "reset init" "program {@ELF@} verify" "reset init"
     "targets rp2040.core1" "arm semihosting enable" "resume"
     "targets rp2040.core0" "arm semihosting enable" "resume")
set (_hwd_ram
     "init" "reset init"
     "rp2040.core0 configure -work-area-phys 0x20041000 -work-area-size 0x1000"
     "load_image {@ELF@}" "verify_image {@ELF@}"
     "targets rp2040.core1" "arm semihosting enable" "resume"
     "targets rp2040.core0" "arm semihosting enable"
     [=[set v [read_memory 0x20000000 32 2]]=]
     "mww 0xe000ed08 0x20000000"
     [=[reg sp [lindex $v 0]]=]
     [=[reg pc [expr {[lindex $v 1] & ~1}]]=]
     "resume")
# The Pico's SWD clock: UOS_HW_ADAPTER_KHZ in the environment, else 15000
#.
set (_hwd_pre_cfg
     [=[set ADAPTER_KHZ [expr {[info exists ::env(UOS_HW_ADAPTER_KHZ)] ? $::env(UOS_HW_ADAPTER_KHZ) : 15000}]]=])

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

  # A board run gets 4 minutes; CTest's allows one more
  # for flashing and tear-down.
  # The hardware run: OpenOCD from CTest (cmake/uos-tests-run.cmake), the
  # board's commands above (the -ram variants run from RAM).
  if (_app MATCHES "-ram$")
    set (_hwd_commands ${_hwd_ram})
  else ()
    set (_hwd_commands ${_hwd_flash})
  endif ()
  uos_tests_add_openocd (
    NAME "${PLATFORM_NAME}-${_app}-hwd" APP "${_app}"
    ELF "$<TARGET_FILE:${_app}-hwd>" CFG "${CMAKE_CURRENT_SOURCE_DIR}/openocd.cfg" PRE_CFG ${_hwd_pre_cfg}
    COMMANDS ${_hwd_commands} TIMEOUT 300
  )
endforeach ()

# -----------------------------------------------------------------------------
message (STATUS "Cortex-M pico: port tests registered (${PLATFORM_NAME})")
