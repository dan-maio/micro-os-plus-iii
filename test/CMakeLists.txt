# -----------------------------------------------------------------------------
# Test support shared by every architecture project.
#
# The application sources under common/<app>/ are ISA-neutral: each one exists
# once and is compiled by every port that can run it. What the applications
# still need from a port they take through headers the port supplies
# (uart.hpp, led.hpp, smp.hpp, timer_arm.hpp, ...), never through inline
# assembly of their own.
#
# Exports: micro-os-plus::test-common
# -----------------------------------------------------------------------------

add_library (micro-os-plus-iii-test-common-interface INTERFACE)

target_include_directories (
  micro-os-plus-iii-test-common-interface INTERFACE "common/include"
)

# Secondary-core bring-up: idle stacks, the idle body and
# smp_install_boot_threads(), which every SMP test used to carry its own copy
# of. Linked into every test application, single-core ones included -- with
# OS_NCPU == 1 the install loop simply has nothing to do.
target_sources (
  micro-os-plus-iii-test-common-interface
  INTERFACE common/src/test-smp-boot.cpp
)

add_library (micro-os-plus::test-common ALIAS micro-os-plus-iii-test-common-interface)

message (STATUS "µOS++ III SMP tests: micro-os-plus::test-common")
