# -----------------------------------------------------------------------------
# Test executables — µOS++ III on the host (the POSIX-arch port).
#
# The port is micro-os-plus-iii-posix-arch.git (selected by tests-main.cmake
# for a `native*` platform). Its tests are host executables -- the "CPUs" are
# host threads -- so its builder emits one image per test, `<app>-host`, and
# the shared runner is test_smpl/run-host.sh.
#
# As on the AArch32 platforms, the tests are not re-listed: the port's builder
# is add_subdirectory()'d and the targets it produced are registered, one CTest
# case per test.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/${PLATFORM_NAME}'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")

# The port publishes its board facts; read the board declaration so the port's
# own builder sees UOS_BOARD_DEVICES and the rest.
if (NOT DEFINED BOARD)
  set (BOARD "native" CACHE STRING "Target board (the port's board id)")
endif ()
include ("${UOS_POSIX_ARCH_DIR}/test/boards/${BOARD}/board.cmake")

# -----------------------------------------------------------------------------
# Build every port test by reusing the port's builder (<app>-host).
add_subdirectory ("${UOS_POSIX_ARCH_DIR}/test" "port-tests")

set (_port_bin "${CMAKE_CURRENT_BINARY_DIR}/port-tests")
set (_port_test_dir "${UOS_POSIX_ARCH_DIR}/test/${BOARD}")
set (_runner "${CMAKE_SOURCE_DIR}/../test_smpl")

# -----------------------------------------------------------------------------
# One CTest case per port test: <platform>-<app>-host.
file (GLOB _test_dirs LIST_DIRECTORIES true "${_port_test_dir}/*")
foreach (_dir IN LISTS _test_dirs)
  if (NOT IS_DIRECTORY "${_dir}")
    continue ()
  endif ()
  get_filename_component (_app "${_dir}" NAME)
  if (_app STREQUAL "include" OR _app STREQUAL "src")
    continue ()
  endif ()
  file (GLOB _srcs "${_dir}/*.cpp")
  if (NOT _srcs)
    continue ()
  endif ()

  add_test (
    NAME "${PLATFORM_NAME}-${_app}-host"
    COMMAND bash "${_runner}/run-host.sh" "${_port_bin}"
  )
  set_tests_properties (
    "${PLATFORM_NAME}-${_app}-host"
    PROPERTIES ENVIRONMENT "UOS_RUN_ONLY=${_app}" LABELS "host" TIMEOUT 1200
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
