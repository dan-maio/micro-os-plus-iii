# -----------------------------------------------------------------------------
# uos-app.cmake — the single application-declaration helper.
#
# D7: the predecessor repository declared each application with its own
# Makefile, 214 of them, differing by roughly 48 lines of boilerplate. This
# file replaces that boilerplate, so a per-application CMakeLists.txt states
# only what is genuinely specific to it.
#
# Usage:
#
#   uos_add_app (smp_test0
#     SOURCES       ${UOS_TEST_COMMON}/smp_test0/main.cpp
#     PORT          micro-os-plus::port-aarch32
#     LINKER_SCRIPT ${CMAKE_CURRENT_SOURCE_DIR}/linker.ld
#     NCPU          4
#   )
# -----------------------------------------------------------------------------

include_guard (GLOBAL)

function (uos_add_app _name)
  set (_opts)
  set (_one  LINKER_SCRIPT PORT NCPU OUTPUT_NAME)
  set (_many SOURCES INCLUDES DEFINES OPTIONS LIBRARIES)
  cmake_parse_arguments (A "${_opts}" "${_one}" "${_many}" ${ARGN})

  if (NOT A_SOURCES)
    message (FATAL_ERROR "uos_add_app(${_name}): SOURCES is required")
  endif ()

  add_executable (${_name} ${A_SOURCES})

  # The kernel is always linked; the port is whatever architecture repo is
  # driving this build. Devices are optional -- not every application uses them.
  target_link_libraries (${_name} PRIVATE micro-os-plus::iii)
  if (A_PORT)
    target_link_libraries (${_name} PRIVATE ${A_PORT})
  endif ()
  if (TARGET micro-os-plus::devices)
    target_link_libraries (${_name} PRIVATE micro-os-plus::devices)
  endif ()
  if (A_LIBRARIES)
    target_link_libraries (${_name} PRIVATE ${A_LIBRARIES})
  endif ()

  if (A_INCLUDES)
    target_include_directories (${_name} PRIVATE ${A_INCLUDES})
  endif ()
  if (A_DEFINES)
    target_compile_definitions (${_name} PRIVATE ${A_DEFINES})
  endif ()
  if (A_OPTIONS)
    target_compile_options (${_name} PRIVATE ${A_OPTIONS})
  endif ()

  # OS_NCPU is how a board selects its CPU count from a shared port (D11:
  # the STM32 boards build the SMP cortexm port at OS_NCPU=1).
  if (A_NCPU)
    target_compile_definitions (${_name} PRIVATE OS_NCPU=${A_NCPU})
    if (A_NCPU GREATER 1)
      target_compile_definitions (${_name} PRIVATE OS_USE_SMP_SCHEDULER=1)
    endif ()
  endif ()

  if (A_OUTPUT_NAME)
    set_target_properties (${_name} PROPERTIES OUTPUT_NAME "${A_OUTPUT_NAME}")
  endif ()

  if (A_LINKER_SCRIPT)
    target_link_options (${_name} PRIVATE "-T${A_LINKER_SCRIPT}")
    set_target_properties (${_name} PROPERTIES LINK_DEPENDS "${A_LINKER_SCRIPT}")
  endif ()

  # Bare-metal targets want a raw image and a listing beside the ELF.
  if (CMAKE_SYSTEM_NAME STREQUAL "Generic")
    add_custom_command (
      TARGET ${_name} POST_BUILD
      COMMAND "${CMAKE_OBJCOPY}" -O binary "$<TARGET_FILE:${_name}>"
              "$<TARGET_FILE_DIR:${_name}>/${_name}.bin"
      COMMAND "${CMAKE_SIZE}" "$<TARGET_FILE:${_name}>"
      VERBATIM
    )
  endif ()
endfunction ()

# -----------------------------------------------------------------------------
# uos_add_test_app (<name> [APP <dir>] <uos_add_app arguments...>)
#
# Declares one of the shared test applications from test/common/. The sources
# come from test/common/<APP>/ -- there is exactly one copy of each test in the
# workspace, and every architecture project compiles that same copy.
#
# APP defaults to <name>, so a board that builds the test under its own target
# name passes APP explicitly:
#
#   uos_add_test_app (rpi-smp_test1 APP smp_test1 NCPU 4 PORT rpi-aarch64 ...)
#
# Any extra SOURCES/DEFINES/LIBRARIES are appended to the shared ones.
# -----------------------------------------------------------------------------
function (uos_add_test_app _name)
  cmake_parse_arguments (T "" "APP" "SOURCES" ${ARGN})

  if (NOT T_APP)
    set (T_APP "${_name}")
  endif ()

  set (_dir "${UOS_TEST_COMMON}/${T_APP}")
  if (NOT IS_DIRECTORY "${_dir}")
    message (FATAL_ERROR "uos_add_test_app: no shared test application '${T_APP}' in ${UOS_TEST_COMMON}")
  endif ()

  # Every .cpp in the application directory, so a test that grew a second
  # translation unit (usb_test/sink.cpp) needs no separate declaration.
  file (GLOB _common_sources CONFIGURE_DEPENDS "${_dir}/*.cpp")
  if (NOT _common_sources)
    message (FATAL_ERROR "uos_add_test_app: no sources in ${_dir}")
  endif ()

  uos_add_app (
    ${_name}
    SOURCES ${_common_sources} ${T_SOURCES}
    LIBRARIES micro-os-plus::test-common
    ${T_UNPARSED_ARGUMENTS}
  )
endfunction ()
