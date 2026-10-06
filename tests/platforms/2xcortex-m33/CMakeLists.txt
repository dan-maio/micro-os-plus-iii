# -----------------------------------------------------------------------------
# Test executables — µOS++ III Cortex-M33 SMP on QEMU mps2-an521 (2 cores).
#
# The harness suites run on two emulated Cortex-M33 cores; the generic M33 port
# releases core 1 itself and drives the cross-core IPI over the SSE-200 MHU.
# The RP2350 board tests are NOT built here: the hardware tests stay in
# `cortexm-pico2`.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/${PLATFORM_NAME}'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")

file (GLOB _qemu_bins
      "$ENV{HOME}/.local/xPacks/@xpack-dev-tools/qemu-arm/*/.content/bin")
if (_qemu_bins)
  list (SORT _qemu_bins COMPARE NATURAL ORDER DESCENDING)
  list (GET _qemu_bins 0 _qemu_bin)
  set (_qemu "${_qemu_bin}/qemu-system-arm")
else ()
  set (_qemu "qemu-system-arm")
endif ()

set (_qemu_machine mps2-an521)
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
      "${_qemu}" --machine ${_qemu_machine} --cpu ${_qemu_cpu} --smp 2
      # QEMU's SSE-200 leaves CPU0's FPU/DSP off by default (unlike the
      # IoTKit of mps2-an505); enable both on BOTH CPUs, so a hard-float
      # image runs whichever core a migrated FP thread lands on.
      --global sse-200.CPU0_FPU=on --global sse-200.CPU0_DSP=on
      --global sse-200.CPU1_FPU=on --global sse-200.CPU1_DSP=on --kernel
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
message (STATUS "Cortex-M 2xcortex-m33: harness suites registered (${PLATFORM_NAME})")
