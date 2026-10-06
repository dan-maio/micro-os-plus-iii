# -----------------------------------------------------------------------------
# Test executables — µOS++ III AArch32 on the Raspberry Pi Zero 2 W.
#
# The port owns its tests (test/rpi-zero-2w/<app>/), and its own builder
# (test/CMakeLists.txt) knows how to compile each of them twice -- `qemu` for
# the emulator and `hwd` for the probe. So this platform does not re-list the
# tests: it add_subdirectory()s the port's builder and then registers the
# targets it produced, one CTest case per (test, variant). Every test the port
# has appears here, and a test added to the port appears here with no edit.
#
# The run side is the shared runner (test_smpl/run-qemu.sh, run-hw.sh), the
# same pair the port's own qemu.sh/hw.sh call. The names carry the variant:
# `<platform>-<app>-qemu` and `<platform>-<app>-hwd`.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/${PLATFORM_NAME}'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")

# -----------------------------------------------------------------------------
# The port publishes most board facts as CACHE INTERNAL, but not
# UOS_BOARD_DEVICES; read the board declaration so the port's own test builder
# (add_subdirectory'd below) sees the driver set its tests link.
include ("${UOS_AARCH32_DIR}/test/boards/${BOARD}/board.cmake")

# -----------------------------------------------------------------------------
# Build the port's tests by reusing the port's builder. It emits, per test
# directory, <app>-qemu and <app>-hwd (this board has both linker scripts),
# plus the AArch64->AArch32 QEMU boot shim (target `qemu-shim`).
add_subdirectory ("${UOS_AARCH32_DIR}/test" "port-tests/test")

set (_port_bin "${CMAKE_CURRENT_BINARY_DIR}/port-tests/test")
set (_port_test_dir "${UOS_AARCH32_DIR}/test/rpi-zero-2w")
set (_board_hw "${UOS_AARCH32_DIR}/test/boards/${BOARD}/hw.sh")
set (_shim_img "${_port_bin}/shim8.img")
set (_runner "${CMAKE_SOURCE_DIR}/../test_smpl")

# -----------------------------------------------------------------------------
# The QEMU binary and machine arguments: raspi3b + the shim, image at 0x10000.
file (GLOB _qemu_bins
      "$ENV{HOME}/.local/xPacks/@xpack-dev-tools/qemu-arm/*/.content/bin")
if (_qemu_bins)
  list (SORT _qemu_bins COMPARE NATURAL ORDER DESCENDING)
  list (GET _qemu_bins 0 _qemu_bin)
  set (_qemu "${_qemu_bin}/qemu-system-aarch64")
else ()
  set (_qemu "qemu-system-aarch64")
endif ()

# -----------------------------------------------------------------------------
# One CTest case per (test, variant). The test list is the port's own: the
# directories under test/rpi-zero-2w/ that hold sources, exactly as the port's
# builder enumerates them.
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

  # --- qemu --------------------------------------------------------------
  add_test (
    NAME "${PLATFORM_NAME}-${_app}-qemu"
    COMMAND
      bash "${_runner}/run-qemu.sh" "${_port_bin}" "${_qemu}" -M raspi3b
      -smp 4
  )
  set_tests_properties (
    "${PLATFORM_NAME}-${_app}-qemu"
    PROPERTIES
      ENVIRONMENT
      "UOS_QEMU_SHIM=${_shim_img};UOS_QEMU_LOAD_ADDR=0x10000;UOS_QEMU_ONLY=${_app};UOS_TEST_SRC_DIR=${_port_test_dir}"
      LABELS "qemu" TIMEOUT 2400
  )

  # --- hwd ---------------------------------------------------------------
  add_test (
    NAME "${PLATFORM_NAME}-${_app}-hwd"
    COMMAND bash "${_board_hw}" "${_app}" 600
  )
  set_tests_properties (
    "${PLATFORM_NAME}-${_app}-hwd"
    PROPERTIES ENVIRONMENT "BUILD=${CMAKE_CURRENT_BINARY_DIR}/port-tests"
               LABELS "hwd" TIMEOUT 1200
  )
endforeach ()

# -----------------------------------------------------------------------------
message (
  STATUS
    "AArch32 rpi-zero-2w: port tests + harness suites registered (${PLATFORM_NAME})"
)

