# Running the µOS++ IIIe tests

This guide is the single entry point for configuring, building and running the
tests: **all of them, one architecture, one board, or one selected case**.

Everything is driven from the kernel's test project:

```text
<workspace>/micro-os-plus-iii/tests/
```

The commands below use relative paths; the workspace can live anywhere. The
only absolute paths involved are external tools (compilers, QEMU, OpenOCD),
installed by xpm in `~/.local/xPacks/` and exposed through each
configuration's `build/<configuration>/xpacks/.bin`.

---

## 1. The workspace

```text
<workspace>/
├── micro-os-plus-iii/                 kernel + test harness (this project)
├── aarch32/  micro-os-plus-iii-aarch32, -devices-rk3506
├── aarch64/  micro-os-plus-iii-aarch64
├── cortexm/  micro-os-plus-iii-cortexm, -devices-rp2xxx, -devices-stm32f4
├── posix-arch/ micro-os-plus-iii-posix-arch
└── common/   micro-os-plus-iii-devices-bcm283x, -devices-storage
```

The ports and device packages are xPack dependencies **linked** into each
build folder (`xpm run link-deps`), as upstream does.

## 2. One-time setup

Register each working copy with xpm (once per machine), then install the
tests' dependencies:

```bash
cd <workspace>
for p in aarch32/micro-os-plus-iii-aarch32 aarch32/micro-os-plus-iii-devices-rk3506 \
         aarch64/micro-os-plus-iii-aarch64 \
         cortexm/micro-os-plus-iii-cortexm cortexm/micro-os-plus-iii-devices-rp2xxx \
         cortexm/micro-os-plus-iii-devices-stm32f4 \
         posix-arch/micro-os-plus-iii-posix-arch \
         common/micro-os-plus-iii-devices-bcm283x common/micro-os-plus-iii-devices-storage; do
  (cd "$p" && xpm link)
done

cd micro-os-plus-iii/tests
xpm run install-all          # npm install + xpm install --all-configs
xpm run link-deps-all        # link the working copies into every configuration
```

A single configuration can be prepared instead:

```bash
xpm run install   --config <configuration>
xpm run link-deps --config <configuration>
```

A configuration is named `<platform>-cmake-<toolchain>-<debug|release>`;
its build folder is `tests/build/<configuration>/`, which also contains the
pinned xPack tools for that configuration. **Do not delete a build folder** to
"clean" it; if it was deleted, run `install` and `link-deps` again.

## 3. The four commands

| Command | What it does |
|---|---|
| `xpm run install --config <C>` | installs the configuration's pinned xPack tools |
| `xpm run link-deps --config <C>` | links the ports/device packages into `build/<C>/xpacks/` |
| `xpm run prepare --config <C>` | CMake configure (`cmake -S . -B build/<C> -G Ninja …`) |
| `xpm run build --config <C>` | reconfigure + `cmake --build build/<C>` |
| `xpm run test --config <C>` | `ctest` in `build/<C>` (does **not** build) |

Typical flow for one configuration:

```bash
cd micro-os-plus-iii/tests
xpm run install   --config aarch64-rpi4b-cmake-gcc-debug
xpm run link-deps --config aarch64-rpi4b-cmake-gcc-debug
xpm run prepare   --config aarch64-rpi4b-cmake-gcc-debug
xpm run build     --config aarch64-rpi4b-cmake-gcc-debug
xpm run test      --config aarch64-rpi4b-cmake-gcc-debug
```

`install`/`link-deps` are only needed once per configuration, or after the
build folder is deleted.

## 4. Run everything, automatically

From `micro-os-plus-iii/tests`:

| Command | Scope |
|---|---|
| `xpm run test-all` | native + Cortex-M + SMP groups |
| `xpm run test-native-cmake-sys` | POSIX host, system compiler, debug + release |
| `xpm run test-native-cmake` | POSIX host, xPack GCC 11–14 and clang 16–19 |
| `xpm run test-cortex-cmake` | QEMU Cortex-M0/M3/M4F/M7F |
| `xpm run test-smp-cmake` | the CI SMP set: Pi Zero 2 W and Pi 3 B both ports, 2×M33, `pico2-1cpu`, Pico 2, PSRAM board (not Pi 4 B) |
| `xpm run test-<platform>-cmake` | one board/platform, debug + release |

Examples:

```bash
xpm run test-smp-cmake
xpm run test-aarch32-rpi3b-cmake
xpm run test-aarch64-rpi4b-cmake
xpm run test-cortexm-pico2-cmake
```

These group actions run **prepare, build and test**; they do not include
hardware-only boards or the PC-driven tests. `test-all` is the upstream CI
subset: it also omits the Pi 4 B, so run `test-aarch64-rpi4b-cmake` (or the
configuration's own `test`) for that board.

## 5. All architectures and platforms

| Family | Configuration prefixes / platforms | Runs on |
|---|---|---|
| AArch32 | `aarch32-rpi-zero-2w`, `aarch32-rpi3b` | QEMU `raspi3b`, and the board through OpenOCD |
| AArch32 | `aarch32-luckfox-lyra` | board only, through OpenOCD |
| AArch64 | `aarch64-rpi-zero-2w`, `aarch64-rpi3b`, `aarch64-rpi4b` | QEMU `raspi3b`/`raspi4b`, and the board |
| Cortex-M QEMU | `qemu-cortex-m0`, `-m3`, `-m4f`, `-m7f` | QEMU MPS2 |
| Cortex-M SMP QEMU | `2xcortex-m33`, `pico2-1cpu` | QEMU SSE-200 (2 cores / 1 core) |
| Cortex-M boards | `cortexm-pico2`, `cortexm-pico`, `cortexm-pico2-pizero`, `cortexm-pico2-rp2350b-psram`, `cortexm-nucleof411`, `cortexm-weactf411`, `cortexm-weactf412` | QEMU where applicable, and the board through OpenOCD |
| POSIX host | `native-cmake-sys`, `native-cmake-gcc*`, `native-cmake-clang*` | the PC process |

Each family has a debug and a release configuration. AArch and Cortex-M
releases use `MinSizeRel`; native releases use `Release`.

### Which tests does a platform have?

| Platform | Automated | Hardware | PC-driven |
|---|---|---|---|
| aarch32/aarch64 Pi Zero 2 W, Pi 3 B | QEMU | OpenOCD | Zero 2 W Wi-Fi/USB |
| aarch64 Pi 4 B | QEMU | OpenOCD | `eth-tcp-server`, `usb_big_test` |
| aarch32 Luckfox Lyra | — | OpenOCD | `smp_test_int3`, `smp_test_int4`, `smp_test7` |
| Pico 2 | QEMU | OpenOCD | CDC-ACM, HID |
| Pico (RP2040) | QEMU | OpenOCD | — |
| Pi-Zero RP2350B | — | OpenOCD | CDC-ACM, HID |
| WeAct RP2350B + PSRAM | QEMU | OpenOCD | the three clock tests (pot + `y`); `_200`/`_250` are `hwd-manual` |
| Nucleo F411 / WeAct F411 / F412 | — | OpenOCD | — |
| QEMU Cortex-M / `2xcortex-m33` / `pico2-1cpu` | QEMU | — | — |
| POSIX host | host process | — | — |

## 6. Select one test, a label, or a board

Inside a configuration's build folder, CTest is a normal CTest directory:

```bash
cd micro-os-plus-iii/tests
C=aarch64-rpi3b-cmake-gcc-debug

ctest --test-dir build/$C -N                      # list
ctest --test-dir build/$C -L qemu                 # all QEMU cases
ctest --test-dir build/$C -L hwd                  # all board cases
ctest --test-dir build/$C -L host                 # all POSIX host cases
ctest --test-dir build/$C -R '^aarch64-rpi3b-smp_test0-qemu$' -V
ctest --test-dir build/$C -E 'smp_test2'          # exclude by name
ctest --test-dir build/$C --rerun-failed          # only what failed
```

`-R`, `-E` and `-L` are regular expressions; **anchor** the full name with
`^…$` when selecting one case.

Labels:

| Label | Meaning |
|---|---|
| `qemu` | QEMU, plus its SD-image fixtures |
| `host` | a native host process |
| `hwd` | a board, through OpenOCD |
| `hwd-reset` | the reset fixture before an AArch hardware test (CTest adds it) |
| `hwd-manual` | a board case run by hand (PSRAM 200/250 MHz clocks) |

The configuration's `test` action normally excludes hardware
(`ctest -V -LE hwd`). On a mixed board configuration it therefore runs the
QEMU cases; `test-hwd` runs the board cases (`ctest -V -L hwd`).
Hardware-only configurations run their `hwd` set as `test`; Lyra and
Pi-Zero's default action skips their PC-driven cases, while `test-hwd` runs
every hardware case.

Useful selections:

```bash
# one board's automatic tests
xpm run test-aarch64-rpi4b-cmake

# one board's hardware tests, one after another
PROBE=cmsis-dap ctest --test-dir build/aarch64-rpi4b-cmake-gcc-debug -L hwd -V

# one hardware test
ctest --test-dir build/aarch64-rpi4b-cmake-gcc-debug \
      -R '^aarch64-rpi4b-smp_test0-hwd$' -V

# all native host tests, one configuration
xpm run build --config native-cmake-sys-debug
xpm run test --config native-cmake-sys-debug
```

`ctest -j N` can parallelise independent QEMU/host cases; hardware tests are
`RUN_SERIAL` and stay one at a time.

## 7. Hardware tests

The board cases are still CTest cases. CTest starts OpenOCD, OpenOCD loads
the image, the test runs, and its semihosting `SYS_EXIT` ends OpenOCD. The
`RESULT:` line is the verdict. The board's UART is never opened: it is yours,
in your terminal.

### Probes and environment

| Platform | Selection |
|---|---|
| AArch Pi Zero 2 W / Pi 3 B | `PROBE=jlink` (default), `olimex`, `cmsis-dap` |
| CMSIS-DAP probes | `UOS_HW_ADAPTER_SERIAL=<serial>` when several are attached |
| AArch boards | `UOS_HW_ADAPTER_KHZ=<kHz>` overrides the adapter clock |
| Cortex-M | probe is fixed by the platform's `openocd.cfg`; `UOS_HW_ADAPTER_SERIAL` for CMSIS-DAP |
| PSRAM RP2350B | 100 kHz in `openocd.cfg` (higher clocks fail to connect/halt) |

### Reset fixtures

Every AArch hardware test has a `<test>-hwd-reset` fixture: the Pi's PM
watchdog or the RK3506 global reset runs in its own OpenOCD session, then
the board is allowed to boot. CTest adds the fixture automatically; if the
reset session cannot reach the board, the test is not run.

Cortex-M boards reset through their OpenOCD configuration; no separate
fixture is needed.

### Manual cases

- **PSRAM 200/250 MHz clock tests** (`smp-test-nested-clock_200`, `_250`,
  label `hwd-manual`) need the potentiometer and `y` on the UART, then reboot
  the chip. Read their `RESULT` on the UART and run them explicitly:
  ```bash
  ctest --test-dir build/cortexm-pico2-rp2350b-psram-cmake-gcc-debug \
        -R '^cortexm-pico2-rp2350b-psram-smp-test-nested-clock_200-hwd$' -V
  ```
- **Pico 2 / Pi-Zero CDC-ACM and HID**: run the test, then the PC host app
  (`Cafe:4013` serial, or `Cafe:4012` HID; see the test folder's README).
- **Lyra** `smp_test_int3`/`_int4`: `host/kbd_forward`; `smp_test7`:
  `usb_test_host --big` plus `y/n` on the UART.
- **Pi 4 B** `eth-tcp-server`: `eth-tcp-host.py`; `usb_big_test`:
  `usb_test_host`.
- **Zero 2 W** `wifi-tcp-server`: `wifi-tcp-host.py`; `usb_test`:
  `send_file.py`.

## 8. Wi-Fi tests

The Zero 2 W Wi-Fi cases need the SSID/passphrase in the build cache. Pass
them at configure time (they stay in `CMakeCache.txt`, not in git):

```bash
cd micro-os-plus-iii/tests
cmake -S . -B build/aarch64-rpi-zero-2w-cmake-gcc-debug \
      -D WIFI_TEST_SSID='<ssid>' -D WIFI_TEST_PASS='<passphrase>'
xpm run build --config aarch64-rpi-zero-2w-cmake-gcc-debug
ctest --test-dir build/aarch64-rpi-zero-2w-cmake-gcc-debug -R wifi -V
```

Without `WIFI_TEST_SSID`, `wifi-net` stops after the scan and cannot pass.

## 9. AArch, Cortex-M, POSIX — the runtime differences

- **AArch32/AArch64 QEMU**: CTest runs `qemu-system-aarch64` directly.
  AArch32 on `raspi3b` boots through a small AArch64 → AArch32 shim
  (`shim8.img`), built with the configuration's `aarch64-none-elf-gcc`.
- **AArch hardware**: CTest runs OpenOCD with the board configuration and
  `cmake/uos-hwd.tcl` (halt, semihosting, pre-load, `load_image`, resume).
- **Cortex-M QEMU**: `qemu-system-arm` with `--semihosting-config`.
- **Cortex-M hardware**: OpenOCD programs/resets/`arm semihosting enable`,
  then resumes; the board commands are in the platform's `CMakeLists.txt`.
- **POSIX**: CTest runs the host executable directly; the "CPUs" are host
  threads.

## 10. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `No tests were found!!!` | the action used `-LE hwd` on a hardware-only board; use its `test`/`test-hwd`, or `ctest -L hwd` |
| `… is not linked into this build folder` | run `xpm run link-deps --config <C>` (after a build folder was deleted, also `install`) |
| A board test waits for ever | check the UART; some tests are PC-driven or need `y`; use the folder's README or the automatic subset |
| OpenOCD cannot connect / `CMSIS-DAP command mismatch` | replug the probe, power-cycle the board, or lower the adapter clock |
| `smp_test_int2` looks stuck at `malloc_memory_resource()` | normal; the test takes about two minutes |
| VS Code xPack task still uses an old action | reload the VS Code window after `tests/package.json` changes |
| `ctest -R name` matches nothing | anchor the full name: `-R '^<platform>-<test>-<variant>$'` |

## 11. Quick reference

```bash
cd micro-os-plus-iii/tests

# one configuration
xpm run install   --config C
xpm run link-deps --config C
xpm run prepare   --config C
xpm run build     --config C
xpm run test      --config C

# all automatic groups
xpm run test-all

# one platform, debug + release
xpm run test-<platform>-cmake

# one CTest case
ctest --test-dir build/C -R '^<case>$' -V

# only the board cases
ctest --test-dir build/C -L hwd -V
```
