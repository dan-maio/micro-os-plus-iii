# -----------------------------------------------------------------------------
# How the QEMU and host tests run: CTest starts the program itself.
#
# This replaces test_smpl/run-qemu.sh and run-host.sh. What the scripts did,
# and where it is now:
#
#   pick one test         one add_test per program
#   timeout per test      uos_tests_timeout(), the table below, -> TIMEOUT
#   verdict from RESULT:  PASS/FAIL/SKIP_REGULAR_EXPRESSION (with a pass
#                         expression set, CTest ignores the exit code, as
#                         the scripts did)
#   AArch32 shim          plain QEMU arguments (-kernel shim, -device loader)
#   SD card image         a CTest fixture: one test creates a fresh image,
#                         one deletes it, around the test that uses it
#   a log per test        ctest --output-log / --output-junit
#
# Only CMake, the emulator, the test program and (for the SD images) Python 3
# are needed, so the same lines run on Linux, macOS and Windows.
# -----------------------------------------------------------------------------

include_guard (GLOBAL)

# The verdict, from the RESULT line every test prints.
set (UOS_TESTS_RESULT_PROPERTIES
     PASS_REGULAR_EXPRESSION "RESULT: PASS"
     FAIL_REGULAR_EXPRESSION "RESULT: FAIL"
     SKIP_REGULAR_EXPRESSION "RESULT: SKIP")

# Wall-clock budgets in seconds (from the predecessor repository's
# run_one_test.sh), not expected durations.
function (uos_tests_timeout app out_var)
  if (app MATCHES "^smp_test[0134]$")
    set (_t 150)
  elseif (app STREQUAL "smp_test2")
    set (_t 300)
  elseif (app STREQUAL "smp-mat-test")
    set (_t 900)
  elseif (app STREQUAL "smp-mat-sdcard-test")
    set (_t 2000)
  elseif (app MATCHES "^(smp-num-test|smp-pipeline-test|smp-pro-cons-test)$")
    set (_t 1000)
  elseif (app STREQUAL "sd_test")
    set (_t 450)
  elseif (app STREQUAL "usb_test")
    set (_t 200)
  else ()
    set (_t 300)
  endif ()
  set (${out_var} ${_t} PARENT_SCOPE)
endfunction ()

# uos_tests_add_qemu (
#   NAME <ctest name> APP <app> IMAGE <raw image>
#   QEMU <qemu-system-*> MACHINE <machine arguments...>
#   [SHIM <shim image> LOAD_ADDRESS <address>])  AArch32 on a 64-bit machine
#
# The tests that use the SD card get a fresh 4 GiB raw image (sparse where the
# file system allows it) for each run, deleted when the run ends: a boot card's
# layout, MBR + FAT32 (board-tests/sd-image.py; sd_test's with a host-written
# seed.bin).
function (uos_tests_add_qemu)
  cmake_parse_arguments (
    _a "" "NAME;APP;IMAGE;QEMU;SHIM;LOAD_ADDRESS" "MACHINE" ${ARGN}
  )

  if (_a_SHIM)
    set (_boot -kernel "${_a_SHIM}" -device "loader,file=${_a_IMAGE},addr=${_a_LOAD_ADDRESS}")
  else ()
    set (_boot -kernel "${_a_IMAGE}")
  endif ()

  set (_drive)
  set (_fixture)
  if (_a_APP MATCHES "^(sd_test|smp-mat-sdcard-test|smp-num-test|smp-pipeline-test|smp-shapes-test)$")
    find_package (Python3 COMPONENTS Interpreter REQUIRED)
    set (_img "${CMAKE_CURRENT_BINARY_DIR}/${_a_NAME}.disk.img")
    # A boot card's layout (MBR + FAT32); sd_test's with the host-written
    # seed.bin.
    set (_make "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/board-tests/sd-image.py" "${_img}")
    if (_a_APP STREQUAL "sd_test")
      list (APPEND _make --seed)
    endif ()
    set (_fixture "${_a_NAME}-sd")
    add_test (NAME "${_a_NAME}-sd-make" COMMAND ${_make})
    add_test (NAME "${_a_NAME}-sd-remove" COMMAND "${CMAKE_COMMAND}" -E rm -f "${_img}")
    set_tests_properties ("${_a_NAME}-sd-make" PROPERTIES FIXTURES_SETUP "${_fixture}" LABELS "qemu")
    set_tests_properties ("${_a_NAME}-sd-remove" PROPERTIES FIXTURES_CLEANUP "${_fixture}" LABELS "qemu")
    set (_drive -drive "file=${_img},if=sd,format=raw")
  endif ()

  add_test (
    NAME "${_a_NAME}"
    COMMAND "${_a_QEMU}" ${_a_MACHINE} -nographic -serial none -monitor none
            -semihosting-config enable=on,target=native ${_drive} ${_boot}
  )
  uos_tests_timeout ("${_a_APP}" _timeout)
  set_tests_properties ("${_a_NAME}" PROPERTIES
    LABELS "qemu" TIMEOUT ${_timeout} ${UOS_TESTS_RESULT_PROPERTIES})
  if (_fixture)
    set_tests_properties ("${_a_NAME}" PROPERTIES FIXTURES_REQUIRED "${_fixture}")
  endif ()
endfunction ()

# uos_tests_add_host (NAME <ctest name> APP <app> PROGRAM <executable>)
#
# The tests that use the SD card get UOS_SD_IMAGE, a file the host back-end
# presents as the card. For the storage tests (posix-io + Chan FatFs) it is a
# fresh boot card's layout for each run, MBR + FAT32 (board-tests/
# sd-image.py, sd_test's with seed.bin), deleted when the run ends.
function (uos_tests_add_host)
  cmake_parse_arguments (_a "" "NAME;APP;PROGRAM" "" ${ARGN})
  add_test (NAME "${_a_NAME}" COMMAND "${_a_PROGRAM}")
  uos_tests_timeout ("${_a_APP}" _timeout)
  set_tests_properties ("${_a_NAME}" PROPERTIES
    LABELS "host" TIMEOUT ${_timeout} ${UOS_TESTS_RESULT_PROPERTIES})
  set (_img "${CMAKE_CURRENT_BINARY_DIR}/${_a_NAME}.disk.img")
  if (_a_APP MATCHES "^(smp-num-test|smp-pipeline-test|smp-mat-sdcard-test|sd_test)$")
    set_tests_properties ("${_a_NAME}" PROPERTIES ENVIRONMENT "UOS_SD_IMAGE=${_img}")
    find_package (Python3 COMPONENTS Interpreter REQUIRED)
    set (_make "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/board-tests/sd-image.py" "${_img}")
    if (_a_APP STREQUAL "sd_test")
      list (APPEND _make --seed)
    endif ()
    set (_fixture "${_a_NAME}-sd")
    add_test (NAME "${_a_NAME}-sd-make" COMMAND ${_make})
    add_test (NAME "${_a_NAME}-sd-remove" COMMAND "${CMAKE_COMMAND}" -E rm -f "${_img}")
    set_tests_properties ("${_a_NAME}-sd-make" PROPERTIES FIXTURES_SETUP "${_fixture}" LABELS "host")
    set_tests_properties ("${_a_NAME}-sd-remove" PROPERTIES FIXTURES_CLEANUP "${_fixture}" LABELS "host")
    set_tests_properties ("${_a_NAME}" PROPERTIES FIXTURES_REQUIRED "${_fixture}")
  endif ()
endfunction ()

# -----------------------------------------------------------------------------
# Hardware tests: CTest runs OpenOCD directly, as upstream's hardware tests
# do; no shell script in between. OpenOCD comes from the configuration's
# xpm .bin, which xpm puts first on PATH during prepare/build/test (this is
# the per-configuration pinned xPack). If it is not there, the PATH's copy
# is used.

unset (UOS_TESTS_OPENOCD CACHE)
find_program (UOS_TESTS_OPENOCD openocd)
if (NOT UOS_TESTS_OPENOCD)
  set (UOS_TESTS_OPENOCD "openocd")
endif ()

# uos_tests_add_hwd (
#   NAME <ctest name> APP <app> ELF <image>
#   CFG <board's OpenOCD configuration> [INIT] [PRE_CFG <Tcl commands...>]
#   ENTRY <address> TARGET_FMT <format> CORES <i...> SEMIHOST_CORES <i...>
#   RESUME entry|cpsr|pc-first|cpsr-first|pc
#   [ADAPTER_KHZ <kHz>] [PRELOAD <Tcl>]
#   [RESET_COMMAND <Tcl> RESET_EXPECT <regex> RESET_WAIT <seconds>]
#   [TIMEOUT <seconds>])
#
# A board OpenOCD halts and loads (the AArch boards, image in RAM):
# uos-hwd.tcl's uos_hwd_run does the run, the test's semihosting SYS_EXIT
# ends OpenOCD, the RESULT line is the verdict. INIT: the configuration does
# not init itself. PRE_CFG: commands before the configuration (a probe
# default). RESET_*: a reset that drops the debug link, run in its own OpenOCD
# session as a CTest fixture of the test, then RESET_WAIT seconds for the
# board to come back; the test is not run if the session's output does not
# match RESET_EXPECT. Tcl's ';' in PRELOAD and RESET_COMMAND becomes a
# newline (CMake splits a function's arguments at ';').
function (uos_tests_add_hwd)
  cmake_parse_arguments (_a "INIT"
    "NAME;APP;ELF;CFG;ENTRY;TARGET_FMT;RESUME;ADAPTER_KHZ;RESET_EXPECT;RESET_WAIT;TIMEOUT"
    "CORES;SEMIHOST_CORES;PRE_CFG;PRELOAD;RESET_COMMAND" ${ARGN})
  get_filename_component (_cfg_dir "${_a_CFG}" DIRECTORY)
  set (_ocd_args -s "${_cfg_dir}")
  foreach (_c IN LISTS _a_PRE_CFG)
    list (APPEND _ocd_args -c "${_c}")
  endforeach ()
  list (APPEND _ocd_args -f "${_a_CFG}")
  if (_a_INIT)
    list (APPEND _ocd_args -c "init")
  endif ()

  list (JOIN _a_CORES " " _cores)
  list (JOIN _a_SEMIHOST_CORES " " _semi)
  # PRELOAD and RESET_COMMAND arrive split at their ';' (CMake splits a
  # function's arguments there): join the pieces with newlines, which Tcl
  # reads the same way.
  list (JOIN _a_PRELOAD "\n" _preload)
  add_test (NAME "${_a_NAME}"
    COMMAND "${UOS_TESTS_OPENOCD}" ${_ocd_args}
            -f "${CMAKE_SOURCE_DIR}/cmake/uos-hwd.tcl"
            -c "uos_hwd_run {${_a_ELF}} ${_a_ENTRY} {${_a_TARGET_FMT}} {${_cores}} {${_semi}} ${_a_RESUME} {${_a_ADAPTER_KHZ}} {${_preload}}")
  if (_a_TIMEOUT)
    set (_timeout ${_a_TIMEOUT})
  else ()
    uos_tests_timeout ("${_a_APP}" _timeout)
  endif ()
  set_tests_properties ("${_a_NAME}" PROPERTIES
    LABELS "hwd" TIMEOUT ${_timeout} RUN_SERIAL TRUE
    ${UOS_TESTS_RESULT_PROPERTIES})

  if (_a_RESET_COMMAND)
    list (JOIN _a_RESET_COMMAND "\n" _reset)
    set (_reset_args ${_ocd_args} -c "${_reset}")
    # One -D value: CTest would keep its ';' escaped, so the arguments travel
    # joined with '|' (in no path and no Tcl command here) and
    # uos-hwd-reset.cmake splits them again.
    string (FIND "${_reset_args}" "|" _bar)
    if (NOT _bar EQUAL -1)
      message (FATAL_ERROR "${_a_NAME}: a reset argument contains '|'.")
    endif ()
    list (JOIN _reset_args "|" _reset_args)
    add_test (NAME "${_a_NAME}-reset"
      COMMAND "${CMAKE_COMMAND}"
              "-DOPENOCD=${UOS_TESTS_OPENOCD}" "-DARGS=${_reset_args}"
              "-DEXPECT=${_a_RESET_EXPECT}" "-DWAIT=${_a_RESET_WAIT}"
              "-DLOG=${CMAKE_CURRENT_BINARY_DIR}/${_a_NAME}-reset.log"
              -P "${CMAKE_SOURCE_DIR}/cmake/uos-hwd-reset.cmake")
    set_tests_properties ("${_a_NAME}-reset" PROPERTIES
      LABELS "hwd-reset" TIMEOUT 120 RUN_SERIAL TRUE
      FIXTURES_SETUP "${_a_NAME}-reset")
    set_tests_properties ("${_a_NAME}" PROPERTIES
      FIXTURES_REQUIRED "${_a_NAME}-reset")
  endif ()
endfunction ()

# uos_tests_add_openocd (
#   NAME <ctest name> APP <app> ELF <image> CFG <board's OpenOCD configuration>
#   [PRE_CFG <Tcl commands...>] COMMANDS <Tcl commands...> [TIMEOUT <seconds>])
#
# A board OpenOCD programs and resets (the Cortex-M boards), as upstream's
# hardware tests run: the configuration, then each command as a -c, @ELF@
# standing for the image. The test's semihosting SYS_EXIT ends OpenOCD; the
# RESULT line is the verdict.
function (uos_tests_add_openocd)
  cmake_parse_arguments (_a "" "NAME;APP;ELF;CFG;TIMEOUT" "PRE_CFG;COMMANDS"
                         ${ARGN})
  get_filename_component (_cfg_dir "${_a_CFG}" DIRECTORY)
  set (_ocd_args -s "${_cfg_dir}")
  foreach (_c IN LISTS _a_PRE_CFG)
    list (APPEND _ocd_args -c "${_c}")
  endforeach ()
  list (APPEND _ocd_args -f "${_a_CFG}")
  foreach (_c IN LISTS _a_COMMANDS)
    string (REPLACE "@ELF@" "${_a_ELF}" _c "${_c}")
    list (APPEND _ocd_args -c "${_c}")
  endforeach ()
  add_test (NAME "${_a_NAME}" COMMAND "${UOS_TESTS_OPENOCD}" ${_ocd_args})
  if (_a_TIMEOUT)
    set (_timeout ${_a_TIMEOUT})
  else ()
    uos_tests_timeout ("${_a_APP}" _timeout)
  endif ()
  set_tests_properties ("${_a_NAME}" PROPERTIES
    LABELS "hwd" TIMEOUT ${_timeout} RUN_SERIAL TRUE
    ${UOS_TESTS_RESULT_PROPERTIES})
endfunction ()
