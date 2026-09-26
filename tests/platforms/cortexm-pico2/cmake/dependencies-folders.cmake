# -----------------------------------------------------------------------------
# Folders to add_subdirectory() for this platform.
#
# The Cortex-M port (and, through it, the kernel and the devices package) is
# added by tests-main.cmake. Only the portable suites are listed here.
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/dependencies-folders.cmake..."
)

set (
  xpack_dependencies_folders
  # The portable harness suites. Their sources become test::<suite>, which the
  # port's board_test_libs() names for the three placeholder applications under
  # test/pico2/.
  "${CMAKE_SOURCE_DIR}/sources/rtos-apis"
  "${CMAKE_SOURCE_DIR}/sources/mutex-stress"
  "${CMAKE_SOURCE_DIR}/sources/cmsis-os-validator"
  "${CMAKE_SOURCE_DIR}/sources/fp-switch"
  # The generic QEMU Cortex-M device the `qemu` images link instead of the
  # board.
  "${CMAKE_SOURCE_DIR}/device-qemu-cortexm"
  # The SOURCE_DIR is the `tests` folder.
  "${CMAKE_SOURCE_DIR}/xpacks/@xpacks/arm-cmsis-rtos-validator"
  "${CMAKE_SOURCE_DIR}/xpacks/@xpacks/chan-fatfs"
  # The BINARY_DIR is the `build/<config>` folder.
  "${CMAKE_BINARY_DIR}/xpacks/@xpacks/arm-cmsis"
)
