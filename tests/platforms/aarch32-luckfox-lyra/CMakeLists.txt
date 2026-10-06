# -----------------------------------------------------------------------------
# Test executables — µOS++ III AArch32 on the Luckfox Lyra B (RK3506).
#
# The Lyra is HARDWARE ONLY: its board.cmake sets no UOS_BOARD_LINKER_QEMU, so
# the port's builder emits one image per test, `<app>-hwd`, and there is no
# emulated suite. This platform reuses that builder, so every test the port has
# appears here, and registers each as `<platform>-<app>-hwd`.
#
# hwd tests are NOT run by a plain `ctest`: they need the board, one test per
# power cycle. They carry the `hwd` label; run the whole emulated set with
# `ctest -LE hwd`, or one test explicitly by name.
# -----------------------------------------------------------------------------

message (VERBOSE "Processing 'tests/platforms/${PLATFORM_NAME}'...")

# -----------------------------------------------------------------------------
include ("cmake/platform-library.cmake")

# The port publishes most board facts as CACHE INTERNAL, but not
# UOS_BOARD_DEVICES; read the board declaration so the builder sees it.
include ("${UOS_AARCH32_DIR}/test/boards/${BOARD}/board.cmake")

# -----------------------------------------------------------------------------
# Build the port's tests by reusing the port's builder. The binary dir ends in
# `test`, which is what the board's hw.sh expects ($BUILD/test/<app>-hwd).
add_subdirectory ("${UOS_AARCH32_DIR}/test" "port-tests/test")

set (_port_bin "${CMAKE_CURRENT_BINARY_DIR}/port-tests")
set (_port_test_dir "${UOS_AARCH32_DIR}/test/luckfox-lyra")
set (_board_hw "${UOS_AARCH32_DIR}/test/boards/${BOARD}/hw.sh")

# -----------------------------------------------------------------------------
# One CTest case per port test: <platform>-<app>-hwd. The test list is the
# port's own -- the directories under test/luckfox-lyra/ that hold sources.
file (GLOB _test_dirs LIST_DIRECTORIES true "${_port_test_dir}/*")
foreach (_dir IN LISTS _test_dirs)
  if (NOT IS_DIRECTORY "${_dir}")
    continue ()
  endif ()
  get_filename_component (_app "${_dir}" NAME)
  if (_app STREQUAL "include" OR _app STREQUAL "src")
    continue ()
  endif ()
  file (GLOB _srcs "${_dir}/*.cpp")
  if (NOT _srcs)
    continue ()
  endif ()

  add_test (
    NAME "${PLATFORM_NAME}-${_app}-hwd"
    COMMAND bash "${_board_hw}" "${_app}" 600
  )
  set_tests_properties (
    "${PLATFORM_NAME}-${_app}-hwd"
    PROPERTIES ENVIRONMENT "BUILD=${_port_bin}" LABELS "hwd" TIMEOUT 1200
  )
endforeach ()

# -----------------------------------------------------------------------------
# The harness suites, on the same board. They supply no main() and no startup
# hooks, so they link micro-os-plus::platform-support. The image lands where
# the board's hw.sh looks for it, <bin>/port-tests/test/<name>-hwd.
#
# The board's shared SMP bring-up (test/luckfox-lyra/src/test-smp-boot.cpp:
# smp_install_boot_threads() and test_wait_secondaries()) is compiled in here
# too. The port's own builder adds test/<board>/src/*.cpp to every test it
# builds, which is how the Pi harness suites get these symbols; this platform
# registers its harness suites itself, so it names the file directly.
function (add_harness_suite _suite _name)
  cmake_parse_arguments (T "" "" "LIBRARIES" ${ARGN})
  add_executable (${_name})
  target_include_directories (
    ${_name} PRIVATE "${_port_test_dir}/include"
  )
  target_sources (
    ${_name} PRIVATE "${_port_test_dir}/src/test-smp-boot.cpp"
  )
  target_link_libraries (
    ${_name}
    PRIVATE micro-os-plus::common-options test::${_suite} micro-os-plus::iii
            micro-os-plus::platform micro-os-plus::platform-support
            ${T_LIBRARIES}
  )
  set_target_properties (
    ${_name} PROPERTIES OUTPUT_NAME "${_name}-hwd" SUFFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${_port_bin}/test"
  )
  add_custom_command (
    TARGET ${_name}
    POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O binary "$<TARGET_FILE:${_name}>"
            "$<TARGET_FILE:${_name}>.bin"
    VERBATIM
  )
  add_test (
    NAME "${PLATFORM_NAME}-${_name}-hwd"
    COMMAND bash "${_board_hw}" "${_name}" 600
  )
  set_tests_properties (
    "${PLATFORM_NAME}-${_name}-hwd"
    PROPERTIES ENVIRONMENT "BUILD=${_port_bin}" LABELS "hwd" TIMEOUT 1200
  )
endfunction ()

add_harness_suite (mutex-stress mutex-stress-test)

# -----------------------------------------------------------------------------
message (STATUS "AArch32 Luckfox Lyra: port tests + harness suites registered")
