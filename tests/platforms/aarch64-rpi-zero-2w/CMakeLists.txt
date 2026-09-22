# -----------------------------------------------------------------------------
# Test executables — µOS++ III AArch64 on the Raspberry Pi Zero 2 W.
#
# QEMU: raspi3b, handed the raw image directly. QEMU starts its Cortex-A53
# cores in AArch64, which is the state this port runs in, so there is no boot
# shim. A semihosted SYS_EXIT (from the platform's strong _Exit override) ends
# the run, so CTest gets a real pass/fail with no log parsing.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/aarch64-rpi-zero-2w'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")

# -----------------------------------------------------------------------------
function (add_test_executable name)
  add_executable (${name})

  set_target_properties (${name} PROPERTIES OUTPUT_NAME "${name}")

  # A raw image beside the ELF: QEMU's -kernel and the SD boot card both
  # consume a .bin, not an ELF. Also print the size listing.
  add_custom_command (
    TARGET ${name}
    POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O binary "$<TARGET_FILE:${name}>"
            "$<TARGET_FILE:${name}>.bin"
    COMMAND ${CMAKE_SIZE} --format=berkeley "$<TARGET_FILE:${name}>"
    VERBATIM
  )
endfunction ()

# -----------------------------------------------------------------------------
if (ENABLE_MUTEX_STRESS_TEST)
  add_test_executable (mutex-stress-test)

  target_link_libraries (
    mutex-stress-test
    PRIVATE micro-os-plus::common-options
            # Current test library.
            test::mutex-stress
            # Tested library (the SMP kernel, via the port).
            micro-os-plus::iii
            # Platform specific dependencies.
            micro-os-plus::platform
            # Hooks + main() + strong _Exit(), for the harness suites.
            micro-os-plus::platform-support
  )

  message (VERBOSE "A> mutex-stress-test")

  add_test (
    NAME "${PLATFORM_NAME}-mutex-stress-test"
    COMMAND
      qemu-system-aarch64${extension} --machine raspi3b -smp 4 --nographic
      --serial none --semihosting-config enable=on,target=native --kernel
      "$<TARGET_FILE:mutex-stress-test>.bin"
  )
  set_tests_properties ("${PLATFORM_NAME}-mutex-stress-test" PROPERTIES TIMEOUT
                                                                            120)
endif ()

# -----------------------------------------------------------------------------
# Port test: the AArch64 port's own smp-pipeline-test (see the AArch32 platform
# for the rationale). It ships its own strong main()/hooks, links the devices
# package, and formats a blank SD image with flatfs under QEMU. No boot shim:
# QEMU raspi3b takes the AArch64 image directly.
option (ENABLE_SMP_PIPELINE_TEST "Build the port's smp-pipeline-test" ON)

if (ENABLE_SMP_PIPELINE_TEST)
  set (_port_test_dir "${UOS_AARCH64_DIR}/test/rpi-zero-2w")

  add_executable (
    smp-pipeline-test
    "${_port_test_dir}/smp-pipeline-test/main.cpp"
    "${_port_test_dir}/src/test-smp-boot.cpp"
  )
  target_include_directories (smp-pipeline-test PRIVATE
                              "${_port_test_dir}/include")
  set_target_properties (smp-pipeline-test PROPERTIES OUTPUT_NAME
                                                        "smp-pipeline-test")

  add_custom_command (
    TARGET smp-pipeline-test
    POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O binary "$<TARGET_FILE:smp-pipeline-test>"
            "$<TARGET_FILE:smp-pipeline-test>.bin"
    COMMAND ${CMAKE_SIZE} --format=berkeley "$<TARGET_FILE:smp-pipeline-test>"
    VERBATIM
  )

  target_link_libraries (
    smp-pipeline-test
    PRIVATE micro-os-plus::common-options
            micro-os-plus::iii
            micro-os-plus::platform
            micro-os-plus::devices
  )

  message (VERBOSE "A> smp-pipeline-test")

  set (_pipe_disk "${CMAKE_CURRENT_BINARY_DIR}/smp-pipeline-test.disk.img")
  add_custom_command (
    OUTPUT "${_pipe_disk}"
    COMMAND truncate -s 4G "${_pipe_disk}"
    VERBATIM
  )
  add_custom_target (smp-pipeline-test-disk ALL DEPENDS "${_pipe_disk}")

  add_test (
    NAME "${PLATFORM_NAME}-smp-pipeline-test"
    COMMAND
      qemu-system-aarch64${extension} --machine raspi3b -smp 4 --nographic
      --serial none --semihosting-config enable=on,target=native --drive
      "file=${_pipe_disk},if=sd,format=raw" --kernel
      "$<TARGET_FILE:smp-pipeline-test>.bin"
  )
  set_tests_properties ("${PLATFORM_NAME}-smp-pipeline-test" PROPERTIES
                        TIMEOUT 1200)
endif ()

# -----------------------------------------------------------------------------
# Port test: the AArch64 port's own smp-pro-cons-test. No SD, so no devices
# and no disk image. QEMU raspi3b takes the AArch64 image directly.
option (ENABLE_SMP_PRO_CONS_TEST "Build the port's smp-pro-cons-test" ON)

if (ENABLE_SMP_PRO_CONS_TEST)
  set (_port_test_dir "${UOS_AARCH64_DIR}/test/rpi-zero-2w")

  add_executable (
    smp-pro-cons-test
    "${_port_test_dir}/smp-pro-cons-test/main.cpp"
    "${_port_test_dir}/src/test-smp-boot.cpp"
  )
  target_include_directories (smp-pro-cons-test PRIVATE
                              "${_port_test_dir}/include")
  set_target_properties (smp-pro-cons-test PROPERTIES OUTPUT_NAME
                                                        "smp-pro-cons-test")

  add_custom_command (
    TARGET smp-pro-cons-test
    POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O binary "$<TARGET_FILE:smp-pro-cons-test>"
            "$<TARGET_FILE:smp-pro-cons-test>.bin"
    COMMAND ${CMAKE_SIZE} --format=berkeley "$<TARGET_FILE:smp-pro-cons-test>"
    VERBATIM
  )

  target_link_libraries (
    smp-pro-cons-test
    PRIVATE micro-os-plus::common-options
            micro-os-plus::iii
            micro-os-plus::platform
  )

  message (VERBOSE "A> smp-pro-cons-test")

  add_test (
    NAME "${PLATFORM_NAME}-smp-pro-cons-test"
    COMMAND
      qemu-system-aarch64${extension} --machine raspi3b -smp 4 --nographic
      --serial none --semihosting-config enable=on,target=native --kernel
      "$<TARGET_FILE:smp-pro-cons-test>.bin"
  )
  set_tests_properties ("${PLATFORM_NAME}-smp-pro-cons-test" PROPERTIES
                        TIMEOUT 1200)
endif ()

# -----------------------------------------------------------------------------
