# -----------------------------------------------------------------------------
# This file is part of the µOS++ project (https://micro-os-plus.github.io/).
# Copyright (c) 2026 Liviu Ionescu. All rights reserved.
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose is hereby granted, under the terms of the MIT license.
#
# If a copy of the license was not distributed with this file, it can be
# obtained from https://opensource.org/licenses/mit.
# -----------------------------------------------------------------------------

# One hardware test on a board OpenOCD can only halt and load (the AArch
# boards: no reset line, the image runs from RAM). CTest runs OpenOCD with the
# board's configuration, this file, and one call:
#
#   openocd -f <board>.cfg [-c init] -f uos-hwd.tcl
#           -c "uos_hwd_run <elf> <entry> <target format> <cores>
#               <semihosting cores> <resume mode> <adapter kHz> <pre-load>"
#
# The run ends when the test's semihosting SYS_EXIT ends OpenOCD; CTest reads
# the RESULT line the test wrote through semihosting (PASS/FAIL regular
# expressions) and stops a run that never ends at its TIMEOUT. The UART is
# never opened. A reset that drops the debug link (the Pi's PM watchdog, the
# RK3506 global reset) is a separate OpenOCD session, a CTest fixture run
# before this one (uos-hwd-reset.cmake).
#
# The steps are the ones the former test_smpl/run-hw.sh took: halt the cores (cores left
# running stale code would corrupt RAM during load_image), enable semihosting,
# the board's hooks, an optional pre-load, load the image, resume.
#
#   target format   printf format of the OpenOCD target names, the core index
#                   its only conversion (bcm2837.cpu%d, rk3506.a7.%d, ...)
#   cores           the cores to halt and resume (a board whose secondaries
#                   are held in reset until the kernel releases them lists 0)
#   resume mode     entry      resume every core at the entry, touching no
#                              register (the RK3506's loader leaves SVC)
#                   cpsr       set CPSR to SVC with interrupts masked, resume
#                              every core at the entry
#                   pc-first   set PC on the first core and resume it; the
#                              others resume where the firmware parked them
#                              and wait for the kernel (AArch64 Pi)
#                   cpsr-first the same with "cpsr" on the first core
#                              (AArch32 Pi)
#                   pc         set PC on every core, then resume them
#   adapter kHz     the JTAG/SWD clock after init ("" keeps the config's)
#   pre-load        Tcl run on the first core after the halt and before the
#                   load ("" for none)

proc uos_hwd_run {elf entry target_fmt cores semihost_cores resume
                  {adapter_khz ""} {preload ""}} {
  # UOS_HW_ADAPTER_KHZ in the environment overrides the clock (slower for
  # long jumper wires; the same knob the former run-hw.sh had).
  if {[info exists ::env(UOS_HW_ADAPTER_KHZ)]} {
    set adapter_khz $::env(UOS_HW_ADAPTER_KHZ)
  }
  if {$adapter_khz ne ""} {
    echo "--- stage: JTAG clock -> $adapter_khz kHz ---"
    adapter speed $adapter_khz
  }
  echo "--- stage: halt cores $cores ---"
  foreach core $cores { targets [format $target_fmt $core]; halt }

  echo "--- stage: enable semihosting on cores $semihost_cores ---"
  foreach core $semihost_cores {
    targets [format $target_fmt $core]
    arm semihosting enable
  }
  # The board's own steps, defined by its OpenOCD configuration.
  if {[info procs rpi4b_enable_hde] ne ""} { rpi4b_enable_hde }
  if {[info procs uos_board_post_semihosting] ne ""} {
    uos_board_post_semihosting
  }

  set first [format $target_fmt [lindex $cores 0]]
  if {$preload ne ""} {
    echo "--- stage: pre-load ---"
    targets $first
    eval $preload
  }

  echo "--- stage: load_image $elf ---"
  targets $first
  load_image $elf

  echo "--- stage: resume cores $cores at $entry ---"
  switch -- $resume {
    entry {
      foreach core $cores {
        targets [format $target_fmt $core]
        resume $entry
      }
    }
    cpsr {
      foreach core $cores {
        targets [format $target_fmt $core]
        reg cpsr 0x600001da
        resume $entry
      }
    }
    pc-first -
    cpsr-first {
      targets $first
      if {$resume eq "cpsr-first"} {
        reg cpsr 0x600001da
        resume $entry
      } else {
        reg pc $entry
        echo "  start PC core [lindex $cores 0] = [reg pc]"
        resume
      }
      foreach core [lrange $cores 1 end] {
        targets [format $target_fmt $core]
        if {[[target current] curstate] eq "halted"} { resume }
      }
    }
    default {
      foreach core $cores {
        targets [format $target_fmt $core]
        reg pc $entry
      }
      foreach core $cores {
        targets [format $target_fmt $core]
        resume
      }
    }
  }
}
