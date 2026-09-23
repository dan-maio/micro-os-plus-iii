# -----------------------------------------------------------------------------
# Folders to add_subdirectory() for this platform.
#
# The AArch32 port — and, through it, the SMP kernel and the devices package —
# is already added by tests-main.cmake. Listing it here as well would add the
# kernel twice and fail on the duplicate micro-os-plus::iii alias. Only the
# test sources and portable xPacks are listed here.
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/dependencies-folders.cmake..."
)

# -----------------------------------------------------------------------------
set (
  xpack_dependencies_folders
  "${CMAKE_SOURCE_DIR}/sources/mutex-stress"
  "${CMAKE_SOURCE_DIR}/sources/rtos-apis"
  "${CMAKE_SOURCE_DIR}/sources/cmsis-os-validator"
  # The CMSIS-OS validator, needed only when cmsis-os-validator is built.
  "${CMAKE_SOURCE_DIR}/xpacks/@xpacks/arm-cmsis-rtos-validator"
  # The Chan FatFs POSIX integration rtos-apis' test-chan-fatfs.cpp needs.
  "${CMAKE_SOURCE_DIR}/xpacks/@xpacks/chan-fatfs"
)

# -----------------------------------------------------------------------------
