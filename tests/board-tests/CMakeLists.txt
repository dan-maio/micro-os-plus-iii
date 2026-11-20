# -----------------------------------------------------------------------------
# The board tests' builder, one for every port. It was the ports' own
# test/CMakeLists.txt (one per port, nearly identical); upstream keeps every
# test in this tests/ folder, so the builder is here.
#
# A platform adds it, after its board facts (cmake/board.cmake) and
# micro-os-plus::board exist, with:
#
#   set (UOS_TESTS_PORT     aarch32 | aarch64 | cortexm | posix)
#   set (UOS_TESTS_BOARD_DIR <the board's test folder: tests.cmake, src/,
#                             include/ and one folder per board-only test>)
#   set (UOS_TESTS_SOURCES  <the portable tests this board runs, from
#                             tests/sources/<test>/>)
#   set (UOS_TESTS_PORTABLE <those of them that are os_main() only: they get
#                             the platform's start-up, src/platform-support.cpp,
#                             and the common end, portable-test-end.cpp>)
#   set (UOS_TESTS_SUITES   <upstream's test suites this board runs, from
#                             tests/sources/<suite>/ (mutex-stress, rtos-apis,
#                             cmsis-os-validator): each is its test::<suite>
#                             library, which has its own os_main(), with the
#                             platform's start-up as a portable test, its
#                             upstream dependencies, and the platform's
#                             src/<suite>-support.cpp when there is one>)
#   set (UOS_TESTS_STARTUP_DEFINES <what the platform's start-up and the
#                             board's console need defined for its portable
#                             tests, e.g. UOS_CONSOLE_UART_ONLY>)
#   set (UOS_TESTS_STARTUP_LIBS <what the platform's start-up needs, e.g. the
#                             kernel's C-library groups on AArch32>)
#   set (UOS_TESTS_STORAGE  <the tests that use the SD card: they get the card
#                             as the posix-io block device /dev/sd (the
#                             board's UOS_BOARD_SD_POSIX), the
#                             @xpacks/chan-fatfs file system, and
#                             portable-test-storage.cpp, which mounts it at
#                             /sd/. A portable test gets the mount before
#                             os_main(); a board test (its tests.cmake adds
#                             it to the list) calls uos_test_storage_start()
#                             itself, from uos-test-storage.h>)
#   add_subdirectory ("${CMAKE_SOURCE_DIR}/board-tests" "port-tests/test")
#
# It hands back UOS_TESTS_APPS, the tests it built, for the platform to
# register with CTest.
#
# Each test folder becomes one image per variant: `qemu` and `hwd` when the
# board has a QEMU linker script, `hwd` only when it has not, `host` on the
# POSIX port. The board's tests.cmake turns the knobs below (defines, sources,
# includes, linker, options, CPU count, libraries, and the qemu replacements).
# -----------------------------------------------------------------------------

option (UOS_DEBUG_BOOT "Compile the hwd builds with the early-boot markers" OFF)

if (UOS_TESTS_PORT STREQUAL "aarch64")
  set (SEMI_PRINTS 0 CACHE STRING "hwd builds: mirror all console output to semihosting (0/1)")
  set_property (CACHE SEMI_PRINTS PROPERTY STRINGS 0 1)
endif ()

set (_boards_dir "${UOS_BOARD_SRC_DIR}")
set (_test_dir   "${UOS_TESTS_BOARD_DIR}")

if (NOT IS_DIRECTORY "${_test_dir}")
  message (FATAL_ERROR "The board's test folder ${_test_dir} does not exist.")
endif ()

# The port: its library, the tests' common defines, the variants.
if (UOS_TESTS_PORT STREQUAL "aarch32")
  set (_port_lib micro-os-plus::aarch32)
  set (_common_defines TRACE __ARM_EABI__ __ARM_ARCH_7A__ SEMIHOST)
elseif (UOS_TESTS_PORT STREQUAL "aarch64")
  set (_port_lib micro-os-plus::aarch64)
  set (_common_defines TRACE __ARM_EABI__ __ARM_ARCH_8A__ SEMIHOST)
elseif (UOS_TESTS_PORT STREQUAL "cortexm")
  set (_port_lib ${UOS_PORT_LIB})
  set (_common_defines TRACE SEMIHOST)
elseif (UOS_TESTS_PORT STREQUAL "posix")
  set (_port_lib micro-os-plus::posix-arch)
  set (_common_defines TRACE OS_USE_TRACE_POSIX_STDOUT)
else ()
  message (FATAL_ERROR "UOS_TESTS_PORT=${UOS_TESTS_PORT}: not a port.")
endif ()

if (UOS_TESTS_PORT STREQUAL "posix")
  set (_variants host)
else ()
  set (_linker_hwd  "${UOS_BOARD_LINKER_HW}")
  set (_linker_qemu "${UOS_BOARD_LINKER_QEMU}")
  if (_linker_qemu)
    set (_variants qemu hwd)
  else ()
    set (_variants hwd)
  endif ()
endif ()

# The knobs, with their defaults; the board's tests.cmake overrides them.
set (BOARD_TEST_SELF_CONTAINED "")
set (BOARD_TEST_NO_KERNEL "")
set (BOARD_TEST_HWD_ONLY "")
function (board_test_defines _app _out)
  set (${_out} "" PARENT_SCOPE)
endfunction ()
function (board_test_sources _app _out)
  set (${_out} "" PARENT_SCOPE)
endfunction ()
function (board_test_includes _app _out)
  set (${_out} "" PARENT_SCOPE)
endfunction ()
function (board_test_linker _app _out)
  set (${_out} "" PARENT_SCOPE)
endfunction ()
function (board_test_options _app _out)
  set (${_out} "" PARENT_SCOPE)
endfunction ()
function (board_test_ncpu _app _out)
  set (${_out} "${UOS_BOARD_NCPU}" PARENT_SCOPE)
endfunction ()
function (board_test_qemu_libs _app _out)
  set (${_out} "" PARENT_SCOPE)
endfunction ()
function (board_test_qemu_sources _app _out)
  set (${_out} "" PARENT_SCOPE)
endfunction ()
function (board_test_qemu_includes _app _out)
  set (${_out} "" PARENT_SCOPE)
endfunction ()
function (board_test_libs _app _out)
  set (${_out} "" PARENT_SCOPE)
endfunction ()
# The SD driver set of a storage test (UOS_TESTS_STORAGE): the board's, unless
# the test reaches the card through another controller -- or OWN, when the test
# drives the card with its own driver and defines uos_test_storage_card().
function (board_test_sd_posix _app _out)
  set (${_out} "${UOS_BOARD_SD_POSIX}" PARENT_SCOPE)
endfunction ()
# The POSIX port's name for the same knob.
function (board_test_libraries _app _out)
  set (${_out} "" PARENT_SCOPE)
endfunction ()

if (EXISTS "${_test_dir}/tests.cmake")
  include ("${_test_dir}/tests.cmake")
endif ()

# The start-up of a portable test: the platform's (board bring-up, the
# secondary cores, then os_main) and the common end (the RESULT line and the
# end of the run), wrapping os_main.
if ((UOS_TESTS_PORTABLE OR UOS_TESTS_SUITES)
    AND NOT TARGET ${PLATFORM_NAME}-test-startup)
  add_library (${PLATFORM_NAME}-test-startup INTERFACE)
  # The platform's start-up, where it has one (a Cortex-M board's library
  # already brings the board up and calls os_main itself).
  set (_platform_support
       "${CMAKE_SOURCE_DIR}/platforms/${PLATFORM_NAME}/src/platform-support.cpp")
  if (EXISTS "${_platform_support}")
    target_sources (${PLATFORM_NAME}-test-startup INTERFACE "${_platform_support}")
  endif ()
  # The end of the run: the Cortex-M boards' (the RESULT line on the UART and
  # on semihosting, then back to the board's own end of run), or the common
  # one.
  if (UOS_TESTS_PORT STREQUAL "cortexm")
    target_sources (${PLATFORM_NAME}-test-startup INTERFACE
      "${CMAKE_CURRENT_SOURCE_DIR}/cortexm/test-end.cpp")
  else ()
    target_sources (${PLATFORM_NAME}-test-startup INTERFACE
      "${CMAKE_CURRENT_SOURCE_DIR}/portable-test-end.cpp")
  endif ()
  target_link_options (${PLATFORM_NAME}-test-startup INTERFACE "-Wl,--wrap=os_main")
  # The platform's own headers (include/), as upstream's portable tests see
  # them (blinky's blink-led.h): clock-test's reference-clock.h; then the
  # common ones a platform may override there (blink-led.h).
  target_include_directories (${PLATFORM_NAME}-test-startup INTERFACE
    "${CMAKE_SOURCE_DIR}/platforms/${PLATFORM_NAME}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/include")
  if (UOS_TESTS_PORT STREQUAL "cortexm")
    target_include_directories (${PLATFORM_NAME}-test-startup INTERFACE
      "${CMAKE_CURRENT_SOURCE_DIR}/cortexm")
  endif ()
  target_link_libraries (${PLATFORM_NAME}-test-startup INTERFACE ${UOS_TESTS_STARTUP_LIBS})
  target_compile_definitions (${PLATFORM_NAME}-test-startup INTERFACE ${UOS_TESTS_STARTUP_DEFINES})
endif ()

# The storage of a portable test that uses the SD card: the card as the posix-io
# block device /dev/sd, and the file system the test mounts on it.
if (UOS_TESTS_STORAGE AND NOT TARGET ${PLATFORM_NAME}-test-storage)
  add_library (${PLATFORM_NAME}-test-storage INTERFACE)
  target_sources (${PLATFORM_NAME}-test-storage INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/portable-test-storage.cpp")
  target_include_directories (${PLATFORM_NAME}-test-storage INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/include")
  # The card's driver set is per test (board_test_sd_posix), added beside.
  target_link_libraries (${PLATFORM_NAME}-test-storage INTERFACE
    xpacks::chan-fatfs micro-os-plus::iii-posix-io)
  # The board's card as /dev/sd, for the tests that use the board's driver.
  add_library (${PLATFORM_NAME}-test-storage-sd INTERFACE)
  target_sources (${PLATFORM_NAME}-test-storage-sd INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/portable-test-storage-sd.cpp")
endif ()

# The support the board's tests share: one copy per board, not per test.
file (GLOB _test_support CONFIGURE_DEPENDS "${_test_dir}/src/*.cpp")
set (_test_includes "${_test_dir}/include")
if (UOS_TESTS_PORT STREQUAL "cortexm")
  # The cross-board helpers of the Cortex-M boards (hw_result.hpp, ...).
  list (APPEND _test_includes "${CMAKE_SOURCE_DIR}/board-tests/cortexm")
endif ()

file (GLOB _test_dirs LIST_DIRECTORIES true CONFIGURE_DEPENDS "${_test_dir}/*")
# The portable tests: one copy for every board, in tests/sources/.
# Upstream's suites: the same, from their libraries. What a suite needs beyond
# its library is what upstream's platforms link it with (rtos-apis: the Chan
# FatFs POSIX I/O integration; cmsis-os-validator: the Arm validator), and
# its own configuration: the suite's cmsis-plus/os-app-config.h (the port's
# hands over to it under UOS_HARNESS_SUITE).
foreach (_t IN LISTS UOS_TESTS_SUITES)
  if (IS_DIRECTORY "${_test_dir}/${_t}")
    message (FATAL_ERROR "${_t} is both a suite (tests/sources/) and a board test (${_test_dir}).")
  endif ()
  if (NOT TARGET test::${_t})
    message (FATAL_ERROR "UOS_TESTS_SUITES names ${_t}, but there is no test::${_t} (is tests/sources/${_t} in the platform's dependencies-folders.cmake?).")
  endif ()
  list (APPEND _test_dirs "${CMAKE_SOURCE_DIR}/sources/${_t}")
endforeach ()
if (UOS_TESTS_SUITES AND NOT TARGET ${PLATFORM_NAME}-test-suite)
  add_library (${PLATFORM_NAME}-test-suite INTERFACE)
  target_compile_definitions (${PLATFORM_NAME}-test-suite INTERFACE
    OS_USE_OS_APP_CONFIG_H UOS_HARNESS_SUITE _POSIX_C_SOURCE=200809L _GNU_SOURCE)
endif ()

foreach (_t IN LISTS UOS_TESTS_SOURCES)
  if (IS_DIRECTORY "${_test_dir}/${_t}")
    message (FATAL_ERROR "${_t} is both a portable test (tests/sources/) and a board test (${_test_dir}).")
  endif ()
  if (NOT IS_DIRECTORY "${CMAKE_SOURCE_DIR}/sources/${_t}")
    message (FATAL_ERROR "UOS_TESTS_SOURCES names ${_t}, but there is no tests/sources/${_t}/.")
  endif ()
  list (APPEND _test_dirs "${CMAKE_SOURCE_DIR}/sources/${_t}")
endforeach ()
set (_apps "")
foreach (_dir IN LISTS _test_dirs)
  if (NOT IS_DIRECTORY "${_dir}")
    continue ()
  endif ()
  get_filename_component (_app "${_dir}" NAME)
  if (_app STREQUAL "include" OR _app STREQUAL "src")
    continue ()
  endif ()
  file (GLOB _srcs CONFIGURE_DEPENDS "${_dir}/*.cpp")
  if ("${_app}" IN_LIST UOS_TESTS_SUITES)
    # A suite's sources are its library's (test::<suite>, below).
    set (_srcs "")
  elseif (NOT _srcs)
    continue ()
  endif ()
  list (APPEND _apps "${_app}")

  board_test_defines  ("${_app}" _app_defines)
  board_test_sources  ("${_app}" _app_sources)
  board_test_includes ("${_app}" _app_includes)
  board_test_linker   ("${_app}" _app_linker)
  board_test_options  ("${_app}" _app_options)
  board_test_ncpu     ("${_app}" _app_ncpu)

  # A test carried over whole defines its own start-up support; adding the
  # board's shared copy would be a duplicate definition.
  set (_app_support ${_test_support})
  if ("${_app}" IN_LIST BOARD_TEST_SELF_CONTAINED)
    set (_app_support "")
  endif ()

  # The application's own sources carry its own options, if it has any.
  if (_app_options)
    set_source_files_properties (${_srcs} PROPERTIES COMPILE_OPTIONS "${_app_options}")
  endif ()

  # The port, then the board (its facts and code, micro-os-plus::board).
  set (_libs ${_port_lib} micro-os-plus::board)
  # What the test itself needs, gathered below.
  set (_test_libs "")
  set (_no_kernel "")
  if ("${_app}" IN_LIST BOARD_TEST_NO_KERNEL)
    if (UOS_TESTS_PORT STREQUAL "cortexm")
      # No kernel, no port scheduler: the board alone.
      set (_libs micro-os-plus::board)
    elseif (UOS_TESTS_PORT STREQUAL "posix")
      message (FATAL_ERROR "${_app} is listed in BOARD_TEST_NO_KERNEL, but the POSIX port has no bare target.")
    endif ()
    set (_no_kernel NO_KERNEL)
  endif ()
  if ("${_app}" IN_LIST UOS_TESTS_PORTABLE)
    if (NOT "${_app}" IN_LIST UOS_TESTS_SOURCES)
      message (FATAL_ERROR "${_app} is in UOS_TESTS_PORTABLE but not in UOS_TESTS_SOURCES.")
    endif ()
    list (APPEND _test_libs ${PLATFORM_NAME}-test-startup)
  endif ()
  if ("${_app}" IN_LIST UOS_TESTS_SUITES)
    list (APPEND _test_libs ${PLATFORM_NAME}-test-startup ${PLATFORM_NAME}-test-suite
          test::${_app})
    if (_app STREQUAL "rtos-apis")
      list (APPEND _test_libs xpacks::chan-fatfs micro-os-plus::iii-posix-io)
    elseif (_app STREQUAL "cmsis-os-validator")
      list (APPEND _test_libs xpacks::arm-cmsis-os-validator)
    endif ()
    set (_suite_support
         "${CMAKE_SOURCE_DIR}/platforms/${PLATFORM_NAME}/src/${_app}-support.cpp")
    if (EXISTS "${_suite_support}")
      list (APPEND _app_sources "${_suite_support}")
    endif ()
  endif ()
  if ("${_app}" IN_LIST UOS_TESTS_STORAGE)
    board_test_sd_posix ("${_app}" _app_sd)
    if (NOT _app_sd)
      message (FATAL_ERROR "${_app} uses the SD card, but platforms/${PLATFORM_NAME} sets no UOS_BOARD_SD_POSIX.")
    endif ()
    list (APPEND _test_libs ${PLATFORM_NAME}-test-storage)
    if (NOT _app_sd STREQUAL "OWN")
      list (APPEND _test_libs ${PLATFORM_NAME}-test-storage-sd ${_app_sd})
    endif ()
    # The storage start-up prints through the C library; a board test with
    # its own start-up gets the system calls the platform's start-up has.
    if (NOT "${_app}" IN_LIST UOS_TESTS_PORTABLE)
      list (APPEND _test_libs ${UOS_TESTS_STARTUP_LIBS})
    endif ()
  endif ()
  # What the test itself needs (its start-up, its suite, its storage) goes
  # with the board's libraries -- and with the emulated image's, where those
  # replace the board (board_test_qemu_libs).
  list (APPEND _libs ${_test_libs})
  # Extra libraries (a harness suite's test::<suite>, a board's driver set).
  if (UOS_TESTS_PORT STREQUAL "posix")
    board_test_libraries ("${_app}" _app_libs)
  else ()
    board_test_libs ("${_app}" _app_libs)
  endif ()
  if (_app_libs)
    list (APPEND _libs ${_app_libs})
  endif ()

  # A test listed HWD_ONLY gets the hardware image only.
  set (_app_variants ${_variants})
  if ("${_app}" IN_LIST BOARD_TEST_HWD_ONLY)
    set (_app_variants hwd)
  endif ()

  foreach (_variant IN LISTS _app_variants)
    set (_variant_libs ${_libs})
    set (_variant_ncpu ${_app_ncpu})
    set (_variant_sources ${_app_sources})
    set (_variant_includes ${_app_includes})
    set (_variant_defines "")
    set (_variant_linker "")
    if (_variant STREQUAL "hwd")
      set (_variant_defines HW_BUILD)
      if (UOS_TESTS_PORT STREQUAL "aarch64")
        list (APPEND _variant_defines SEMI_PRINTS=${SEMI_PRINTS})
      endif ()
      # DEBUG_BOOT is opt-in: every early-boot marker is a semihosting trap.
      if (UOS_DEBUG_BOOT)
        list (APPEND _variant_defines DEBUG_BOOT)
      endif ()
      set (_variant_linker "${_linker_hwd}")
      # A test that names its own script takes it (hardware image only).
      if (_app_linker)
        set (_variant_linker "${_app_linker}")
      endif ()
    elseif (_variant STREQUAL "qemu")
      set (_variant_defines QEMU_BUILD)
      set (_variant_linker "${_linker_qemu}")
      # The emulated image may replace the board entirely (the RP2xxx boards):
      # the kernel plus a generic device, its own linker script and one CPU.
      board_test_qemu_libs ("${_app}" _qemu_libs)
      if (_qemu_libs)
        set (_variant_libs ${_qemu_libs} ${_test_libs} ${_app_libs})
        set (_variant_linker "")
        set (_variant_ncpu 1)
      endif ()
      board_test_qemu_sources ("${_app}" _qemu_sources)
      if (_qemu_sources)
        set (_variant_sources ${_qemu_sources})
      endif ()
      board_test_qemu_includes ("${_app}" _qemu_includes)
      list (APPEND _variant_includes ${_qemu_includes})
    endif ()

    uos_add_app (
      "${_app}-${_variant}"
      ${_no_kernel}
      SOURCES ${_srcs} ${_app_support} ${_variant_sources}
      NCPU ${_variant_ncpu}
      LINKER_SCRIPT "${_variant_linker}"
      DEFINES ${_common_defines} ${_app_defines} ${_variant_defines}
      # ${_dir}: the application's own folder, -I. for headers beside it.
      INCLUDES ${_variant_includes} ${_dir} ${_test_includes}
      LIBRARIES ${_variant_libs}
      OUTPUT_NAME "${_app}-${_variant}"
    )

    # hw.sh loads `$BUILD/test/<app>-hwd`, with no extension; leave a symlink
    # under that name. The `.elf` stays the real file.
    if (_variant STREQUAL "hwd")
      add_custom_command (
        TARGET "${_app}-${_variant}"
        POST_BUILD
        COMMAND
          "${CMAKE_COMMAND}" -E create_symlink
          "$<TARGET_FILE:${_app}-${_variant}>"
          "$<TARGET_FILE_DIR:${_app}-${_variant}>/${_app}-${_variant}"
        VERBATIM
      )
    endif ()
  endforeach ()
endforeach ()

# The tests built, for the platform to register.
set (UOS_TESTS_APPS ${_apps} PARENT_SCOPE)

list (LENGTH _apps _n)
list (LENGTH _variants _nv)
math (EXPR _n "${_n} * ${_nv}")
message (STATUS "µOS++ III ${UOS_TESTS_PORT} board tests: ${_n} targets, board=${BOARD}, from ${_test_dir}")

# The AArch64->AArch32 QEMU boot shim: QEMU's raspi3b starts its Cortex-A53
# cores in AArch64, so an AArch32 image is loaded at an address and this shim
# drops to AArch32 and jumps there. Built with the aarch64 toolchain.
if (UOS_TESTS_PORT STREQUAL "aarch32")
  unset (_a64_gcc CACHE)
  unset (_a64_objcopy CACHE)
  find_program (_a64_gcc aarch64-none-elf-gcc)
  find_program (_a64_objcopy aarch64-none-elf-objcopy)
  if (_a64_gcc AND _a64_objcopy AND EXISTS "${_boards_dir}/qemu-raspi3-shim/shim.S")
    set (_shim_src "${_boards_dir}/qemu-raspi3-shim")
    add_custom_command (
      OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/shim8.img"
      COMMAND "${_a64_gcc}" -nostdlib
              "-Wl,-T,${_shim_src}/shim.ld" "${_shim_src}/shim.S"
              -o "${CMAKE_CURRENT_BINARY_DIR}/shim.elf"
      COMMAND "${_a64_objcopy}" -O binary
              "${CMAKE_CURRENT_BINARY_DIR}/shim.elf"
              "${CMAKE_CURRENT_BINARY_DIR}/shim8.img"
      DEPENDS "${_shim_src}/shim.S" "${_shim_src}/shim.ld"
      COMMENT "Building the AArch64->AArch32 QEMU boot shim"
      VERBATIM
    )
    add_custom_target (qemu-shim ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/shim8.img")
  else ()
    message (STATUS "µOS++ III AArch32: no aarch64 toolchain, QEMU boot shim not built")
  endif ()
endif ()
