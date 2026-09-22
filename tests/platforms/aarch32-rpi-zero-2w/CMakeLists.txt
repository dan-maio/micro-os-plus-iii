# -----------------------------------------------------------------------------
# Test executables — µOS++ III AArch32 on the Raspberry Pi Zero 2 W.
#
# QEMU: raspi3b + the AArch64->AArch32 boot shim, image loaded at 0x10000.
# A semihosted SYS_EXIT (from the platform's _Exit override) ends the run, so
# CTest gets a real pass/fail with no log parsing.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/aarch32-rpi-zero-2w'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")

# -----------------------------------------------------------------------------
function (add_test_executable name)
  add_executable (${name})

  set_target_properties (${name} PROPERTIES OUTPUT_NAME "${name}")

  # A raw image beside the ELF: the QEMU shim and the SD boot card both
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
# The AArch64 -> AArch32 QEMU boot shim, built with the aarch64 toolchain.
# QEMU's raspi3b starts its Cortex-A53 cores in AArch64; the shim drops to
# AArch32 and jumps to the image loaded at 0x10000.
set (_shim_src "${UOS_AARCH32_DIR}/test/boards/rpi-zero-2w/qemu-raspi3-shim")
set (_shim_img "${CMAKE_CURRENT_BINARY_DIR}/shim8.img")
file (GLOB _a64_bins
      "$ENV{HOME}/.local/xPacks/@xpack-dev-tools/aarch64-none-elf-gcc/*/.content/bin")
if (_a64_bins AND EXISTS "${_shim_src}/shim.S")
  list (SORT _a64_bins COMPARE NATURAL ORDER DESCENDING)
  list (GET _a64_bins 0 _a64_bin)
  add_custom_command (
    OUTPUT "${_shim_img}"
    COMMAND
      "${_a64_bin}/aarch64-none-elf-gcc" -nostdlib
      "-Wl,-T,${_shim_src}/shim.ld" "${_shim_src}/shim.S" -o
      "${CMAKE_CURRENT_BINARY_DIR}/shim.elf"
    COMMAND
      "${_a64_bin}/aarch64-none-elf-objcopy" -O binary
      "${CMAKE_CURRENT_BINARY_DIR}/shim.elf" "${_shim_img}"
    DEPENDS "${_shim_src}/shim.S" "${_shim_src}/shim.ld"
    COMMENT "Building the AArch64->AArch32 QEMU boot shim"
    VERBATIM
  )
  add_custom_target (qemu-shim ALL DEPENDS "${_shim_img}")
else ()
  message (
    STATUS "AArch32: no aarch64 toolchain, QEMU boot shim not built"
  )
endif ()

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
            # Hooks + main() + C library, for the harness suites.
            micro-os-plus::platform-support
  )

  message (VERBOSE "A> mutex-stress-test")

  add_test (
    NAME "${PLATFORM_NAME}-mutex-stress-test"
    COMMAND
      qemu-system-aarch64${extension} --machine raspi3b -smp 4 --nographic
      --serial none --semihosting-config enable=on,target=native --kernel
      "${_shim_img}" --device
      "loader,file=$<TARGET_FILE:mutex-stress-test>.bin,addr=0x10000"
  )
  set_tests_properties ("${PLATFORM_NAME}-mutex-stress-test" PROPERTIES TIMEOUT
                                                                            120)
endif ()

# -----------------------------------------------------------------------------
# Port test: the AArch32 port's own smp-pipeline-test.
#
# Unlike the harness suites, this test ships its own strong main() and startup
# hooks (in the port's test/rpi-zero-2w/smp-pipeline-test/main.cpp), which
# override the platform's weak ones. It links the devices package (SD/FatFs)
# and, under QEMU (!HW_BUILD), formats a blank SD image with flatfs, so the
# run needs an SD drive.
option (ENABLE_SMP_PIPELINE_TEST "Build the port's smp-pipeline-test" ON)

if (ENABLE_SMP_PIPELINE_TEST)
  set (_port_test_dir "${UOS_AARCH32_DIR}/test/rpi-zero-2w")

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
            # The port test reaches the SD card / FatFs.
            micro-os-plus::devices
  )

  message (VERBOSE "A> smp-pipeline-test")

  # A blank SD image the test formats with flatfs under QEMU.
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
      "file=${_pipe_disk},if=sd,format=raw" --kernel "${_shim_img}" --device
      "loader,file=$<TARGET_FILE:smp-pipeline-test>.bin,addr=0x10000"
  )
  set_tests_properties ("${PLATFORM_NAME}-smp-pipeline-test" PROPERTIES
                        TIMEOUT 1200)
endif ()

# -----------------------------------------------------------------------------
# Port test: the AArch32 port's own smp-pro-cons-test. It does not touch the
# SD card, so no devices and no disk image.
option (ENABLE_SMP_PRO_CONS_TEST "Build the port's smp-pro-cons-test" ON)

if (ENABLE_SMP_PRO_CONS_TEST)
  set (_port_test_dir "${UOS_AARCH32_DIR}/test/rpi-zero-2w")

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
      "${_shim_img}" --device
      "loader,file=$<TARGET_FILE:smp-pro-cons-test>.bin,addr=0x10000"
  )
  set_tests_properties ("${PLATFORM_NAME}-smp-pro-cons-test" PROPERTIES
                        TIMEOUT 1200)
endif ()

# -----------------------------------------------------------------------------
