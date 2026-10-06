# -----------------------------------------------------------------------------
# Folders to add_subdirectory() for this platform.
#
# The AArch32 port — and, through it, the SMP kernel and the devices package —
# is already added by tests-main.cmake. Listing it here as well would add the
# kernel twice and fail on the duplicate micro-os-plus::iii alias.
#
# The port's own board tests are built directly by CMakeLists.txt from the
# port's test/luckfox-lyra/. The only harness test source this platform needs
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
)

# -----------------------------------------------------------------------------
