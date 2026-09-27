# -----------------------------------------------------------------------------
# Test executables — µOS++ III Cortex-M33 on QEMU mps2-an505 (single core).
#
# The harness suites (rtos-apis, mutex-stress, cmsis-os-validator) are run on
# one emulated Cortex-M33 via the generic M33 port core. The RP2350 board
# tests are NOT built here: the hardware tests stay in `cortexm-pico2`.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/${PLATFORM_NAME}'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")

# The QEMU binary, from the newest installed qemu-arm xpack (same discovery as
# the cortexm-pico2 platform); it is used as an absolute path in add_test, so
# PATH does not matter.
file (GLOB _qemu_bins
      "$ENV{HOME}/.local/xPacks/@xpack-dev-tools/qemu-arm/*/.content/bin")
if (_qemu_bins)
  list (SORT _qemu_bins COMPARE NATURAL ORDER DESCENDING)
  list (GET _qemu_bins 0 _qemu_bin)
  set (_qemu "${_qemu_bin}/qemu-system-arm")
else ()
  set (_qemu "qemu-system-arm")
endif ()

set (_qemu_machine mps2-an505)
set (_qemu_cpu cortex-m33)

# -----------------------------------------------------------------------------
function (add_suite_executable name suite)
  add_executable (${name})
  target_link_libraries (
    ${name}
    PRIVATE micro-os-plus::common-options test::${suite} micro-os-plus::iii
            micro-os-plus::platform ${ARGN}
  )
  set_target_properties (${name} PROPERTIES OUTPUT_NAME "${name}")
  add_test (
    NAME "${PLATFORM_NAME}-${name}"
    COMMAND
      "${_qemu}" --machine ${_qemu_machine} --cpu ${_qemu_cpu} --kernel
      "$<TARGET_FILE:${name}>" --nographic -d unimp,guest_errors
      --semihosting-config enable=on,target=native
  )
  set_tests_properties ("${PLATFORM_NAME}-${name}" PROPERTIES LABELS "qemu" TIMEOUT 1200)
endfunction ()

# -----------------------------------------------------------------------------
add_suite_executable (rtos-apis-test rtos-apis xpacks::chan-fatfs)
add_suite_executable (mutex-stress-test mutex-stress)
add_suite_executable (fp-switch-test fp-switch)
add_suite_executable (cmsis-os-validator-test cmsis-os-validator
                      xpacks::arm-cmsis-os-validator)

# -----------------------------------------------------------------------------
message (STATUS "Cortex-M pico2-1cpu: harness suites registered (${PLATFORM_NAME})")
