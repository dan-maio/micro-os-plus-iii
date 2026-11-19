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

# A board reset that drops the debug link, before a hardware test: one OpenOCD
# session that runs the reset, then a wait for the board to come back (the
# Pi's firmware to boot and re-enable JTAG). A CTest fixture of the test
# (uos_tests_add_hwd's RESET), run as:
#
#   cmake -D OPENOCD=<openocd> -D ARGS=<openocd arguments, joined with '|'>
#         -D EXPECT=<regex the session's output must match>
#         -D WAIT=<seconds> -D LOG=<log file> -P uos-hwd-reset.cmake
#
# Fails when the session's output does not match EXPECT: OpenOCD did not reach
# the board (off, not booted, the wrong probe), and the test then is not run.

foreach (_v OPENOCD ARGS EXPECT WAIT LOG)
  if (NOT DEFINED ${_v})
    message (FATAL_ERROR "uos-hwd-reset.cmake: ${_v} is not set.")
  endif ()
endforeach ()

string (REPLACE "|" ";" _args "${ARGS}")
execute_process (
  COMMAND "${OPENOCD}" ${_args}
  OUTPUT_VARIABLE _out ERROR_VARIABLE _out
  TIMEOUT 60)
file (WRITE "${LOG}" "${_out}")

if (NOT _out MATCHES "${EXPECT}")
  message (FATAL_ERROR
    "The reset session did not reach the board (see ${LOG}): power-cycle the "
    "board, check its probe and wiring.")
endif ()

message (STATUS "reset done; waiting ${WAIT} s for the board")
execute_process (COMMAND "${CMAKE_COMMAND}" -E sleep "${WAIT}")
