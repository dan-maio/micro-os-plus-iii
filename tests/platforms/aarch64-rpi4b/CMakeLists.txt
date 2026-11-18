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
include ("${CMAKE_SOURCE_DIR}/cmake/uos-tests-run.cmake")

# The board facts and micro-os-plus::board come from cmake/platform-library.cmake
# (cmake/board.cmake); the port's builder below reads them.

# -----------------------------------------------------------------------------
# Build every port test (qemu + hwd) by reusing the port's builder.
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
# Of those, the ones that use the SD card: the card as the posix-io block
# device /dev/sd, under the Chan FatFs file system.
set (UOS_TESTS_STORAGE sd_test smp-mat-sdcard-test smp-num-test
     smp-pipeline-test)
set (UOS_TESTS_PORT aarch64)
set (UOS_TESTS_BOARD_DIR "${UOS_AARCH64_DIR}/test/${BOARD}")
add_subdirectory ("${CMAKE_SOURCE_DIR}/board-tests" "port-tests/test")

set (_port_bin "${CMAKE_CURRENT_BINARY_DIR}/port-tests/test")
set (_board_hw "${UOS_AARCH64_DIR}/test/boards/${BOARD}/hw.sh")

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
# One CTest case per test the builder built (board-tests/: UOS_TESTS_APPS).
foreach (_app IN LISTS UOS_TESTS_APPS)

  uos_tests_add_qemu (
    NAME "${PLATFORM_NAME}-${_app}-qemu" APP "${_app}"
    IMAGE "${_port_bin}/${_app}-qemu.bin"
    QEMU "${_qemu}" MACHINE -M raspi4b -smp 4
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
    PROPERTIES ENVIRONMENT "BUILD=${CMAKE_CURRENT_BINARY_DIR}/port-tests;UOS_SMP_DIR=${CMAKE_SOURCE_DIR}/.."
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
