# -----------------------------------------------------------------------------
# Test executables — µOS++ III AArch32 on the Luckfox Lyra B (RK3506).
#
# The Lyra is HARDWARE ONLY: its board.cmake sets no UOS_BOARD_LINKER_QEMU, so
# the port's builder emits one image per test, `<app>-hwd`, and there is no
# emulated suite. This platform reuses that builder, so every test the port has
# appears here, and registers each as `<platform>-<app>-hwd`.
#
# hwd tests are NOT run by a plain `ctest`: they need the board, one test per
# power cycle. They carry the `hwd` label; run the whole emulated set with
# `ctest -LE hwd`, or one test explicitly by name.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/${PLATFORM_NAME}'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")

# The board facts and micro-os-plus::board come from cmake/platform-library.cmake
# (cmake/board.cmake); the port's builder below reads them.

# -----------------------------------------------------------------------------
# Build the port's tests by reusing the port's builder. The binary dir ends in
# `test`, which is what the board's hw.sh expects ($BUILD/test/<app>-hwd).
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

set (_port_bin "${CMAKE_CURRENT_BINARY_DIR}/port-tests")
set (_port_test_dir "${CMAKE_CURRENT_SOURCE_DIR}/tests")
set (_board_hw "${CMAKE_CURRENT_SOURCE_DIR}/hw.sh")

# -----------------------------------------------------------------------------
# One CTest case per test the builder built (board-tests/: UOS_TESTS_APPS).
foreach (_app IN LISTS UOS_TESTS_APPS)

  add_test (
    NAME "${PLATFORM_NAME}-${_app}-hwd"
    COMMAND bash "${_board_hw}" "${_app}" 600
  )
  set_tests_properties (
    "${PLATFORM_NAME}-${_app}-hwd"
    PROPERTIES ENVIRONMENT "BUILD=${_port_bin};UOS_SMP_DIR=${CMAKE_SOURCE_DIR}/.." LABELS "hwd" TIMEOUT 1200
  )
endforeach ()

# -----------------------------------------------------------------------------
# The harness suites, on the same board. They supply no main() and no startup
# hooks, so they link micro-os-plus::platform-support. The image lands where
# the board's hw.sh looks for it, <bin>/port-tests/test/<name>-hwd.
#
# The board's shared SMP bring-up (tests/src/test-smp-boot.cpp:
# smp_install_boot_threads() and test_wait_secondaries()) is compiled in here
# too. The port's own builder adds test/<board>/src/*.cpp to every test it
# builds, which is how the Pi harness suites get these symbols; this platform
# registers its harness suites itself, so it names the file directly.
function (add_harness_suite _suite _name)
  cmake_parse_arguments (T "" "" "LIBRARIES" ${ARGN})
  add_executable (${_name})
  target_include_directories (
    ${_name} PRIVATE "${_port_test_dir}/include"
  )
  target_sources (
    ${_name} PRIVATE "${_port_test_dir}/src/test-smp-boot.cpp"
  )
  target_link_libraries (
    ${_name}
    PRIVATE micro-os-plus::common-options test::${_suite} micro-os-plus::iii
            micro-os-plus::platform micro-os-plus::platform-support
            ${T_LIBRARIES}
  )
  set_target_properties (
    ${_name} PROPERTIES OUTPUT_NAME "${_name}-hwd" SUFFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${_port_bin}/test"
  )
  add_custom_command (
    TARGET ${_name}
    POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O binary "$<TARGET_FILE:${_name}>"
            "$<TARGET_FILE:${_name}>.bin"
    VERBATIM
  )
  add_test (
    NAME "${PLATFORM_NAME}-${_name}-hwd"
    COMMAND bash "${_board_hw}" "${_name}" 600
  )
  set_tests_properties (
    "${PLATFORM_NAME}-${_name}-hwd"
    PROPERTIES ENVIRONMENT "BUILD=${_port_bin};UOS_SMP_DIR=${CMAKE_SOURCE_DIR}/.." LABELS "hwd" TIMEOUT 1200
  )
endfunction ()

add_harness_suite (mutex-stress mutex-stress-test)

# -----------------------------------------------------------------------------
message (STATUS "AArch32 Luckfox Lyra: port tests + harness suites registered")
