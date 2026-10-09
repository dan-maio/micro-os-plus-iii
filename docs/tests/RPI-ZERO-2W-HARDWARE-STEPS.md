# Raspberry Pi Zero 2 W — running one test on the board, step by step

This page runs one µOS++ test on a Raspberry Pi Zero 2 W through OpenOCD,
by hand, for the 32-bit (AArch32) and the 64-bit (AArch64) port. It does
the same thing the test scripts (`hw.sh`, `run-hw.sh`) do, written out as
plain commands.

The probe is a SEGGER J-Link, used through OpenOCD. (An Olimex
ARM-USB-OCD also works; see the end of the page.)

## What happens, in short

1. The board is reset through its watchdog, and boots again.
2. OpenOCD stops the four CPU cores.
3. OpenOCD turns semihosting on, so the test can print through the probe.
4. OpenOCD copies the test program into the board's RAM.
5. AArch32: OpenOCD clears a small table the cores use to start each
   other, then starts the four cores at the program's first instruction.
   AArch64: OpenOCD starts only core 0; cores 1–3 stay in the firmware's
   waiting loop until the test itself releases them (no table to clear).
6. The test runs and prints `RESULT: PASS` (or `FAIL`).

One test per power cycle: before the next test, unplug the board's power
and plug it in again. (On AArch64 the 14 tests also passed back to back
with only the step-4 watchdog reset between them.)

## Step 0 — set the paths

```bash
WORK=/home/dan/Desktop/tmp_tests          # the folder that holds the repositories
K=$WORK/micro-os-plus-iii                 # kernel
A32=$WORK/micro-os-plus-iii-aarch32       # 32-bit port
A64=$WORK/micro-os-plus-iii-aarch64       # 64-bit port
BUILD=$K/tests/build
OPENOCD=$HOME/.local/xPacks/@xpack-dev-tools/openocd/0.12.0-7.1/.content/bin/openocd
TC32=$HOME/.local/xPacks/@xpack-dev-tools/arm-none-eabi-gcc/15.2.1-1.1.1/.content/bin
TC64=$HOME/.local/xPacks/@xpack-dev-tools/aarch64-none-elf-gcc/15.2.1-1.1.1/.content/bin
```

## Step 1 — build the tests

```bash
cd $K/tests
xpm install     --config aarch32-rpi-zero-2w-cmake-gcc-debug
xpm run prepare --config aarch32-rpi-zero-2w-cmake-gcc-debug
xpm run build   --config aarch32-rpi-zero-2w-cmake-gcc-debug
```

For the 64-bit port, write `aarch64` instead of `aarch32`.

The programs for the board are the files ending in `-hwd`, in
`$BUILD/aarch32-rpi-zero-2w-cmake-gcc-debug/platform-bin/port-tests/test/`
(or `aarch64-...`). The tests are: `smp_test0` … `smp_test4`,
`smp-mat-test`, `smp-mat-sdcard-test`, `smp-num-test`, `smp-pipeline-test`,
`smp-pro-cons-test`, `sd_test`, `usb_test`, `cmsis-os-validator`,
`mutex-stress`, `rtos-apis`.

---

## AArch32 (32-bit port)

### Step 2 — choose the test and read two addresses from it

```bash
D=$BUILD/aarch32-rpi-zero-2w-cmake-gcc-debug/platform-bin/port-tests/test
CFG=$A32/test/boards/rpi-zero-2w
ELF=$D/smp_test0-hwd

$TC32/arm-none-eabi-readelf -h $ELF | grep 'Entry point'
$TC32/arm-none-eabi-nm $ELF | grep ' __smp_spin$'
```

- **Entry point** is where the program starts. For this port it is always
  `0x1003c`.
- **`__smp_spin`** is a table of 4 numbers (4 bytes each). A waiting core
  reads its start address from it. Its address changes from build to build,
  so read it every time. Example output: `0002cfb0 B __smp_spin`.

Write the 4 addresses of the table (the address, then +4, +8, +12):

```bash
S=0x$($TC32/arm-none-eabi-nm $ELF | awk '$3 == "__smp_spin" {print $1}')
S0=$(printf 0x%x $((S)))
S1=$(printf 0x%x $((S + 4)))
S2=$(printf 0x%x $((S + 8)))
S3=$(printf 0x%x $((S + 12)))
echo $S0 $S1 $S2 $S3          # e.g. 0x2cfb0 0x2cfb4 0x2cfb8 0x2cfbc
```

### Step 3 — open the serial console (optional)

In another terminal:

```bash
tio -b 115200 /dev/ttyACM0
```

OpenOCD never uses this port, so it can stay open all the time.

### Step 4 — reset the board

```bash
$OPENOCD -s $CFG -f $CFG/openocd-jlink-rpi3.cfg \
  -c "targets bcm2837.cpu0" \
  -c "halt" \
  -c "mww 0x3f100024 0x5a000001" \
  -c "mww 0x3f10001c 0x5a000020" \
  -c "shutdown"
```

- `-s $CFG -f $CFG/openocd-jlink-rpi3.cfg` — the J-Link and the board
  description (4 Cortex-A53 cores, JTAG at 1000 kHz). This file also
  connects to the board and stops core 0 by itself.
- `targets bcm2837.cpu0` — talk to core 0.
- `halt` — stop core 0.
- `mww 0x3f100024 0x5a000001` — set the watchdog timer to (almost) zero.
- `mww 0x3f10001c 0x5a000020` — tell the watchdog to reset the chip when
  it expires. The board reboots.
- `shutdown` — OpenOCD exits.

### Step 5 — wait for the board to boot

```bash
sleep 12
```

### Step 6 — load the test and start it

This is one OpenOCD command. The options run in order, from top to bottom.

```bash
$OPENOCD -s $CFG -f $CFG/openocd-jlink-rpi3.cfg \
  -c "targets bcm2837.cpu0" -c "halt" \
  -c "targets bcm2837.cpu1" -c "halt" \
  -c "targets bcm2837.cpu2" -c "halt" \
  -c "targets bcm2837.cpu3" -c "halt" \
  -c "targets bcm2837.cpu0" -c "arm semihosting enable" \
  -c "targets bcm2837.cpu1" -c "arm semihosting enable" \
  -c "targets bcm2837.cpu2" -c "arm semihosting enable" \
  -c "targets bcm2837.cpu3" -c "arm semihosting enable" \
  -c "targets bcm2837.cpu0" -c "load_image $ELF" \
  -c "mww $S0 0" -c "mww $S1 0" -c "mww $S2 0" -c "mww $S3 0" \
  -c "targets bcm2837.cpu0" -c "reg cpsr 0x600001da" -c "resume 0x1003c" \
  -c "targets bcm2837.cpu1" -c "reg cpsr 0x600001da" -c "resume 0x1003c" \
  -c "targets bcm2837.cpu2" -c "reg cpsr 0x600001da" -c "resume 0x1003c" \
  -c "targets bcm2837.cpu3" -c "reg cpsr 0x600001da" -c "resume 0x1003c"
```

What each part does:

1. **Stop the 4 cores** (`targets` … `halt`, for cores 0–3). A core still
   running old code could overwrite RAM while the new program is copied.
2. **Turn semihosting on for each core.** The test prints by stopping the
   core for a moment; OpenOCD sees the stop, prints the text and lets the
   core go on. Every core needs it, because any core can print.
3. **Copy the program into RAM** (`load_image $ELF`, through core 0).
4. **Clear the `__smp_spin` table** (the 4 `mww … 0`). A waiting core must
   not find an old start address there from the previous test.
5. **Start each core** at the program's entry:
   - `reg cpsr 0x600001da` — put the core in 32-bit mode: the low bits
     `0x1a` select HYP (hypervisor) mode, and `0x1c0` masks the aborts,
     IRQs and FIQs;
   - `resume 0x1003c` — run from the entry point.

   Core 0 starts the system; cores 1–3 wait until the kernel releases them.

### Step 7 — watch the result

The test's messages appear in this OpenOCD window. It passed when it prints
`RESULT: PASS`. Then press **Ctrl-C** to stop OpenOCD.

How long to wait at most: `smp_test0`–`smp_test3` 120 s; `smp_test4`,
`usb_test`, `cmsis-os-validator`, `mutex-stress`, `rtos-apis` 300 s;
`sd_test` 450 s; `smp-num-test`, `smp-pipeline-test`, `smp-pro-cons-test`
600 s; `smp-mat-test`, `smp-mat-sdcard-test` 900 s. Printing is slow over
JTAG, so the chatty tests take long.

### Step 8 — power-cycle the board

Unplug the power and plug it in again before the next test, then go back to
step 2.

---

## AArch64 (64-bit port)

The same steps; only these things change:

| | AArch32 | AArch64 |
|---|---|---|
| Config folder `CFG` | `$A32/test/boards/rpi-zero-2w` | `$A64/test/boards/rpi-zero-2w` |
| Tools | `$TC32/arm-none-eabi-…` | `$TC64/aarch64-none-elf-…` |
| Entry point | `0x1003c` | `0x80000` |
| `__smp_spin` | read with `nm`, 4 writes | not used (nothing to read or write) |
| Connect | the config file does it | add `-c init` after the config file |
| Start the cores | all 4: `reg cpsr …` then `resume 0x1003c` | core 0: `reg pc 0x80000`, `resume`; cores 1–3: `resume` where they are |
| JTAG speed | 1000 kHz | 4000 kHz |

### Why AArch64 needs no `__smp_spin` writes

After the reset in step 4 the firmware holds cores 1–3 in its own waiting
loop (they are stopped at `pc=0x7c`, EL2, MMU off, and their release words at
`0xd8`…`0xf0` are 0). Step 6 starts only core 0. Cores 1–3 are let go
exactly where they were, so they keep waiting in the firmware. When the
kernel is ready, the test releases them itself (`release_one()` in
`test/boards/rpi-zero-2w/src/smp.cpp`): it first writes their entry into
`__smp_spin`, then writes `_start` into their release word. So a core never
reads `__smp_spin` before the test has written it, and its old content does
not matter.

This needs an SD card whose kernel does **not** start cores 1–3 (for example
`test/boards/rpi-zero-2w/hw-park/`). Check it once, after a step-4 reset:

```bash
$OPENOCD -s $CFG -f $CFG/openocd-jlink-rpi3.cfg -c "init" \
  -c "targets bcm2837.cpu1" -c "halt" -c "reg pc" -c "resume" \
  -c "shutdown"
```

`pc` must be `0x7c` (and the same for `cpu2`, `cpu3`). If a core is
anywhere else, the SD card's kernel has started it; use the AArch32 way
(start all 4 cores and clear `__smp_spin`) instead.

Tested on 2026-10-09: all 14 AArch64 tests (all but `usb_test`) passed
this way, one after another, with only the step-4 reset between them.

### Step 2 (AArch64)

```bash
D=$BUILD/aarch64-rpi-zero-2w-cmake-gcc-debug/platform-bin/port-tests/test
CFG=$A64/test/boards/rpi-zero-2w
ELF=$D/smp_test0-hwd
```

Nothing to read from the ELF: the entry is always `0x80000`.

### Step 4 (AArch64) — reset the board

```bash
$OPENOCD -s $CFG -f $CFG/openocd-jlink-rpi3.cfg -c "init" \
  -c "targets bcm2837.cpu0" \
  -c "halt" \
  -c "mww 0x3f100024 0x5a000001" \
  -c "mww 0x3f10001c 0x5a000020" \
  -c "shutdown"
```

`-c "init"` connects to the board: the 64-bit config file only describes
the hardware and does not connect by itself.

### Step 5 (AArch64)

```bash
sleep 12
```

### Step 6 (AArch64) — load the test and start it

```bash
$OPENOCD -s $CFG -f $CFG/openocd-jlink-rpi3.cfg -c "init" \
  -c "targets bcm2837.cpu0" -c "halt" \
  -c "targets bcm2837.cpu1" -c "halt" \
  -c "targets bcm2837.cpu2" -c "halt" \
  -c "targets bcm2837.cpu3" -c "halt" \
  -c "targets bcm2837.cpu0" -c "arm semihosting enable" \
  -c "targets bcm2837.cpu1" -c "arm semihosting enable" \
  -c "targets bcm2837.cpu2" -c "arm semihosting enable" \
  -c "targets bcm2837.cpu3" -c "arm semihosting enable" \
  -c "targets bcm2837.cpu0" -c "load_image $ELF" \
  -c "targets bcm2837.cpu0" -c "reg pc 0x80000" -c "resume" \
  -c "targets bcm2837.cpu1" -c "resume" \
  -c "targets bcm2837.cpu2" -c "resume" \
  -c "targets bcm2837.cpu3" -c "resume"
```

What each part does:

1. **Stop the 4 cores**, so nothing runs while the program is copied.
2. **Turn semihosting on for each core** — cores 1–3 print too, once the
   test has released them.
3. **Copy the program into RAM** (`load_image $ELF`).
4. **Start core 0**: `reg pc 0x80000` sets its program counter to the
   entry, `resume` runs it. A 64-bit core keeps the mode it was stopped in
   (EL2), and the startup code reads that mode, so there is no CPSR to set.
5. **Let cores 1–3 go on where they were** (`resume` with no address): back
   in the firmware's waiting loop, until the test releases them.

Steps 3, 7 and 8 are the same as for AArch32.

---

## With the Olimex ARM-USB-OCD instead of the J-Link

In steps 4 and 6, write `openocd-olimex.cfg` instead of
`openocd-jlink-rpi3.cfg`. Nothing else changes.

## If something goes wrong

- **`LIBUSB_ERROR_BUSY`** — another OpenOCD still holds the probe:
  `pkill -9 -f openocd`.
- **`Invalid ACK (0) in DAP response`**, then the cores cannot be examined —
  the JTAG link dropped, not the test. Lower the speed: add
  `-c "adapter speed 1000"` right after the config file, and check the
  board's power supply.
- **Nothing prints** — power-cycle the board and start again from step 4.
