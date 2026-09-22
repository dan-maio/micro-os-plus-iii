# -----------------------------------------------------------------------------
# DO NOT EDIT! Automatically generated from build-helper/templates.
#
# This file is part of the µOS++ project (https://micro-os-plus.github.io/).
# Copyright (c) 2022-2025 Liviu Ionescu. All rights reserved.
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose is hereby granted, under the terms of the MIT license.
#
# If a copy of the license was not distributed with this file, it can be
# obtained from https://opensource.org/licenses/mit.
#
# -----------------------------------------------------------------------------

# Generate the compile_commands.json file to feed the indexer. Highly
# recommended, to help IDEs construct the index.
set (CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Enable this to see the dependency graph. set_property(GLOBAL PROPERTY
# GLOBAL_DEPENDS_DEBUG_MODE 1)

# -----------------------------------------------------------------------------

# Bare-metal executables have the .elf extension.
if (CMAKE_SYSTEM_NAME STREQUAL "Generic")
  set (CMAKE_EXECUTABLE_SUFFIX ".elf")
endif ()

# -----------------------------------------------------------------------------
# Non-target specific definitions.

# The globals must be included in this scope, before creating any targets. The
# compile options, symbols and include folders apply to all compiled sources,
# from all libraries.
if ("${CMAKE_HOST_SYSTEM_NAME}" STREQUAL "Windows")
  set (extension ".cmd")
endif ()

# Define `micro-os-plus::common-options` with the compile & link options common
# to all platforms.
include ("cmake/common-options.cmake")

# Platform specific definitions.
include ("platforms/${PLATFORM_NAME}/cmake/definitions.cmake")

# Set `xpack_dependencies_folders` with the platform specific dependencies.
include ("platforms/${PLATFORM_NAME}/cmake/dependencies-folders.cmake")

# Iterate the platform dependencies and `add_subdirectory()`.
xpack_add_dependencies_subdirectories (
  "${xpack_dependencies_folders}" "xpacks-bin"
)

# -----------------------------------------------------------------------------

# The library under test is the architecture port, which itself adds the SMP
# kernel (micro-os-plus::iii) and the devices package. Do NOT add the kernel
# separately: both the kernel and the port define micro-os-plus::iii, and
# adding it twice fails on the duplicate alias. The port is chosen from the
# platform name.
message (VERBOSE "Selecting the library under test for ${PLATFORM_NAME}...")
set (UOS_AARCH32_DIR "${CMAKE_SOURCE_DIR}/../../micro-os-plus-iii-aarch32.git"
     CACHE PATH "µOS++ III AArch32 port working copy")
set (UOS_AARCH64_DIR "${CMAKE_SOURCE_DIR}/../../micro-os-plus-iii-aarch64.git"
     CACHE PATH "µOS++ III AArch64 port working copy")

if (PLATFORM_NAME MATCHES "^aarch32")
  message (VERBOSE "Adding the AArch32 port (brings iii + devices)...")
  if (NOT EXISTS "${UOS_AARCH32_DIR}/CMakeLists.txt")
    message (FATAL_ERROR "Cannot find the AArch32 port at ${UOS_AARCH32_DIR}")
  endif ()
  add_subdirectory ("${UOS_AARCH32_DIR}" "port-bin")
elseif (PLATFORM_NAME MATCHES "^aarch64")
  message (VERBOSE "Adding the AArch64 port (brings iii + devices)...")
  if (NOT EXISTS "${UOS_AARCH64_DIR}/CMakeLists.txt")
    message (FATAL_ERROR "Cannot find the AArch64 port at ${UOS_AARCH64_DIR}")
  endif ()
  add_subdirectory ("${UOS_AARCH64_DIR}" "port-bin")
else ()
  # Fallback: the plain kernel, one level above (upstream behaviour).
  message (VERBOSE "Adding the top library...")
  add_subdirectory (".." "top-bin")
endif ()

# -----------------------------------------------------------------------------
# Platform specifics.

# Add the platform specific targets and tests. For consistency, the binaries are
# created in the `platform-bin` folder.
add_subdirectory ("platforms/${PLATFORM_NAME}" "platform-bin")

# -----------------------------------------------------------------------------
