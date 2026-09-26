# -----------------------------------------------------------------------------
# Test executables — µOS++ III Cortex-M on the Raspberry Pi Pico 2 (RP2350).
#
# The port owns its tests (test/pico2/<app>/) and its own builder
# (test/CMakeLists.txt), which compiles each test as `-hwd` for the probe and,
# for the tests the board can run emulated, `-qemu`. This platform reuses that
# builder and registers what it produced, so every test the port has appears,
# named `<platform>-<app>-<variant>`.
#
# hwd tests are NOT run by a plain `ctest`: they need the board, one test per
# power cycle. They carry the `hwd` label.
#
# The `qemu` images end themselves: each test prints a RESULT line and, under
# QEMU_BUILD, exits through the strong semihosting _Exit() (see the port's
# test/pico2/include/hw_result.hpp), so CTest reads a real exit code and needs
# no runner script.
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

# The QEMU binary, for the tests the board can run emulated. The RP2350's
# Cortex-M33 is close enough to QEMU's generic mps2-an500 Cortex-M7 for the
# core bring-up and kernel-object tests; the RP2350-only blocks (SIO, USB,
# PSRAM) are listed HWD_ONLY and never get a `qemu` image.
file (GLOB _qemu_bins
      "$ENV{HOME}/.local/xPacks/@xpack-dev-tools/qemu-arm/*/.content/bin")
if (_qemu_bins)
  list (SORT _qemu_bins COMPARE NATURAL ORDER DESCENDING)
  list (GET _qemu_bins 0 _qemu_bin)
  set (_qemu "${_qemu_bin}/qemu-system-arm")
else ()
  set (_qemu "qemu-system-arm")
endif ()

# -----------------------------------------------------------------------------
# One CTest case per (test, variant). The port's builder emits <app>-hwd for
# every test and <app>-qemu only for the ones the board can run emulated (its
# tests.cmake lists the rest HWD_ONLY), so the qemu case is registered only
# when the target exists.
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

  if (TARGET "${_app}-qemu")
    add_test (
      NAME "${PLATFORM_NAME}-${_app}-qemu"
      COMMAND
        "${_qemu}" -M mps2-an500 -cpu cortex-m7
        -kernel "${_port_bin}/test/${_app}-qemu.elf" --nographic -d
        unimp,guest_errors --semihosting-config enable=on,target=native
    )
    set_tests_properties (
      "${PLATFORM_NAME}-${_app}-qemu"
      PROPERTIES LABELS "qemu" TIMEOUT 300
    )
  endif ()

  # A board run gets 4 minutes (hw.sh's own limit); CTest's allows one more
  # for flashing and tear-down, so hw.sh reports the TIMEOUT, not CTest.
  add_test (
    NAME "${PLATFORM_NAME}-${_app}-hwd"
    COMMAND bash "${_board_hw}" "${_app}" 240
  )
  set_tests_properties (
    "${PLATFORM_NAME}-${_app}-hwd"
    PROPERTIES ENVIRONMENT "BUILD=${_port_bin}" LABELS "hwd" TIMEOUT 300
  )
endforeach ()

# -----------------------------------------------------------------------------
message (STATUS "Cortex-M pico2: port tests registered (${PLATFORM_NAME})")
