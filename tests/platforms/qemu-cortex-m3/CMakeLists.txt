# -----------------------------------------------------------------------------
# Test executables — µOS++ III Cortex-M3 on QEMU (single core).
#
# The harness suites (rtos-apis, mutex-stress, cmsis-os-validator) run on one
# emulated Cortex-M3 via the generic M3 port core, on QEMU's mps2-an385
# machine.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/${PLATFORM_NAME}'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")

# The QEMU binary, from the configuration's xpm .bin (the per-config pin).
unset (_qemu CACHE)
find_program (
  _qemu qemu-system-arm
  HINTS "${CMAKE_BINARY_DIR}/xpacks/.bin"
)
if (NOT _qemu)
  set (_qemu "qemu-system-arm")
endif ()

set (_qemu_machine mps2-an385)
set (_qemu_cpu cortex-m3)

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
add_suite_executable (cmsis-os-validator-test cmsis-os-validator
                      xpacks::arm-cmsis-os-validator)

# -----------------------------------------------------------------------------
message (STATUS "Cortex-M qemu-cortex-m3: harness suites registered (${PLATFORM_NAME})")
