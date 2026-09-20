# -----------------------------------------------------------------------------
# micro-os-plus-iii-smp — the common half of the unified µOS++ III SMP project.
#
# This repository holds everything that is *common* (see the design spec,
# Section 1.1): the kernel, the device layer, and the shared test sources.
# Architecture-specific code lives in its own repository per D8/D9, and each
# architecture repo consumes this one as a Git submodule (D10):
#
#   add_subdirectory (micro-os-plus-iii-smp)
#   target_link_libraries (my-app PRIVATE micro-os-plus::iii)
#
# It is therefore designed to work both standalone and as a subproject.
# -----------------------------------------------------------------------------

cmake_minimum_required (VERSION 3.20)

project (
  micro-os-plus-iii-smp
  DESCRIPTION "µOS++ III SMP — common kernel, devices and tests"
  LANGUAGES C CXX ASM
)

# True only when this repo is the top-level build, false when an architecture
# repo added it as a submodule.
if (CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  set (UOS_SMP_STANDALONE TRUE)
else ()
  set (UOS_SMP_STANDALONE FALSE)
endif ()

# Absolute paths are forbidden in scripts and build files; consumers refer to
# the shared trees through these variables instead.
set (UOS_SMP_ROOT        "${CMAKE_CURRENT_SOURCE_DIR}" CACHE INTERNAL "")
set (UOS_TEST_COMMON     "${CMAKE_CURRENT_SOURCE_DIR}/test/common" CACHE INTERNAL "")
set (UOS_CMAKE_DIR       "${CMAKE_CURRENT_SOURCE_DIR}/cmake" CACHE INTERNAL "")
set (UOS_TOOLCHAINS_DIR  "${CMAKE_CURRENT_SOURCE_DIR}/cmake/toolchains" CACHE INTERNAL "")

# The shared application helper, available to every architecture repo.
include ("${CMAKE_CURRENT_SOURCE_DIR}/cmake/uos-app.cmake")

# -----------------------------------------------------------------------------
# The kernel. Exports micro-os-plus::iii.
#
# Note: the kernel does not compile on its own. os-decls.h includes
# <cmsis-plus/rtos/port/os-decls.h>, which an architecture repo supplies. This
# subdirectory therefore defines an INTERFACE library; the sources are compiled
# by whichever application links it, against that application's port.
add_subdirectory (micro-os-plus-iii)

# -----------------------------------------------------------------------------
# The common device layer. Exports micro-os-plus::devices.
# Added in step 2, when the rpi slice extracts it.
if (EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/devices/CMakeLists.txt")
  add_subdirectory (devices)
endif ()

# -----------------------------------------------------------------------------
# Tests are built by the architecture repos, which know their toolchain and
# linker script. Standalone, there is nothing to build here.
if (UOS_SMP_STANDALONE AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/test/CMakeLists.txt")
  add_subdirectory (test)
endif ()

# -----------------------------------------------------------------------------
message (STATUS "µOS++ III SMP common: kernel=micro-os-plus::iii standalone=${UOS_SMP_STANDALONE}")
