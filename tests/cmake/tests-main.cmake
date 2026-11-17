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

# TEMPORARY (until the ports are xpm dependencies, plugged in with `xpm link`):
# an architecture port listed as build/<config>/xpacks/@micro-os-plus/<port>
# is taken from its working copy in this workspace, next to the kernel, unless
# that entry already leads there. (An `xpm install` may have put the released
# single-core package there, which is not the port under test.)
# UOS_<PORT>_DIR names the folder used; the platforms of the ports read it.
get_filename_component (_uos_workspace "${CMAKE_SOURCE_DIR}/../.." REALPATH)
set (_uos_deps "")
foreach (_dep IN LISTS xpack_dependencies_folders)
  string (REGEX MATCH "/xpacks/@micro-os-plus/(micro-os-plus-iii-[a-z0-9-]+)$" _m "${_dep}")
  if (_m)
    set (_port "${CMAKE_MATCH_1}")
    get_filename_component (_real "${_dep}" REALPATH)
    if (NOT _real STREQUAL "${_uos_workspace}/${_port}")
      set (_dep "${_uos_workspace}/${_port}")
    endif ()
    string (REPLACE "micro-os-plus-iii-" "" _var "${_port}")
    string (TOUPPER "${_var}" _var)
    string (REPLACE "-" "_" _var "${_var}")
    set (UOS_${_var}_DIR "${_dep}")
    message (STATUS "µOS++ III ${_port}: ${_dep}")
  endif ()
  list (APPEND _uos_deps "${_dep}")
endforeach ()
set (xpack_dependencies_folders "${_uos_deps}")

# Iterate the platform dependencies and `add_subdirectory()`.
xpack_add_dependencies_subdirectories (
  "${xpack_dependencies_folders}" "xpacks-bin"
)

# -----------------------------------------------------------------------------

# Add the project library, defined one level above.
message (VERBOSE "Adding top library...")
add_subdirectory (".." "top-bin")

# -----------------------------------------------------------------------------
# Platform specifics.

# Add the platform specific targets and tests. For consistency, the binaries are
# created in the `platform-bin` folder.
add_subdirectory ("platforms/${PLATFORM_NAME}" "platform-bin")

# -----------------------------------------------------------------------------
