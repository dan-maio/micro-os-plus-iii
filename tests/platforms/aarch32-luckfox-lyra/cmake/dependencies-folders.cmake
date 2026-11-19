# -----------------------------------------------------------------------------
# Folders to add_subdirectory() for this platform.
#
# The AArch32 port — and, through it, the SMP kernel and the devices package —
# is already added by tests-main.cmake. Listing it here as well would add the
# kernel twice and fail on the duplicate micro-os-plus::iii alias.
#
# The port's own board tests are built directly by CMakeLists.txt from the
# platforms/aarch32-luckfox-lyra/tests/. The only harness test source this platform needs
# is the portable mutex-stress suite.
# -----------------------------------------------------------------------------

message (
  VERBOSE
  "Including tests/platforms/${PLATFORM_NAME}/cmake/dependencies-folders.cmake..."
)

# -----------------------------------------------------------------------------
set (
  xpack_dependencies_folders
  "${CMAKE_SOURCE_DIR}/sources/mutex-stress"
  "${CMAKE_BINARY_DIR}/xpacks/@micro-os-plus/micro-os-plus-iii-aarch32"
  # The device packages this board's chip needs (xpm link, as the port).
  "${CMAKE_BINARY_DIR}/xpacks/@micro-os-plus/micro-os-plus-iii-devices-storage"
  "${CMAKE_BINARY_DIR}/xpacks/@micro-os-plus/micro-os-plus-iii-devices-rk3506"
  # The Chan FatFs POSIX I/O integration (the portable storage tests).
  "${CMAKE_SOURCE_DIR}/xpacks/@xpacks/chan-fatfs"
)

# -----------------------------------------------------------------------------
