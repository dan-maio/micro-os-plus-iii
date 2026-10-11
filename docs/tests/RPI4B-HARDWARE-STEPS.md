# Raspberry Pi 4 B — running one test on the board, step by step

This page runs one µOS++ test on a Raspberry Pi 4 B (BCM2711, 4× Cortex-A72)
through OpenOCD, by hand, for the 64-bit (AArch64) port. It does exactly what
the test scripts do (`micro-os-plus-iii-aarch64/test/boards/rpi4b/hw.sh`, which
calls `micro-os-plus-iii/test_smpl/run-hw.sh`), written out as plain commands:
reset, load, run, watch, end.

The probe is a Raspberry Pi **debugprobe** (a Pico, firmware 2.0.0) used as a
**CMSIS-DAP v2** adapter in **JTAG** mode, through OpenOCD (xPack 0.12.0-7.1).

## What happens, in short

1. **Reset.** OpenOCD connects, halts core 0, and writes the BCM2711 PM
   watchdog (`0xfe100024` = `0x5a000001`, then `0xfe10001c` = `0x5a000020`).
   The whole SoC resets and boots again from the SD card. OpenOCD loses the
   link and exits.
2. **Wait 15 s** for the firmware to boot and switch the JTAG pins on again.
   Core 0 runs the firmware stub; cores 1–3 wait in the stub's spin-table loop.
3. **Connect and halt core 0** (it stops at EL2, MMU off). Cores 1–3 are not
   halted (see step 6).
4. **Semihosting on**, on all four cores (cores 1–3 while they run).
5. **Load.** `load_image` copies the test's ELF into RAM at `0x80000`.
6. **Run.** Core 0's PC is set to `0x80000` (`_start`) and core 0 is resumed.
   Cores 1–3 go on waiting in the firmware's loop until the kernel writes
   their spin-table slot.
7. **Watch.** The test's console is the UART. The verdict line
   (`RESULT: PASS|FAIL|SKIP`) also goes out through semihosting, where the
   runner sees it.
8. **End.** As soon as the verdict appears, the runner stops OpenOCD. The next
   test starts again at step 1; no power cycle is needed.

## The hardware

| What | Where |
|---|---|
| JTAG | the Pi's GPIO 22–27 (ALT4: TRST, RTCK, TDO, TCK, TDI, TMS), enabled by `enable_jtag_gpio=1` in `config.txt` |
| Probe | Pico debugprobe, USB `2e8a:000c`, CMSIS-DAP v2, firmware 2.0.0 |
| Console | the Pi's PL011 UART (GPIO 14/15), 115200 8N1, here on a CH340 adapter at `/dev/ttyUSB0` |
| SD card | the boot card: firmware, `config.txt` and a `kernel8.img`. The test's `config.txt` is `micro-os-plus-iii-aarch64/test/boards/rpi4b/config.txt` |

The hwd tests that use the SD card (`sd_test`, `smp-mat-sdcard-test`,
`smp-num-test`, `smp-pipeline-test`) mount the card's **existing FAT32 boot
partition** and write only under a `tests/` folder. They never format the card
and never touch the boot files.

## Step 0 — set the paths

```sh
W=/home/dan/Desktop/micro-os-plu-iii-smp-pr-github
OCD_DIR=$HOME/.local/xPacks/@xpack-dev-tools/openocd/0.12.0-7.1/.content
OCD=$OCD_DIR/bin/openocd
SCRIPTS=$OCD_DIR/openocd/scripts
BOARD=$W/micro-os-plu-iii-aarch64/test/boards/rpi4b
CFG=$BOARD/openocd-cmsis-dap-rpi4b.cfg
C=aarch64-rpi4b-cmake-gcc-debug
TESTS=$W/micro-os-plus-iii/tests
ELF_DIR=$TESTS/build/$C/platform-bin/port-tests/test
```

## Step 1 — build the tests

```sh
cd $TESTS
xpm run install --config $C     # first time only
xpm run prepare --config $C
xpm run build   --config $C
```

Each test gives `<app>-hwd` (for the board) and `<app>-qemu`. The `-hwd`
name is a symlink to `<app>-hwd.elf`.

## Step 2 — choose the test

```sh
ls $ELF_DIR/*-hwd
APP=smp-mat-test
ELF=$ELF_DIR/$APP-hwd
```

What matters for the load time is the size of the loadable segment
(`FileSiz` of the `LOAD` line), not the size of the ELF file (that one also
holds the debug information, which is never sent to the board):

```sh
$TESTS/build/$C/xpacks/.bin/aarch64-none-elf-readelf -lW $ELF | grep LOAD
```

The load runs at about **1 KB/s** (see "Why the load is slow" below):

| Test | Loaded bytes | Load |
|---|---|---|
| cmsis-os-validator | 151,640 | ~2.4 min |
| mutex-stress | 94,488 | ~1.5 min |
| rtos-apis | 228,136 | ~3.5 min |
| sd_test | 83,512 | ~1.3 min |
| smp-mat-sdcard-test | 93,736 | ~1.5 min |
| smp-mat-test | 77,608 | ~1.2 min |
| smp-num-test | 91,160 | ~1.4 min |
| smp-pipeline-test | 146,472 | ~2.3 min |
| smp-pro-cons-test | 88,968 | ~1.4 min |
| smp_test0 … smp_test4 | 65,656 … 74,744 | ~1.1 min |

## Step 3 — open the serial console

In a second terminal, and leave it open:

```sh
tio -b 115200 /dev/ttyUSB0
```

The test's whole output appears here once it is started (step 6). On the
board, only the verdict lines go through semihosting.

## Step 4 — reset the board

```sh
pgrep -x openocd && echo "an OpenOCD still holds the probe: pkill -x openocd"

$OCD -s $BOARD -s $SCRIPTS -f $CFG -c init \
  -c "targets bcm2711.cpu0; halt; \
      catch {mww 0xfe100024 0x5a000001}; \
      catch {mww 0xfe10001c 0x5a000020}; \
      shutdown"
```

`0x5a` is the PM password; `0xfe100024` (PM_WDOG) gets a timeout of 1 tick,
and `0xfe10001c` (PM_RSTC) gets "full reset".

The address is the **virtual** one, not `mww phys`. With the MMU and D-cache
on (a test was running), `mww phys` makes OpenOCD clean the caches by set/way
over JTAG first, which never finishes at this link speed.

What a good reset prints: the TAP is found, and then the link drops when the
SoC resets:

```text
Info : JTAG tap: bcm2711.cpu tap/device found: 0x4ba00477 (mfg: 0x23b (ARM Ltd), part: 0xba00, ver: 0x4)
...
Error: Invalid ACK (0) in DAP response
Error: [bcm2711.cpu0] Polling failed, trying to reexamine
```

Those last errors are the proof that the reset happened. If the output has
no `tap/device found` line, or a Tcl `Traceback`, the watchdog was **not**
written: fix that first. The runner checks this and stops with
`watchdog reset FAILED`.

The same reset is in `$BOARD/reset.cfg`:

```sh
$OCD -s $BOARD -s $SCRIPTS -f $BOARD/reset.cfg
```

## Step 5 — wait for the board to boot

```sh
sleep 15
```

## Step 6 — load the test and start it

Write the session's commands to a file (this is what the runner generates, in
`$ELF_DIR/.hw-logs/<app>.cfg`):

```sh
cat > /tmp/run-$APP.cfg <<CFG
echo "--- stage: halt cores 0 ---"
targets bcm2711.cpu0; halt

echo "--- stage: enable semihosting on cores 0 1 2 3 ---"
# Every core that may trap; cores 1-3 are NOT halted for this.
foreach core {0 1 2 3} { targets [format {bcm2711.cpu%d} \$core]; arm semihosting enable }

echo "--- stage: load_image $ELF ---"
targets bcm2711.cpu0
load_image $ELF

echo "--- stage: resume cores 0 at 0x80000 ---"
targets bcm2711.cpu0
reg pc 0x80000
echo "  start PC core 0 = [reg pc]"
resume
CFG
```

Only **core 0** is halted, loaded through and resumed. Cores 1–3 are never
halted: they keep running in the firmware's spin loop until the kernel writes
their spin-table slot. Halting them too looks harmless but is not: a resume of
core 0 restarts the other cores through the CTI (cross-trigger), so OpenOCD
never resumes them itself, and a core it halted at the start later halts with
the registers OpenOCD cached at that first halt. OpenOCD then cannot serve
that core's semihosting call, the core stays halted, and the test stalls.

`0x80000` is `_start`, the ELF's entry point
(`aarch64-none-elf-readelf -h $ELF | grep Entry`).

Then run OpenOCD with it, and **leave it running**: it serves the test's
semihosting calls.

```sh
$OCD -s $BOARD -s $SCRIPTS -f $CFG -c init -f /tmp/run-$APP.cfg 2>&1 | tee /tmp/run-$APP.log
```

What it prints before the load, all normal:

```text
Info : JTAG tap: bcm2711.cpu tap/device found: 0x4ba00477 ...
Error: JTAG-DP STICKY ERROR
Error: Failed to read memory at 0x80410088        (and 0x80510088, 0x80610088, 0x80710088)
bcm2711.cpu0 halted in AArch64 state due to debug-request, current mode: EL2H
cpsr: 0x000003c9 pc: 0x200
```

The `STICKY ERROR` / `Failed to read memory at 0x80n10088` lines come from
examining each A72 (it reads `EDSCR`); OpenOCD recovers by itself. The runner
ignores exactly these (`UOS_HW_IGNORE_ERRORS` in `hw.sh`).

What the config file `$CFG` sets up, besides the board:

| Line | Why |
|---|---|
| `source [find interface/cmsis-dap.cfg]`, `transport select jtag` | the probe, in JTAG mode |
| `source [find board/rpi4b.cfg]` | OpenOCD's BCM2711 target: `bcm2711.cpu0..3`, `bcm2711.dap`, `bcm2711.ap` (not grouped: `USE_SMP` is 0), linked by their CTIs |
| `adapter speed 4000` | 4 MHz TCK (the clock is not what limits the load) |
| `gdb port disabled` | no GDB, OpenOCD only |
| `rpi4b_unwedge` on every `examine-start` | clears a core's stuck debug state (EDSCR ERR/MA, TX/RX full) left by an earlier session |
| `bcm2711.dap memaccess 0` on every `examine-end` | no idle TCKs after each access: the load is 1.74× faster (see below). It has to be set after `init`, and every core's examine resets it to 10, so it is set again after each one |

## Step 7 — watch the result

On the UART (`tio`), the test's own output, ending with the verdict:

```text
RESULT: PASS
```

In the OpenOCD output, only the verdict line arrives (through semihosting).
The runner waits for one of:

| In the OpenOCD output | Meaning |
|---|---|
| `RESULT: PASS` | passed |
| `RESULT: SKIP` | skipped |
| `RESULT: FAIL`, `[FAIL]`, `FAIL:`, `FATAL:` | failed |
| OpenOCD exits | OpenOCD died |
| `Invalid ACK`, `Polling failed`, `Examination failed` | debug link lost |
| any other `Error:` line | OpenOCD error |
| nothing within the time limit (1800 s) | timeout |

## Step 8 — end OpenOCD

When the verdict is there, stop OpenOCD (Ctrl-C, or):

```sh
pkill -x openocd
```

Stopping it while it is talking to the probe prints
`Error: error handling USB events: System call interrupted (perhaps due to signal)`:
that is the stop itself, not a problem.

The board is now running (or stopped in) the finished test. The next test
starts again at step 4: the watchdog reset puts the board back in a clean
state, so there is **no power cycle** between tests.

## The same, with the scripts

One test, with its result in CTest (reset, wait, load, run, verdict, end):

```sh
cd $TESTS
export PATH=$PWD/build/$C/xpacks/.bin:$PATH
ctest --test-dir build/$C -R '^aarch64-rpi4b-smp-mat-test-hwd$' -V
```

Or through xpm, which builds first:

```sh
xpm run test-smp-mat-test-hwd --config $C
```

All hwd tests, one after another (each one resets the board first):

```sh
xpm run test-hwd --config $C          # prepare + build, then ctest -V -L hwd
```

The port's script directly, without CTest:

```sh
$BOARD/hw.sh list                      # what is built, with time limits
BUILD=$TESTS/build/$C/platform-bin/port-tests $BOARD/hw.sh smp-mat-test 1800
```

Files the runner leaves in `$ELF_DIR/.hw-logs/`:

| File | What |
|---|---|
| `<app>.reset.log` | OpenOCD output of the reset session (step 4) |
| `<app>.cfg` | the commands of step 6 |
| `<app>.log` | OpenOCD output of the test session (steps 6–7) |

Settings (environment variables) the scripts take:

| Variable | Default | What |
|---|---|---|
| `UOS_HW_RESET_WAIT` | 15 | seconds between the watchdog reset and the connect |
| `UOS_HW_CORES` | `0` | cores that are halted, loaded through and resumed |
| `UOS_HW_SEMIHOST_CORES` | `0 1 2 3` | cores with semihosting enabled (without halting them) |
| `UOS_HW_ADAPTER_KHZ` | (config: 4000) | JTAG clock, set after `init` |
| `UOS_HW_PRELOAD` | the two watchdog writes | the reset commands of step 4 |
| `UOS_HW_IGNORE_ERRORS` | `JTAG-DP STICKY ERROR\|Failed to read memory at 0x80[4-7][0-9a-f]+$` | `Error:` lines that do not end the run |
| `OPENOCD` | newest xPack OpenOCD | the OpenOCD binary |

## From VS Code

The VS Code project (`RPI4B/64/rpi4b`) uses the same steps with its own
config, `rpi4b-cmsis-dap.cfg` (same `rpi4b_unwedge` and `memaccess 0` events):

```sh
./reset-board.sh 30      # step 4 + a 30 s wait (step 5)
```

and then the "Debug Pi 4B" launch does steps 6–7 through GDB
(`monitor halt`, `load`, `monitor arm semihosting enable`).

## Why the load is slow

Measured on this setup, with OpenOCD's packet-level log (`-d4`):

* OpenOCD's CMSIS-DAP driver, in **JTAG** mode, sends raw
  `DAP_JTAG_Sequence` commands and encodes every TMS bit and every idle clock
  as its own 2-byte entry. One 32-bit access (a 35-bit DR scan plus idle
  clocks) fills a whole 64-byte USB packet: 4 bytes of data per packet.
* Each packet waits for its answer: **8.4 ms** per round trip on average
  (full-speed USB, the probe behind a hub).
* So the TCK frequency hardly matters: about 0.6 KB/s at any clock.

With `bcm2711.dap memaccess 0` (10 idle clocks per access removed), a 4 KB
load went from 6.7 s to 3.9 s (1.74×) and read back identical. The rest of
the cost is the round trip: the probe on a USB port without a hub, or a newer
debugprobe firmware, are the next things to try.

## If something goes wrong

| Symptom | Cause, fix |
|---|---|
| `LIBUSB_ERROR_BUSY`, or the probe is not found | another OpenOCD holds it: `pkill -x openocd` |
| the reset prints `The 'bcm2711.dap memaccess' command must be used after 'init'` | `memaccess` written as a plain line in the config; it must be in the `examine-end` events |
| the reset session shows no `tap/device found` | no JTAG: the board is off, or the firmware has not enabled the pins (`enable_jtag_gpio=1`), or it is still booting (wait longer: `UOS_HW_RESET_WAIT=30`) |
| `Error: [bcm2711.cpu1] not halted` at the resume, then OpenOCD exits | a script that halted cores 1–3 and resumes them after core 0: the core 0 resume already restarted them through the CTI. Halt and resume core 0 only (step 6) |
| the output stops, and a core 1–3 shows `halted ... due to breakpoint`, `pc: 0x80`, EL1, registers equal to its first halt | that core was halted at the start of the session: OpenOCD later reads its stale cached registers and cannot serve its semihosting call. Do not halt cores 1–3 (`UOS_HW_CORES=0`) |
| the run log shows `RESULT: ` without `PASS`/`FAIL` | the verdict was printed in pieces; the board's `uart.hpp` must mirror the whole verdict line (`mirror_verdict`) |
| nothing on the UART for minutes after the halt | the load is still running (see the table in step 2) |
| `mww phys` never ends | use the virtual address (step 4) |
