# -----------------------------------------------------------------------------
# Test executables — µOS++ III Cortex-M on the Pi-Zero RP2350B (16 MB flash).
#
# The port owns its tests (test/pico2-pizero/<app>/) and its own builder
# (test/CMakeLists.txt). This board is hardware-only -- QEMU has no Cortex-M33
# and the board is built ARMv8-M -- so the builder emits `hwd` alone and this
# platform registers what it produced, named `<platform>-<app>-hwd`.
#
# hwd tests are NOT run by a plain `ctest`: they need the board, one test per
# power cycle. They carry the `hwd` label.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/${PLATFORM_NAME}'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")

# The board facts and micro-os-plus::board come from cmake/platform-library.cmake
# (cmake/board.cmake); the port's builder below reads them.

# Build the port's tests by reusing the port's builder. The binary dir ends in
# `test`, which is what the board's hw.sh expects ($BUILD/test/<app>-hwd).
# The board tests, built by the tests' own builder (board-tests/) from the
# board's test folder (still in the port until the tests move into tests/).
set (UOS_TESTS_PORT cortexm)
set (UOS_TESTS_BOARD_DIR "${UOS_CORTEXM_DIR}/test/${BOARD}")
add_subdirectory ("${CMAKE_SOURCE_DIR}/board-tests" "port-tests/test")

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
message (STATUS "Cortex-M pico2-pizero: port tests registered (${PLATFORM_NAME})")
