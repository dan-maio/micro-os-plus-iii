# -----------------------------------------------------------------------------
# Test executables — µOS++ III on the host (the POSIX-arch port).
#
# The port is micro-os-plus-iii-posix-arch.git (selected by tests-main.cmake
# for a `native*` platform). Its tests are host executables -- the "CPUs" are
# host threads -- so its builder emits one image per test, `<app>-host`, and
# CTest runs each one itself (tests/cmake/uos-tests-run.cmake).
#
# As on the AArch32 platforms, the tests are not re-listed: the tests' builder
# is add_subdirectory()'d and the targets it produced are registered, one CTest
# case per test.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/${PLATFORM_NAME}'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")
include ("${CMAKE_SOURCE_DIR}/cmake/uos-tests-run.cmake")

# The board facts (BOARD, UOS_BOARD_*) and micro-os-plus::board are set in
# cmake/platform-library.cmake, above; the tests' builder reads them.

# -----------------------------------------------------------------------------
# Build every test with the tests' builder (board-tests/; <app>-host).
# The board tests, built by the tests' own builder (board-tests/) from the
# board's test folder (this platform's tests/).
# The portable tests this board runs (tests/sources/).
set (UOS_TESTS_SOURCES smp_test0 smp_test1 smp_test2 smp_test3 smp_test4
     smp-num-test smp-pipeline-test smp-pro-cons-test smp-mat-test
     clock-test)
# Of those, the ones that are os_main() only (the platform starts them up).
set (UOS_TESTS_PORTABLE smp_test0 smp_test1 smp_test2 smp_test3 smp_test4
     smp-num-test smp-pipeline-test smp-pro-cons-test smp-mat-test
     clock-test)
# Of those, the ones that use the SD card (here a host file): the card as the
# posix-io block device /dev/sd, under the Chan FatFs file system.
set (UOS_TESTS_STORAGE smp-num-test smp-pipeline-test)
# Upstream's suites (tests/sources/<suite>/), on the platform's start-up. The
# board builds them single-core (tests/tests.cmake): the port's OS_NCPU=1
# leg. The validator is registered below, as upstream's native platform does.
set (UOS_TESTS_SUITES mutex-stress rtos-apis)
set (UOS_TESTS_PORT posix)
# The board-only tests: this platform's tests/ (tests.cmake, include/, src/,
# one folder per test).
set (UOS_TESTS_BOARD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/tests")
add_subdirectory ("${CMAKE_SOURCE_DIR}/board-tests" "port-tests")

# -----------------------------------------------------------------------------
# One CTest case per port test: <platform>-<app>-host.
# One CTest case per test the builder built (board-tests/: UOS_TESTS_APPS).
foreach (_app IN LISTS UOS_TESTS_APPS)

  uos_tests_add_host (
    NAME "${PLATFORM_NAME}-${_app}-host" APP "${_app}"
    PROGRAM "$<TARGET_FILE:${_app}-host>"
  )
endforeach ()

# -----------------------------------------------------------------------------
# Harness suite: the Arm CMSIS RTOS validator. On the host the validator xpack
# supplies the NVIC_* shims (SIGUSR1/SIGALRM), so it runs as an ordinary host
# test, no probe and no board. Two port fixes were needed for it to pass:
#   * in_handler_mode() must also report true while the validator's SIGUSR1
#     handler runs (it bumps signal_nesting), or the kernel does not see ISR
#     context and TC_ThreadInterrupts fails;
#   * the message queue's send()/receive() must reschedule after their critical
#     section, or a receiver resumed by a send() waits for the next tick and
#     TC_MsgQWait's immediate assert fails.
add_executable (cmsis-os-validator-test)
target_compile_definitions (
  cmsis-os-validator-test PRIVATE TRACE OS_USE_TRACE_POSIX_STDOUT
)
# The port's own sources carry warnings the strict harness options promote to
# errors (they are compiled here through the interface library).
target_compile_options (
  cmsis-os-validator-test
  PRIVATE -Wno-redundant-decls -Wno-sign-conversion -Wno-missing-declarations
)
target_link_libraries (
  cmsis-os-validator-test
  PRIVATE test::cmsis-os-validator micro-os-plus::iii
          xpacks::arm-cmsis-os-validator micro-os-plus::platform
)
add_test (
  NAME "${PLATFORM_NAME}-cmsis-os-validator-host"
  COMMAND cmsis-os-validator-test
)
set_tests_properties (
  "${PLATFORM_NAME}-cmsis-os-validator-host"
  PROPERTIES LABELS "host" TIMEOUT 600
)

# -----------------------------------------------------------------------------
message (STATUS "native (posix-arch): port tests registered (${PLATFORM_NAME})")
