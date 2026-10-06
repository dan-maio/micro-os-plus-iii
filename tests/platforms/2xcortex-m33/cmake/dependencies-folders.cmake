# -----------------------------------------------------------------------------
# Folders to add_subdirectory() for this platform.
#
# The Cortex-M port (and, through it, the kernel and devices) is added by
# tests-main.cmake. Here are the portable suites and the generic device.
# -----------------------------------------------------------------------------

set (
  xpack_dependencies_folders
  "${CMAKE_SOURCE_DIR}/sources/rtos-apis"
  "${CMAKE_SOURCE_DIR}/sources/mutex-stress"
  "${CMAKE_SOURCE_DIR}/sources/cmsis-os-validator"
  "${CMAKE_SOURCE_DIR}/sources/fp-switch"
  # The generic QEMU Cortex-M device (vectors, CMSIS).
  "${CMAKE_SOURCE_DIR}/device-qemu-cortexm"
  # The SOURCE_DIR is the `tests` folder.
  "${CMAKE_SOURCE_DIR}/xpacks/@xpacks/arm-cmsis-rtos-validator"
  "${CMAKE_SOURCE_DIR}/xpacks/@xpacks/chan-fatfs"
  # The BINARY_DIR is the `build/<config>` folder.
  "${CMAKE_BINARY_DIR}/xpacks/@xpacks/arm-cmsis"
  "${CMAKE_BINARY_DIR}/xpacks/@xpack-3rd-party/arm-cmsis-core"
)
