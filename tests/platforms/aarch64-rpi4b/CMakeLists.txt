# -----------------------------------------------------------------------------
# Test executables — µOS++ III AArch64 on the Raspberry Pi 4 B.
#
# BOARD=rpi4b of the AArch64 port: BCM2711, 4x Cortex-A72, GIC-400. The
# board's own sources are test/boards/rpi4b/, its tests test/rpi4b/ (the
# Pi 3 B's tests carried over, without usb_test).
#
#   hwd    runs through the board's own hw.sh (test/boards/rpi4b/hw.sh:
#          OpenOCD + CMSIS-DAP over JTAG). Before each test the board is
#          reset through the PM watchdog and given UOS_HW_RESET_WAIT (15) s
#          to boot, so the hwd cases can run one after another. The port's
#          builder is add_subdirectory()'d into port-tests/test -- the layout
#          that script expects.
#   qemu   raspi4b (QEMU >= 9.0), handed the raw image directly (-kernel):
#          QEMU enters it at EL2 in AArch64 and holds cores 1-3 in the
#          spin-table, like the Pi 4 firmware's armstub8.
#
# The port owns its tests (test/rpi4b/<app>/), and its builder compiles each
# twice -- `qemu` and `hwd`. This platform reuses that builder, so every test
# the port has appears, named `<platform>-<app>-qemu` / `-hwd`.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/${PLATFORM_NAME}'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")

# The port publishes most board facts as CACHE INTERNAL, but not
# UOS_BOARD_DEVICES; read the board declaration so the builder sees it.
include ("${UOS_AARCH64_DIR}/test/boards/${BOARD}/board.cmake")

# -----------------------------------------------------------------------------
# Build every port test (qemu + hwd) by reusing the port's builder.
add_subdirectory ("${UOS_AARCH64_DIR}/test" "port-tests/test")

set (_port_bin "${CMAKE_CURRENT_BINARY_DIR}/port-tests/test")
set (_port_test_dir "${UOS_AARCH64_DIR}/test/rpi4b")
set (_board_hw "${UOS_AARCH64_DIR}/test/boards/${BOARD}/hw.sh")
set (_runner "${CMAKE_SOURCE_DIR}/../test_smpl")

# -----------------------------------------------------------------------------
# The QEMU binary and machine arguments: raspi4b, image handed to -kernel.
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
# One CTest case per (test, variant).
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
    NAME "${PLATFORM_NAME}-${_app}-qemu"
    COMMAND
      bash "${_runner}/run-qemu.sh" "${_port_bin}" "${_qemu}" -M raspi4b -smp 4
  )
  set_tests_properties (
    "${PLATFORM_NAME}-${_app}-qemu"
    PROPERTIES ENVIRONMENT "UOS_QEMU_ONLY=${_app};UOS_TEST_SRC_DIR=${_port_test_dir}" LABELS "qemu" TIMEOUT 2400
  )

  add_test (
    NAME "${PLATFORM_NAME}-${_app}-hwd"
    # 1800 s: the budget counts from OpenOCD's start, and loading an image
    # over the CMSIS-DAP probe alone takes 3-8 minutes (~0.6 KB/s; the
    # images are 100-290 KB). The watchdog reset and boot wait come first.
    COMMAND bash "${_board_hw}" "${_app}" 1800
  )
  set_tests_properties (
    "${PLATFORM_NAME}-${_app}-hwd"
    PROPERTIES ENVIRONMENT "BUILD=${CMAKE_CURRENT_BINARY_DIR}/port-tests"
               LABELS "hwd" TIMEOUT 2400
  )
endforeach ()

# -----------------------------------------------------------------------------
# The harness suites are NOT a special case here.
#
# mutex-stress and rtos-apis are built as board apps by the port's own builder
# above: test/rpi4b/<suite>/ carries the wrapper that prints the RESULT line,
# and test/rpi4b/tests.cmake's board_test_libs() names the harness's
# test::<suite> plus aarch64-rpi4b-harness-suite (the suite's os-app-config.h,
# the startup hooks and --wrap=os_main). The loop
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
message (STATUS "AArch64 rpi4b: port tests + harness suites registered")
