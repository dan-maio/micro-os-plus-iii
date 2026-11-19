// The harness suite "mutex-stress-ram" on the Pico (RAM execution).
//
// Reuses the portable mutex-stress suite, linked to execute entirely
// from internal SRAM (no_flash), loaded and run directly via OpenOCD.

// Nothing to compile here: the suite is test::<suite> (tests.cmake's
// board_test_libs), and its verdict is board-tests/cortexm/test-end.cpp, on
// the platform's start-up. The builder makes one application per folder that
// has a source file, and this folder is where this variant's NAME, linker
// script and runner come from.
