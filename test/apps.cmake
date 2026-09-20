# -----------------------------------------------------------------------------
# The shared test applications, and the build knobs each one needs.
#
# This table is the one place that knows which tests exist and what they are
# configured with. Every architecture project reads it and builds the same
# twelve applications; none of them keeps its own list.
#
# Defines that are the same for every test (TRACE, SEMIHOST, the board macros)
# belong to the architecture project, not here -- they depend on the toolchain
# and the board, which this file knows nothing about.
# -----------------------------------------------------------------------------
include_guard (GLOBAL)

set (UOS_TEST_APPS
     sd_test
     smp_test0
     smp_test1
     smp_test2
     smp_test3
     smp_test4
     smp-mat-test
     smp-mat-sdcard-test
     smp-num-test
     smp-pipeline-test
     smp-pro-cons-test
     usb_test
     CACHE INTERNAL "Shared µOS++ III SMP test applications")

# Tests that only make sense on more than one CPU. A single-CPU port (an
# STM32 at OS_NCPU=1) skips these and still builds the rest.
set (UOS_TEST_APPS_SMP_ONLY
     smp_test0 smp_test1 smp_test2 smp_test3 smp_test4
     smp-mat-test smp-mat-sdcard-test smp-pipeline-test smp-pro-cons-test
     CACHE INTERNAL "Tests that require OS_NCPU > 1")

# Tests that read or write the SD card, and so need micro-os-plus::devices.
set (UOS_TEST_APPS_NEED_SD
     sd_test smp-mat-sdcard-test smp-num-test smp-pipeline-test
     CACHE INTERNAL "Tests that need the SD/FatFs drivers")

# -----------------------------------------------------------------------------
# uos_test_app_defines (<app> <out-var>)
#
# The application-specific -D flags, carried over from the per-test Makefiles.
# Anything not listed here has no knobs of its own.
# -----------------------------------------------------------------------------
function (uos_test_app_defines _app _out)
  set (_d "")
  if (_app STREQUAL "usb_test")
    # led.hpp's own default is GPIO 16, which blinks nothing on a bare board.
    # A burst of LED_BLINKS blinks, each LED_ON_MS lit then LED_OFF_MS dark,
    # then LED_GAP_MS dark, repeating.
    list (APPEND _d LED_PIN=29 LED_BLINKS=3 LED_ON_MS=40 LED_OFF_MS=40
                    LED_GAP_MS=300 USB_FORCE_FS)
  endif ()
  set (${_out} "${_d}" PARENT_SCOPE)
endfunction ()
