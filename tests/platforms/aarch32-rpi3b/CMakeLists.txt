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
# The harness suites, on the same platform. They supply no main() and no
# startup hooks, so they link micro-os-plus::platform-support.
function (add_harness_suite _suite _name)
  cmake_parse_arguments (T "" "" "LIBRARIES" ${ARGN})
  add_executable (${_name})
  target_link_libraries (
    ${_name}
    PRIVATE micro-os-plus::common-options test::${_suite} micro-os-plus::iii
            micro-os-plus::platform micro-os-plus::platform-support
            ${T_LIBRARIES}
  )
  set_target_properties (${_name} PROPERTIES OUTPUT_NAME "${_name}" SUFFIX "")
  add_custom_command (
    TARGET ${_name}
    POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O binary "$<TARGET_FILE:${_name}>"
            "$<TARGET_FILE:${_name}>.bin"
    VERBATIM
  )
  # A harness suite ends through the platform's strong _Exit() (SYS_EXIT), so
  # QEMU returns a real exit code -- no RESULT line to grep.
  add_test (
    NAME "${PLATFORM_NAME}-${_name}-qemu"
    COMMAND
      "${_qemu}" --machine raspi3b -smp 4 --nographic --serial none
      --semihosting-config enable=on,target=native --kernel "${_shim_img}"
      --device
      "loader,file=$<TARGET_FILE:${_name}>.bin,addr=0x10000"
  )
  set_tests_properties ("${PLATFORM_NAME}-${_name}-qemu" PROPERTIES LABELS
                                                                  "qemu" TIMEOUT 300)
endfunction ()

# Every harness suite this platform pulls in (see dependencies-folders.cmake).
add_harness_suite (mutex-stress mutex-stress-test)
add_harness_suite (rtos-apis rtos-apis-test
                   LIBRARIES xpacks::chan-fatfs micro-os-plus::iii-posix-io)
# rtos-apis and cmsis-os-validator are NOT built here yet:
#   * rtos-apis builds, but aborts in first_fit_top::internal_align_ on the
#     AArch32 harness. The cause is a heap overlap this platform cannot fix
#     from CMake: the µOS++ app-heap (first_fit_top over [__heap_start,
#     __heap_end]) and newlib's _sbrk region ([_Heap_Begin, _Heap_Limit]) are
#     the SAME bytes -- the linker sets both to the .heap section -- so `new`
#     and ::malloc hand out the same memory. mutex-stress' small footprint
#     never collides; rtos-apis' FatFs/posix-io tests do. It needs a port
#     linker-script change (separate _Heap_Limit) or kernel work.
#   * cmsis-os-validator is Cortex-M only: its RV_Signal.c/RV_Thread.c call the
#     NVIC API (NVIC_EnableIRQ, IRQn_Type), which does not exist on AArch32.

# -----------------------------------------------------------------------------
message (
  STATUS
    "AArch32 rpi3b: port tests + harness suites registered (${PLATFORM_NAME})"
)
