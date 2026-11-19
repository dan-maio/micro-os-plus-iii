# -----------------------------------------------------------------------------
# micro-os-plus::board for a Cortex-M board platform.
#
# The board facts are the platform's (tests/platforms/<P>/cmake/board.cmake);
# this builds the board target from them, as the Cortex-M port's
# "-board-interface" did when the port still read the board. The board's code
# and its linker scripts are the platform's (include/, src/,
# device/linker-scripts/).
#
# Facts read: UOS_BOARD_SRC_DIR, UOS_BOARD_FLAGS, UOS_BOARD_NCPU,
# UOS_BOARD_CAPS, UOS_BOARD_LINKER_HW, UOS_BOARD_DEFINES, and optionally
# UOS_BOARD_LIBS, UOS_BOARD_LINKER_QEMU, UOS_BOARD_RTOS_GLUE, UOS_PORT_LIB
# (default micro-os-plus::cortexm).
#
# A macro, not a function: the facts it checks and completes stay visible to
# the tests' builder, which the platform adds next.
# -----------------------------------------------------------------------------

include_guard (GLOBAL)

macro (uos_cortexm_board_library)
  # UOS_BOARD_LINKER_QEMU may be unset: a board QEMU cannot usefully model
  # is built for hardware only (the three STM32 boards).
  foreach (_required IN ITEMS UOS_BOARD_SRC_DIR UOS_BOARD_FLAGS UOS_BOARD_NCPU
                              UOS_BOARD_CAPS UOS_BOARD_LINKER_HW
                              UOS_BOARD_DEFINES)
    if (NOT DEFINED ${_required})
      message (FATAL_ERROR
        "platforms/${PLATFORM_NAME}/cmake/board.cmake does not set ${_required}.")
    endif ()
  endforeach ()

  get_filename_component (UOS_BOARD_SRC_DIR "${UOS_BOARD_SRC_DIR}" ABSOLUTE)
  if (NOT IS_DIRECTORY "${UOS_BOARD_SRC_DIR}")
    message (FATAL_ERROR
      "platforms/${PLATFORM_NAME}/cmake/board.cmake points at ${UOS_BOARD_SRC_DIR}, which does not exist.")
  endif ()

  if (NOT DEFINED UOS_PORT_LIB)
    set (UOS_PORT_LIB micro-os-plus::cortexm)
  endif ()

  file (GLOB _board_sources CONFIGURE_DEPENDS
        "${UOS_BOARD_SRC_DIR}/src/*.c" "${UOS_BOARD_SRC_DIR}/src/*.cpp"
        "${UOS_BOARD_SRC_DIR}/src/*.S" "${UOS_BOARD_SRC_DIR}/src/rtos/*.cpp")

  # The newlib/OS glue is identical on every board of the port, so there is
  # one copy of it, in the port's board-tests/cortexm/. It is inserted where
  # the glob used to find each board's own src/syscalls.c -- the glob is
  # sorted, so the position is reproducible and link order does not move.
  # Boards that compose their glue PER TEST name it themselves (the RP2xxx
  # ones, whose kernel-less probes must not link it) and are recognised by
  # having set UOS_BOARD_RTOS_GLUE.
  if (NOT DEFINED UOS_BOARD_RTOS_GLUE)
    set (_uos_syscalls "${CMAKE_SOURCE_DIR}/board-tests/cortexm/syscalls.c")
    set (_uos_at -1)
    set (_i 0)
    foreach (_f IN LISTS _board_sources)
      get_filename_component (_n "${_f}" NAME)
      if (_n STRGREATER "syscalls.c" AND _uos_at EQUAL -1)
        set (_uos_at ${_i})
      endif ()
      math (EXPR _i "${_i} + 1")
    endforeach ()
    if (_uos_at EQUAL -1)
      list (APPEND _board_sources "${_uos_syscalls}")
    else ()
      list (INSERT _board_sources ${_uos_at} "${_uos_syscalls}")
    endif ()
  endif ()

  # The board: its flags, its include path, its start-up and its silicon
  # support. True before any scheduler exists, and therefore linkable on its
  # own (the kernel-less tests link only this).
  add_library (board-${PLATFORM_NAME}-interface INTERFACE)
  target_include_directories (
    board-${PLATFORM_NAME}-interface INTERFACE "${UOS_BOARD_SRC_DIR}/include"
  )
  target_sources (board-${PLATFORM_NAME}-interface INTERFACE ${_board_sources})
  target_compile_definitions (
    board-${PLATFORM_NAME}-interface INTERFACE ${UOS_BOARD_DEFINES}
  )
  target_compile_options (
    board-${PLATFORM_NAME}-interface
    INTERFACE ${UOS_BOARD_FLAGS}
              # Without it every static object with a destructor registers
              # through __cxa_atexit and drags in the exit machinery, which a
              # 512 KiB part does not want.
              $<$<COMPILE_LANGUAGE:CXX>:-fno-use-cxa-atexit>
  )
  target_link_options (
    board-${PLATFORM_NAME}-interface
    INTERFACE ${UOS_BOARD_FLAGS}
              # newlib-nano; the linker scripts are sized for it.
              --specs=nano.specs
  )
  # The start-up and the trace back-end are board choices (UOS_BOARD_LIBS):
  # the STM32 boards take micro-os-plus::iii-startup and
  # ::iii-trace-semihosting, the RP2xxx boards their own boot.S and a UART.
  target_link_libraries (board-${PLATFORM_NAME}-interface INTERFACE ${UOS_BOARD_LIBS})
  add_library (micro-os-plus::board ALIAS board-${PLATFORM_NAME}-interface)
endmacro ()
