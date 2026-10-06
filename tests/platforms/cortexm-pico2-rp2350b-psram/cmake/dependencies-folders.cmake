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
  "${CMAKE_SOURCE_DIR}/sources/mutex-stress"
  # The one harness suite this board runs; its sources become test::fp-switch,
  # which the port's board_test_libs() names for test/pico2-rp2350b-psram/
  # fp-switch/.
  "${CMAKE_SOURCE_DIR}/sources/fp-switch"
  "${CMAKE_SOURCE_DIR}/device-qemu-cortexm"
  "${CMAKE_BINARY_DIR}/xpacks/@xpacks/arm-cmsis"
)
