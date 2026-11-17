# -----------------------------------------------------------------------------
# micro-os-plus::board for an AArch32 or AArch64 board platform.
#
#   uos_aarch_board_library (<SoC folder>)
#
# The board facts are the platform's (tests/platforms/<P>/cmake/board.cmake);
# this builds the board target from them: the SoC's include/ and src/ (a
# device package's soc/<chip>/, UOS_BOARD_SOC_DIR), then the board's
# include/ and src/ (in the port's test/boards/<b>/, until the board tests move,
# step 6), the board's defines and flags, and its libraries. This is what the
# port target carried when the port still read the board.
#
# Facts read: UOS_BOARD_SRC_DIR, UOS_BOARD_FLAGS, UOS_BOARD_NCPU,
# UOS_BOARD_CAPS, UOS_BOARD_LINKER_HW, UOS_BOARD_DEFINES, and optionally
# UOS_BOARD_LIBS.
#
# A macro, not a function: the facts it checks and completes stay visible to
# the port's test builder, which the platform adds next.
# -----------------------------------------------------------------------------

include_guard (GLOBAL)

macro (uos_aarch_board_library _soc_dir)
  foreach (_required IN ITEMS UOS_BOARD_SRC_DIR UOS_BOARD_FLAGS UOS_BOARD_NCPU
                              UOS_BOARD_CAPS UOS_BOARD_LINKER_HW
                              UOS_BOARD_DEFINES)
    if (NOT DEFINED ${_required})
      message (FATAL_ERROR
        "platforms/${PLATFORM_NAME}/cmake/board.cmake does not set ${_required}.")
    endif ()
  endforeach ()

  get_filename_component (UOS_BOARD_SRC_DIR "${UOS_BOARD_SRC_DIR}" ABSOLUTE)
  if (NOT IS_DIRECTORY "${_soc_dir}")
    message (FATAL_ERROR "The SoC folder ${_soc_dir} does not exist (is its device package linked?).")
  endif ()

  file (GLOB _board_sources CONFIGURE_DEPENDS
        "${UOS_BOARD_SRC_DIR}/src/*.cpp" "${UOS_BOARD_SRC_DIR}/src/*.S"
        "${UOS_BOARD_SRC_DIR}/src/rtos/*.cpp")
  file (GLOB _soc_sources CONFIGURE_DEPENDS "${_soc_dir}/src/*.cpp")

  add_library (board-${PLATFORM_NAME}-interface INTERFACE)
  target_include_directories (board-${PLATFORM_NAME}-interface INTERFACE
    "${_soc_dir}/include" "${UOS_BOARD_SRC_DIR}/include")
  target_sources (board-${PLATFORM_NAME}-interface INTERFACE
    ${_soc_sources} ${_board_sources})
  target_compile_definitions (board-${PLATFORM_NAME}-interface INTERFACE ${UOS_BOARD_DEFINES})
  target_compile_options    (board-${PLATFORM_NAME}-interface INTERFACE ${UOS_BOARD_FLAGS})
  target_link_options       (board-${PLATFORM_NAME}-interface INTERFACE ${UOS_BOARD_FLAGS})
  target_link_libraries     (board-${PLATFORM_NAME}-interface INTERFACE ${UOS_BOARD_LIBS})
  add_library (micro-os-plus::board ALIAS board-${PLATFORM_NAME}-interface)
endmacro ()
