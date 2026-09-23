# -----------------------------------------------------------------------------
# Test executables — µOS++ III AArch64 on the Raspberry Pi Zero 2 W.
#
# QEMU: raspi3b, handed the raw image directly (-kernel): QEMU starts its
# Cortex-A53 cores in AArch64, which is the state this port runs in, so there
# is no boot shim.
#
# The port owns its tests (test/rpi-zero-2w/<app>/), and its builder compiles
# each twice -- `qemu` and `hwd`. This platform reuses that builder, so every
# test the port has appears, named `<platform>-<app>-qemu` / `-hwd`.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/${PLATFORM_NAME}'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")

# The port publishes most board facts as CACHE INTERNAL, but not
# UOS_BOARD_DEVICES; read the board declaration so the builder sees it.
include ("${UOS_AARCH64_DIR}/test/boards/${BOARD}/board.cmake")

# -----------------------------------------------------------------------------
# Build every port test (qemu + hwd) by reusing the port's builder.
add_subdirectory ("${UOS_AARCH64_DIR}/test" "port-tests")

set (_port_bin "${CMAKE_CURRENT_BINARY_DIR}/port-tests")
set (_port_test_dir "${UOS_AARCH64_DIR}/test/rpi-zero-2w")
set (_runner "${CMAKE_SOURCE_DIR}/../test_smpl")

# -----------------------------------------------------------------------------
# The QEMU binary and machine arguments: raspi3b, image handed to -kernel.
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
      bash "${_runner}/run-qemu.sh" "${_port_bin}" "${_qemu}" -M raspi3b -smp 4
  )
  set_tests_properties (
    "${PLATFORM_NAME}-${_app}-qemu"
    PROPERTIES ENVIRONMENT "UOS_QEMU_ONLY=${_app}" LABELS "qemu" TIMEOUT 2400
  )

  add_test (
    NAME "${PLATFORM_NAME}-${_app}-hwd"
    COMMAND bash "${_runner}/run-hw.sh" "${_port_bin}" "${_app}" 600
  )
  set_tests_properties (
    "${PLATFORM_NAME}-${_app}-hwd"
    PROPERTIES ENVIRONMENT "BUILD=${_port_bin}" LABELS "hwd" TIMEOUT 1200
  )
endforeach ()

# -----------------------------------------------------------------------------
# The harness suites. They supply no main()/hooks, so they link
# micro-os-plus::platform-support; they end through the strong _Exit()
# (SYS_EXIT), so QEMU returns an exit code and there is no RESULT line.
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
  add_test (
    NAME "${PLATFORM_NAME}-${_name}-qemu"
    COMMAND
      "${_qemu}" --machine raspi3b -smp 4 --nographic --serial none
      --semihosting-config enable=on,target=native --kernel
      "$<TARGET_FILE:${_name}>.bin"
  )
  set_tests_properties ("${PLATFORM_NAME}-${_name}-qemu" PROPERTIES LABELS
                                                                  "qemu" TIMEOUT 300)
endfunction ()

# The harness suite needs the AArch64 platform-support's strong _Exit() to
# resolve its semihosting group.
add_harness_suite (mutex-stress mutex-stress-test)
# rtos-apis brings its own os_main() and the newlib/posix-io + Chan FatFs
# dependencies its POSIX and FatFs sub-tests need.
add_harness_suite (rtos-apis rtos-apis-test
                   LIBRARIES xpacks::chan-fatfs micro-os-plus::iii-posix-io)

# -----------------------------------------------------------------------------
message (STATUS "AArch64 rpi-zero-2w: port tests + harness suites registered")
