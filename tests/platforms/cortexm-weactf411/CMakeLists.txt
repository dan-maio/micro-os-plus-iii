# -----------------------------------------------------------------------------
# Test executables — µOS++ III Cortex-M on the WeAct F411CE (STM32F411CE).
#
# The port owns its tests (test/weactf411/<app>/) and its own builder
# (test/CMakeLists.txt). This board is hardware-only -- it is programmed over
# its ST-Link and run on the desk -- so the builder emits `hwd` alone and this
# platform registers what it produced, named `<platform>-<app>-hwd`.
#
# hwd tests are NOT run by a plain `ctest`: they need the board. They carry the
# `hwd` label.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/${PLATFORM_NAME}'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")

# Read the board declaration so the port's own builder sees its facts.
include ("${UOS_CORTEXM_DIR}/test/boards/${BOARD}/board.cmake")

# Build the port's tests by reusing the port's builder. The binary dir ends in
# `test`, which is what the board's hw.sh expects ($BUILD/test/<app>-hwd).
add_subdirectory ("${UOS_CORTEXM_DIR}/test" "port-tests/test")

set (_port_bin "${CMAKE_CURRENT_BINARY_DIR}/port-tests")
set (_port_test_dir "${UOS_CORTEXM_DIR}/test/${BOARD}")
set (_board_hw "${UOS_CORTEXM_DIR}/test/boards/${BOARD}/hw.sh")

# -----------------------------------------------------------------------------
# One CTest case per test. Every one is `hwd`: the board has no `qemu` image.
file (GLOB _test_dirs LIST_DIRECTORIES true "${_port_test_dir}/*")
foreach (_dir IN LISTS _test_dirs)
  if (NOT IS_DIRECTORY "${_dir}")
    continue ()
  endif ()
  get_filename_component (_app "${_dir}" NAME)
  if (_app STREQUAL "include" OR _app STREQUAL "src")
    continue ()
  endif ()
  file (GLOB _srcs "${_dir}/*.c" "${_dir}/*.cpp")
  if (NOT _srcs)
    continue ()
  endif ()

  add_test (
    NAME "${PLATFORM_NAME}-${_app}-hwd"
    COMMAND bash "${_board_hw}" "${_app}" 600
  )
  set_tests_properties (
    "${PLATFORM_NAME}-${_app}-hwd"
    PROPERTIES ENVIRONMENT "BUILD=${_port_bin}" LABELS "hwd" TIMEOUT 1200
  )
endforeach ()

# -----------------------------------------------------------------------------
message (STATUS "Cortex-M weactf411: port tests registered (${PLATFORM_NAME})")
