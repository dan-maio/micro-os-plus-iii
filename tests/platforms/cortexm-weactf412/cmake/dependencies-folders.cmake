# -----------------------------------------------------------------------------
# Folders to add_subdirectory() for this platform.
#
# The Cortex-M port (and, through it, the kernel and the devices package) is
# added by tests-main.cmake. This platform is hardware-only, so there is no
# generic QEMU device to add either.
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/dependencies-folders.cmake..."
)

set (
  xpack_dependencies_folders
  # The portable harness suites. Their sources become test::<suite>, which the
  # port's board_test_libs() names for the three placeholder applications under
  # test/weactf412/ (built with the kernel's SMP scheduler at OS_NCPU=1).
  "${CMAKE_SOURCE_DIR}/sources/rtos-apis"
  "${CMAKE_SOURCE_DIR}/sources/mutex-stress"
  "${CMAKE_SOURCE_DIR}/sources/cmsis-os-validator"
  # The SOURCE_DIR is the `tests` folder.
  "${CMAKE_SOURCE_DIR}/xpacks/@xpacks/arm-cmsis-rtos-validator"
  "${CMAKE_SOURCE_DIR}/xpacks/@xpacks/chan-fatfs"
  # The BINARY_DIR is the `build/<config>` folder.
  "${CMAKE_BINARY_DIR}/xpacks/@xpacks/arm-cmsis"
)
