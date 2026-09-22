# -----------------------------------------------------------------------------
# Test executables — µOS++ III AArch32 on the Luckfox Lyra B (RK3506).
#
# HARDWARE ONLY. QEMU models none of the RK3506's own blocks, so there is no
# emulated suite here: each test is built for the board (`hwd`) and run through
# the port's own test/boards/luckfox-lyra/hw.sh, which drives OpenOCD.
#
# CTest does not compare a process exit code -- OpenOCD is a debugger, not a
# parent. The verdict is the "RESULT: PASS|FAIL" line the test prints on the
# semihosting channel, which run-hw.sh greps out of the OpenOCD log, exactly as
# it does for the port's other hardware tests.
#
# Registering the runs needs the board attached and one power cycle per test,
# so it is opt-in: -DENABLE_HW_TESTS=ON. Without it the images are still built
# (a normal `xpm run build`), and you can run one by hand:
#
#   test/boards/luckfox-lyra/hw.sh smp_test4
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/aarch32-luckfox-lyra'...")

include ("cmake/platform-library.cmake")

# -----------------------------------------------------------------------------
option (ENABLE_HW_TESTS
        "Register the hardware board tests with CTest (needs the board)" OFF)

set (_port_test_dir "${UOS_AARCH32_DIR}/test/luckfox-lyra")
set (_board_dir "${UOS_BOARD_SRC_DIR}") # .../test/boards/luckfox-lyra
set (_port_hw "${UOS_AARCH32_DIR}/test/boards/luckfox-lyra/hw.sh")

# -----------------------------------------------------------------------------
# One hardware test. This is what the port's own test/CMakeLists.txt would set
# for an `hwd` application, so the board test builds exactly as it does there:
#
#   * output name <app>-hwd and runtime dir <binary>/test, because hw.sh runs
#     `run-hw.sh "$BUILD/test" <app>` and looks the image up as <app>-hwd with
#     no extension (the port's own build names it that way);
#   * the port's application flags. common-options is deliberately NOT linked:
#     it defines OS_USE_OS_APP_CONFIG_H, which the port's tests do not use and
#     which would make the kernel look for an os-app-config.h that is not there;
#   * the base platform only. The tests bring their own strong main() and
#     startup hooks; the platform-support library (a second strong main()) is
#     for the harness suite below, and the board tests do not link it.
#
#   add_hw_test (<app> SOURCES <files...> [INCLUDES <dirs...>]
#                      [LIBRARIES <libs...>])
function (add_hw_test _app)
  cmake_parse_arguments (T "" "SECONDS" "SOURCES;INCLUDES;LIBRARIES" ${ARGN})

  add_executable (${_app} ${T_SOURCES})
  target_include_directories (${_app} PRIVATE ${T_INCLUDES})
  set_target_properties (${_app} PROPERTIES OUTPUT_NAME "${_app}-hwd")

  target_compile_options (
    ${_app}
    PRIVATE -O2 -g3 -fmessage-length=0 -fsigned-char
            -ffunction-sections -fdata-sections
            $<$<COMPILE_LANGUAGE:C>:-std=gnu11>
            $<$<COMPILE_LANGUAGE:CXX>:-std=c++20>
            $<$<COMPILE_LANGUAGE:CXX>:-fabi-version=0>
            $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions>
            $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti>
  )
  target_link_options (
    ${_app} PRIVATE -nostartfiles -Wl,--gc-sections
                    "-Wl,-Map,$<TARGET_FILE_DIR:${_app}>/${_app}.map"
  )
  target_link_libraries (
    ${_app} PRIVATE micro-os-plus::iii micro-os-plus::platform ${T_LIBRARIES}
  )

  add_custom_command (
    TARGET ${_app}
    POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O binary "$<TARGET_FILE:${_app}>"
            "$<TARGET_FILE:${_app}>.bin"
    COMMAND ${CMAKE_SIZE} "$<TARGET_FILE:${_app}>"
    VERBATIM
  )

  # tests-main.cmake sets CMAKE_EXECUTABLE_SUFFIX=.elf for Generic systems, but
  # run-hw.sh looks the image up as <app>-hwd with no extension, so clear it.
  set_target_properties (
    ${_app} PROPERTIES RUNTIME_OUTPUT_DIRECTORY
                       "${CMAKE_CURRENT_BINARY_DIR}/test" SUFFIX ""
  )

  if (ENABLE_HW_TESTS)
    # Run budget, in seconds, passed to run-hw.sh. A test that needs longer
    # than the default says so with SECONDS: the SD solver, for example, runs
    # for many minutes on hardware.
    set (_secs "${T_SECONDS}")
    if (_secs STREQUAL "")
      set (_secs 600)
    endif ()
    add_test (
      NAME "${PLATFORM_NAME}-${_app}"
      COMMAND bash "${_port_hw}" ${_app} ${_secs}
    )
    # CTest must not kill the run before the runner's own budget expires; give
    # it the budget plus a margin for OpenOCD start/stop.
    math (EXPR _timeout "${_secs} + 600")
    set_tests_properties (
      "${PLATFORM_NAME}-${_app}"
      PROPERTIES ENVIRONMENT "BUILD=${CMAKE_CURRENT_BINARY_DIR}"
                 TIMEOUT ${_timeout} LABELS hw
    )
  endif ()
endfunction ()

# -----------------------------------------------------------------------------
# smp_test4 — no-affinity load balancing across the three A7 cores.
#
# Uses the board's shared test/luckfox-lyra/src/test-smp-boot.cpp for the
# secondary idle threads; no devices. It ends with hw_result::ok()/fail(),
# which on a SEMIHOST build prints "RESULT: PASS|FAIL" and stops via SYS_EXIT.
add_hw_test (
  smp_test4
  SOURCES "${_port_test_dir}/smp_test4/main.cpp"
          "${_port_test_dir}/src/test-smp-boot.cpp"
  INCLUDES "${_port_test_dir}/include" "${_port_test_dir}/smp_test4"
)

# -----------------------------------------------------------------------------
# smp-mat-sdcard-test — parallel block linear solver with the matrices stored on
# the SD card.
#
# Uses the board's shared test-smp-boot.cpp for the secondary idle threads, and
# the devices package (flatfs / FatFs over the RK3506 SD host). On hardware it
# mounts the EXISTING FAT32 partition -- it does not format it. Ends with
# hw_result::ok()/fail().
add_hw_test (
  smp-mat-sdcard-test
  SOURCES "${_port_test_dir}/smp-mat-sdcard-test/main.cpp"
          "${_port_test_dir}/src/test-smp-boot.cpp"
  INCLUDES "${_port_test_dir}/include" "${_port_test_dir}/smp-mat-sdcard-test"
  LIBRARIES micro-os-plus::devices-rk3506
  # The SD solver writes/reads ~1 MB matrices and solves a 200x200 system with
  # per-iteration output; on hardware it runs for many minutes.
  SECONDS 1800
)

# -----------------------------------------------------------------------------
# smp_test5 — SD card + LED + logger on the three A7 cores.
#
# Self-contained (its own main(), startup hooks and smp_install_boot_threads()),
# so it does NOT take src/test-smp-boot.cpp. It drives the SD card through the
# board's C++ FatFs (namespace fatfs) and the RK3506 SD host
# (micro-os-plus::devices-rk3506). The port caches UOS_BOARD_SRC_DIR but not the
# FatFs source lists, so the paths are named here, from the board's fatfs-cpp/.
set (_fatfs_dir "${_board_dir}/fatfs-cpp")
add_hw_test (
  smp_test5
  SOURCES "${_port_test_dir}/smp_test5/main.cpp"
          "${_fatfs_dir}/ff.cpp"
          "${_fatfs_dir}/ffsystem.cpp"
          "${_fatfs_dir}/ffunicode.cpp"
          "${_fatfs_dir}/diskio_sdmmc.cpp"
  INCLUDES "${_fatfs_dir}" "${_port_test_dir}/smp_test5"
           "${_port_test_dir}/include"
  LIBRARIES micro-os-plus::devices-rk3506
  SECONDS 900
)

# -----------------------------------------------------------------------------
# Harness suite: the portable mutex-stress test, on the Lyra.
#
# Unlike the port's board tests, this is a HARNESS suite: it supplies no main()
# and no startup hooks, so it links micro-os-plus::platform-support (the
# hardware variant in src/platform-support.cpp) and micro-os-plus::common-options.
# The support trampoline prints "RESULT: PASS|FAIL" before it exits, so the
# runner gets a verdict without the suite knowing anything about OpenOCD.
option (ENABLE_MUTEX_STRESS_TEST "Build the mutex-stress harness suite" ON)

if (ENABLE_MUTEX_STRESS_TEST)
  add_executable (mutex-stress-test)
  target_link_libraries (
    mutex-stress-test
    PRIVATE micro-os-plus::common-options
            test::mutex-stress
            micro-os-plus::iii
            micro-os-plus::platform
            micro-os-plus::platform-support
  )
  set_target_properties (
    mutex-stress-test
    PROPERTIES OUTPUT_NAME "mutex-stress-test-hwd" RUNTIME_OUTPUT_DIRECTORY
               "${CMAKE_CURRENT_BINARY_DIR}/test" SUFFIX ""
  )
  add_custom_command (
    TARGET mutex-stress-test
    POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O binary "$<TARGET_FILE:mutex-stress-test>"
            "$<TARGET_FILE:mutex-stress-test>.bin"
    COMMAND ${CMAKE_SIZE} "$<TARGET_FILE:mutex-stress-test>"
    VERBATIM
  )
  if (ENABLE_HW_TESTS)
    add_test (
      NAME "${PLATFORM_NAME}-mutex-stress-test"
      COMMAND bash "${_port_hw}" mutex-stress-test 600
    )
    set_tests_properties (
      "${PLATFORM_NAME}-mutex-stress-test"
      PROPERTIES ENVIRONMENT "BUILD=${CMAKE_CURRENT_BINARY_DIR}" TIMEOUT 1200
                 LABELS hw
    )
  endif ()
endif ()

# -----------------------------------------------------------------------------
if (ENABLE_HW_TESTS)
  message (STATUS "AArch32 Lyra: hardware tests registered (ENABLE_HW_TESTS=ON)")
else ()
  message (
    STATUS
      "AArch32 Lyra: board tests + mutex-stress built; run registration off "
      "(configure with -DENABLE_HW_TESTS=ON to add them to CTest)"
  )
endif ()

# -----------------------------------------------------------------------------
