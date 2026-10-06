# fp-switch

This test checks that the FPU registers (s0-s31 and the FPSCR flags)
survive a preemptive context switch, and on SMP a move to another core.
