# -----------------------------------------------------------------------------
# What this board's tests need.
#
# mos-test1 and spi-pipeline are the board's own tests and keep the defaults:
# one CPU, the kernel's non-SMP branch.
#
# The three harness suites run here under the kernel's SMP scheduler at
# OS_NCPU=1: the SMP code paths (per-CPU current thread and lock state, the
# affinity-aware picker, the stack_ptr liveness rule) on one Cortex-M4F, at
# the board's 100 MHz (HSE 25 MHz -> PLL, os-hooks.c). The port's upstream
# core carries that branch (src/rtos/os-core.cpp, gated on
# OS_USE_SMP_SCHEDULER); its kernel lock is interrupt masking with an
# owner/depth record, since one CPU has no other core to exclude. The suites
# use neither the LED (PC13) nor the SPI NOR flash; their verdict goes out on
# semihosting and on USART1 (PA9/PA10).
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# The harness suites.
#
# Upstream's suites (tests/sources/<suite>/, test::<suite>), built by the
# tests' builder from the platform's UOS_TESTS_SUITES on the platform's
# start-up: <platform>-test-startup (the end of the run is
# board-tests/cortexm/test-end.cpp, the RESULT line through this platform's
# include/test-end-console.h; -Wl,--wrap=os_main) and <platform>-test-suite
# (the suite's own os-app-config.h, UOS_HARNESS_SUITE). The names below are
# still this board's knobs (single core, defines).
# -----------------------------------------------------------------------------
set (_harness_suites rtos-apis mutex-stress cmsis-os-validator)

function (board_test_defines _app _out)
  # The suites build the kernel's SMP branch. NCPU stays the board's 1, so
  # uos_add_app() defines OS_NCPU=1 and, on its own, no SMP scheduler: the
  # define is added here, for these three applications only.
  if ("${_app}" IN_LIST _harness_suites)
    set (${_out} OS_USE_SMP_SCHEDULER=1 PARENT_SCOPE)
  else ()
    set (${_out} "" PARENT_SCOPE)
  endif ()
endfunction ()

function (board_test_libs _app _out)
  set (${_out} "" PARENT_SCOPE)
endfunction ()
