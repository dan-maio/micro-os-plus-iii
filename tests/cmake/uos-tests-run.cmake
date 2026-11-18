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
# file system allows it) for each run, deleted when the run ends: sd_test and
# smp-mat-sdcard-test a boot card's layout, MBR + FAT32 (board-tests/
# sd-image.py; sd_test's with a host-written seed.bin), the others a blank card
# they format themselves.
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
  if (_a_APP MATCHES "^(sd_test|smp-mat-sdcard-test|smp-num-test|smp-pipeline-test)$")
    find_package (Python3 COMPONENTS Interpreter REQUIRED)
    set (_img "${CMAKE_CURRENT_BINARY_DIR}/${_a_NAME}.disk.img")
    if (_a_APP STREQUAL "sd_test")
      # A boot card's layout (MBR + FAT32), with the host-written seed.bin.
      set (_make "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/board-tests/sd-image.py" "${_img}" --seed)
    elseif (_a_APP STREQUAL "smp-mat-sdcard-test")
      # A boot card's layout (MBR + FAT32), empty.
      set (_make "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/board-tests/sd-image.py" "${_img}")
    else ()
      set (_make "${Python3_EXECUTABLE}" -c "open(__import__('sys').argv[1],'wb').truncate(4<<30)" "${_img}")
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
# presents as the card; the back-end creates and grows it itself.
function (uos_tests_add_host)
  cmake_parse_arguments (_a "" "NAME;APP;PROGRAM" "" ${ARGN})
  add_test (NAME "${_a_NAME}" COMMAND "${_a_PROGRAM}")
  uos_tests_timeout ("${_a_APP}" _timeout)
  set_tests_properties ("${_a_NAME}" PROPERTIES
    LABELS "host" TIMEOUT ${_timeout} ${UOS_TESTS_RESULT_PROPERTIES})
  if (_a_APP MATCHES "^(smp-num-test|smp-pipeline-test|smp-mat-sdcard-test|sd_test|flatfs-test)$")
    set_tests_properties ("${_a_NAME}" PROPERTIES
      ENVIRONMENT "UOS_SD_IMAGE=${CMAKE_CURRENT_BINARY_DIR}/${_a_NAME}.disk.img")
  endif ()
endfunction ()
