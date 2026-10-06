# -----------------------------------------------------------------------------
# Test executables — µOS++ III AArch32 on the Raspberry Pi 3 B.
#
# The Zero 2 W platform (aarch32-rpi-zero-2w) with BOARD=rpi3b: the same
# BCM2837 and the same port sources, built with -DBOARD_RPI3B (see
# cmake/definitions.cmake), and the board's own tests. Two differences here:
#
#   hwd    runs through the board's own hw.sh (test/boards/rpi3b/hw.sh, which
#          hands the Zero 2 W runner its OpenOCD facts), as the Lyra platform
#          does, so the port's builder is add_subdirectory()'d into
#          port-tests/test -- the layout that script expects.
#   usb    usb_test gets NO hwd case: it is a DWC2 USB gadget, and on a real
#          Pi 3 B the USB ports sit behind the LAN9514 hub, so the controller
#          can only be a host. Its qemu case stays.
#
# The port owns its tests (test/rpi3b/<app>/), and its own builder
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
set (_port_test_dir "${UOS_AARCH32_DIR}/test/rpi3b")
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
# directories under test/rpi3b/ that hold sources, exactly as the port's
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
  # Not usb_test: a USB gadget cannot run on the Pi 3 B (see the header).
  if (_app STREQUAL "usb_test")
    continue ()
  endif ()
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
# The harness suites are NOT a special case here.
#
# mutex-stress and rtos-apis are built as board apps by the port's own builder
# above: test/rpi3b/<suite>/ carries the wrapper that prints the RESULT line,
# and test/rpi3b/tests.cmake's board_test_libs() names the harness's
# test::<suite> plus aarch32-rpi3b-harness-suite (the suite's os-app-config.h,
# the semihosting groups, the startup hooks and --wrap=os_main). The loop
# further up therefore registers their qemu and hwd cases with the same code
# path as every port test -- `<platform>-mutex-stress-qemu` and so on. The
# older add_harness_suite() here built a second, differently-named image
# against a separately-maintained platform-support library; it was the thing
# that left the kernel on its DEFAULT os-app-config.h (no OS_USE_OS_APP_CONFIG_H
# reached the suite), which is what stopped rtos-apis in malloc_memory_
# resource(). Naming test::<suite> through the builder's own seam is what the
# proven Cortex-M pico2 platform does, and it carries the suite's config with
# it.

# -----------------------------------------------------------------------------
message (
  STATUS
    "AArch32 rpi3b: port tests + harness suites registered (${PLATFORM_NAME})"
)
