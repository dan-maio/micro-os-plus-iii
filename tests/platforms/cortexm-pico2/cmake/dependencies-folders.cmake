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

set (xpack_dependencies_folders "${CMAKE_SOURCE_DIR}/sources/mutex-stress"
                                "${CMAKE_SOURCE_DIR}/device-qemu-cortexm"
                                "${CMAKE_BINARY_DIR}/xpacks/@xpacks/arm-cmsis")
