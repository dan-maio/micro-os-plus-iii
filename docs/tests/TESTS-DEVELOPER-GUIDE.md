# µOS++ IIIe test framework — developer guide

How to **configure**, **run** and **write** tests in the xPack/xpm test
framework of `micro-os-plus-iii` (branch `smp`).

This guide follows the workflow of the upstream
[`README-DEVELOPER.md`](../../README-DEVELOPER.md): every command is an
`xpm run <action>` executed in the `tests/` folder (or with
`-C <repo>/tests`), and the same four verbs — `install-all`, `test`,
`test-all`, `deep-clean` — are the entry points. Everything below that is
the machinery those verbs drive, and how to extend it.

Every statement in this guide was checked against the files it names. When
another document disagrees, the files win.

---

## Contents

1. [Who this is for](#1-who-this-is-for)
2. [Prerequisites and workspace](#2-prerequisites-and-workspace)
3. [Quick start (the README-DEVELOPER flow)](#3-quick-start-the-readme-developer-flow)
4. [Architecture in one picture](#4-architecture-in-one-picture)
5. [Layer 1 — `tests/package.json` (xpm)](#5-layer-1--testspackagejson-xpm)
6. [Layer 2 — the CMake harness (`tests/`)](#6-layer-2--the-cmake-harness-tests)
7. [Layer 3 — the port test builders](#7-layer-3--the-port-test-builders)
8. [Layer 4 — CTest, runners and verdicts](#8-layer-4--ctest-runners-and-verdicts)
9. [Running tests day to day](#9-running-tests-day-to-day)
10. [Writing a new test](#10-writing-a-new-test)
11. [Adding a configuration or a platform](#11-adding-a-configuration-or-a-platform)
12. [Checklist before you commit](#12-checklist-before-you-commit)
13. [Troubleshooting](#13-troubleshooting)
14. [Reference tables](#14-reference-tables)

---

## 1. Who this is for

- You want to **run** the existing tests on the host, under QEMU, or on a
  board → read §2, §3 and §9.
- You want to **add a test** → read §4, then §10. §5–§8 explain every file
  a recipe touches.
- You want to **add a board, a toolchain or a build type** → §11.

Vocabulary used throughout:

| term | meaning |
|---|---|
| **configuration** (`C`) | one entry of `xpack.buildConfigurations` in `tests/package.json`, e.g. `cortexm-pico2-cmake-gcc-debug`. It owns one build folder, `tests/build/<C>`. |
| **platform** | the value of `PLATFORM_NAME`, e.g. `cortexm-pico2`. One folder under `tests/platforms/`. Several configurations (debug/release, toolchains) share one platform. |
| **port** | an architecture repository: `micro-os-plus-iii-{aarch32,aarch64,cortexm,posix-arch}`. |
| **board** | the port's name for a physical/emulated board (`BOARD`), e.g. `pico2-rp2350b-psram`. |
| **harness suite** | a portable test in `tests/sources/<name>/`, entry point `os_main()`, no `main()`. |
| **board test** | a test owned by one board of one port, in `<port>/test/<board>/<name>/`, with its own `main()`. |
| **variant** | how a test image runs: `-qemu` (emulator), `-host` (native process), `-hwd` (real board over OpenOCD). |

---

## 2. Prerequisites and workspace

### Tools

- A recent [xpm](https://xpack.github.io/xpm/) (the harness requires
  `minimumXpmRequired: 0.20.8`), which is a portable
  [Node.js](https://nodejs.org/) command line application:

  ```sh
  npm install --global xpm@latest
  ```

- `bash`, `git`, and for hardware runs a USB debug probe (CMSIS-DAP / ST-Link /
  J-Link, per board).

Everything else — CMake, Ninja, the host GCC/clang versions, `arm-none-eabi-gcc`,
`aarch64-none-elf-gcc`, `qemu-arm`, `openocd` — is **pinned per configuration**
in `tests/package.json` and installed by xpm into
`tests/build/<C>/xpacks/.bin`. Nothing is taken from your system `PATH` except
in the `native-cmake-sys-*` configurations, whose purpose is to test the
system compiler.

### Workspace layout

The kernel and its ports are separate repositories that must be **siblings**:

```
~/Work/micro-os-plus/
├── micro-os-plus-iii/              the kernel + the test harness   (branch smp)
│   ├── tests/                      ← every xpm command runs here
│   └── test_smpl/                  the runners: run-qemu.sh, run-host.sh, run-hw.sh
├── micro-os-plus-iii-aarch32/      AArch32 port   (Raspberry Pi, Luckfox Lyra)
├── micro-os-plus-iii-aarch64/      AArch64 port   (Raspberry Pi)
├── micro-os-plus-iii-cortexm/      Cortex-M port  (RP2350, STM32F4, QEMU cores)
└── micro-os-plus-iii-posix-arch/   POSIX port     (native host process)
```

Each port carries its own drivers and SoC support in `drivers/` and
`soc/<chip>/`. They come from the former `micro-os-plus-iii-devices`
repository, which was dissolved into the ports on 2026-10-06
(`xpack-dev-smp.md` §14) and is no longer cloned.

`tests/cmake/tests-main.cmake` finds the ports as
`<tests>/../../micro-os-plus-iii-<port>`, and falls back to the old
`micro-os-plus-iii-<port>.git` names when the plain name has no
`CMakeLists.txt`. To use a copy somewhere else, pass the cache variable on
`prepare` (see §6.3), e.g. `-D UOS_CORTEXM_DIR=/path/to/cortexm`.

To clone the workspace:

```sh
mkdir -p ~/Work/micro-os-plus && cd ~/Work/micro-os-plus
for r in micro-os-plus-iii micro-os-plus-iii-aarch32 micro-os-plus-iii-aarch64 \
         micro-os-plus-iii-cortexm micro-os-plus-iii-posix-arch
do
  git clone --branch smp "<origin>/$r.git" "$r"   # <origin>: your remote
done
```

or, to update an existing workspace:

```sh
for r in ~/Work/micro-os-plus/micro-os-plus-iii*; do git -C "$r" pull; done
```

---

## 3. Quick start (the README-DEVELOPER flow)

The commands below are exactly the upstream `README-DEVELOPER.md` sequence,
pointed at this workspace. `-C` makes xpm run in the `tests/` folder, so they
work from anywhere.

**Top dependencies** (the build helper, `del-cli`, …), once per clone:

```sh
npm --prefix ~/Work/micro-os-plus/micro-os-plus-iii/tests install
```

**Satisfy dependencies for all configurations** — downloads every pinned
toolchain and emulator into each configuration's build folder (large, one-off):

```sh
xpm run install-all -C ~/Work/micro-os-plus/micro-os-plus-iii/tests
```

**Run a first test set** — `test` is the quick one (the `qemu-cortex-m7f`
debug and release suites):

```sh
xpm run test -C ~/Work/micro-os-plus/micro-os-plus-iii/tests
```

**Run all tests with all available toolchains:**

```sh
xpm run test-all -C ~/Work/micro-os-plus/micro-os-plus-iii/tests
```

`test-all` is `test-native-cmake` → `test-cortex-cmake` → `test-smp-cmake`:
every host compiler (GCC 11–14 and clang 16–19 on Linux; the system compiler
and clang 16–19 on macOS — clang 13–15 are listed but disabled), the four QEMU
Cortex-M cores,
then every SMP platform (AArch32, AArch64, the emulated Cortex-M33 pair, the
Pico 2 boards under QEMU), each in debug and release. Hardware (`hwd`) cases
are **never** part of it. Expect it to take hours.

**Remove all** dependencies and build folders, then restart from `npm install`:

```sh
xpm run deep-clean -C ~/Work/micro-os-plus/micro-os-plus-iii/tests
```

> **Never `rm -rf tests/build/<C>` by hand to "fix" a build.** The folder
> also holds that configuration's pinned toolchain (`xpacks/`). If a CMake
> cache is poisoned, delete only `tests/build/<C>/CMakeCache.txt` and run
> `prepare` again.

---

## 4. Architecture in one picture

Four layers, each edited by hand, each with one job:

```
 xpm run test-foo-qemu --config cortexm-pico2-cmake-gcc-debug
   │
   │ LAYER 1  tests/package.json
   │          which configuration, which toolchain, which build type,
   │          which actions exist (and therefore which appear in VS Code)
   ▼
 cmake -S tests -B build/<C> -G Ninja -D PLATFORM_NAME=cortexm-pico2
       -D CMAKE_BUILD_TYPE=Debug -D CMAKE_TOOLCHAIN_FILE=…/arm-none-eabi-gcc.cmake
   │
   │ LAYER 2  tests/CMakeLists.txt → cmake/tests-main.cmake
   │          → tests/platforms/<platform>/
   │          which port (library under test) and which CTest cases exist
   ▼
 add_subdirectory(<port>/test)          ← the port's own test builder
   │
   │ LAYER 3  <port>/test/CMakeLists.txt + test/boards/<board>/board.cmake
   │          + test/<board>/tests.cmake + test/<board>/<app>/*.cpp
   │          which images are built: <app>-qemu, <app>-hwd, <app>-host
   ▼
 ctest -R cortexm-pico2-foo-qemu
   │
   │ LAYER 4  CTest case → runner (qemu / run-qemu.sh / run-host.sh / hw.sh)
   │          the verdict: exit code and the "RESULT: PASS|FAIL|SKIP" line
   ▼
 PASS / FAIL / TIMEOUT
```

The rule that makes this work: **only `package.json` passes `-D PLATFORM_NAME`,
`CMAKE_BUILD_TYPE` and `CMAKE_TOOLCHAIN_FILE`**, and only the platform folder
creates CTest cases. A port never knows it is inside the harness; a platform
never compiles a test by itself when the port can.

---

## 5. Layer 1 — `tests/package.json` (xpm)

The file has two parts that matter: `xpack.properties` + `xpack.actions`
(global), and `xpack.buildConfigurations` (one entry per configuration, plus
hidden mixins).

### 5.1 Properties: the command chain

Properties are [Liquid](https://shopify.github.io/liquid/) templates, expanded
by xpm before an action runs. The global ones build every CMake command:

| property | expands to |
|---|---|
| `buildFolderRelativePath` | `build/<configuration name, lower-cased>` |
| `commandCMakeReconfigure` | `cmake -S . -B <build> -G Ninja -D CMAKE_BUILD_TYPE={{buildType}} -D PLATFORM_NAME={{platformName}}` |
| `commandCMakePrepare` | `<Reconfigure> --log-level=VERBOSE` |
| `commandCMakePrepareWithToolchain` | `<Prepare> -D CMAKE_TOOLCHAIN_FILE=xpacks/@micro-os-plus/build-helper/cmake/toolchains/{{toolchainFileName}}` |
| `commandCMakeBuild` | `cmake --build <build>` |
| `commandCMakePerformTests` | `cd <build> && ctest -V` |

A configuration supplies the variables they use: `buildType`, `platformName`,
`toolchainFileName`, and (for short Windows paths) `shortConfigurationName`.

### 5.2 Hidden mixins

A configuration with `"hidden": true` has no build folder; it exists to be
inherited. The ones in use:

| mixin | provides |
|---|---|
| `cmake-actions` | the lifecycle actions `prepare`, `build`, `test`, `clean` |
| `native-actions`, `cortexm-actions`, `aarch32-actions`, `aarch64-actions` | `install` (`xpm install --config {{ configuration.name }}`), plus `link-deps` for native/cortexm |
| `gccNN-dependencies`, `clangNN-dependencies`, `gcc-latest-…`, `clang-latest-…` | the pinned host compiler |
| `arm-none-eabi-gcc-dependencies`, `aarch32-dependencies`, `aarch64-dependencies` | the cross toolchains (+ `qemu-arm` for the Pis) |
| `qemu-arm-dependencies`, `openocd-dependencies` | emulator / probe tools |
| `native-dependencies`, `cortexm-dependencies`, `arm-cmsis-…` | source packages the platform needs |
| `clang-gcc14-properties` | for clang 16–18: builds against the xPack GCC 14 libstdc++ (`--gcc-toolchain=…`), because clang < 19 cannot parse a newer host GCC's headers |
| `short-win-paths-properties` | on Windows, `build/<shortConfigurationName>` instead of the long name |

### 5.3 A concrete configuration

Name pattern: **`<platform>-cmake-<toolchain>-<debug|release>`**.

```json
"cortexm-pico2-rp2350b-psram-cmake-gcc-debug": {
  "inherit": [
    "cortexm-actions", "cmake-actions", "cortexm-dependencies",
    "arm-cmsis-dependencies", "arm-none-eabi-gcc-dependencies",
    "openocd-dependencies", "short-win-paths-properties"
  ],
  "properties": {
    "buildType": "Debug",
    "platformName": "cortexm-pico2-rp2350b-psram",
    "toolchainFileName": "arm-none-eabi-gcc.cmake",
    "shortConfigurationName": "cpsd"
  },
  "actions": {
    "test": "cd {{ properties.buildFolderRelativePath }} && ctest -V -LE hwd",
    "test-fp-switch-qemu": "{{ properties.commandCMakePrepareWithToolchain }} && {{ properties.commandCMakeBuild }} && cd {{ properties.buildFolderRelativePath }} && ctest -V -R cortexm-pico2-rp2350b-psram-fp-switch-qemu",
    "test-fp-switch-hwd":  "… same, ending in -fp-switch-hwd"
  }
},
"cortexm-pico2-rp2350b-psram-cmake-gcc-release": {
  "inherit": ["cortexm-pico2-rp2350b-psram-cmake-gcc-debug"],
  "properties": { "buildType": "MinSizeRel", "shortConfigurationName": "cpsr" }
}
```

**Inheritance rules** (xpm):

- parents are merged in the order listed; a later parent wins over an
  earlier one; the configuration's own `properties`/`actions` win over all;
- a local action **replaces** an inherited action of the same name (that is
  how `test` above becomes `ctest -V -LE hwd`);
- the **release** configuration inherits the debug one and changes only
  `buildType` (`MinSizeRel` on embedded, `Release` on native). It has its
  **own build folder**, so it needs its own `install`.

### 5.4 Actions: three kinds

**Lifecycle** (per configuration, from `cmake-actions` and the family mixin):

| action | does | note |
|---|---|---|
| `install` | downloads the configuration's pinned tools into `build/<C>/xpacks` | run once per configuration |
| `prepare` | CMake configure **with** the toolchain file | must precede `build` on a new folder |
| `build` | CMake reconfigure (no toolchain arg — it is already cached) + build | |
| `test` | `ctest -V` — or `ctest -V -LE hwd` on every configuration that has hardware cases | **does not build** |
| `clean` | `cmake --build … --target clean` | |

**Per-test** (per configuration, written by hand, one per CTest case):

```json
"test-<app>-<variant>": "{{ properties.commandCMakePrepareWithToolchain }} && {{ properties.commandCMakeBuild }} && cd {{ properties.buildFolderRelativePath }} && ctest -V -R <platformName>-<app>-<variant>"
```

It configures and builds before it runs, so it works on a cold tree once
`install` has run. **These actions are what make a test appear in the VS Code
xPack extension**; there is no generator, so a test without its action runs
in CTest but is invisible in the IDE.

For the upstream-style platforms (`qemu-cortex-m*`, `pico2-1cpu`,
`2xcortex-m33`) the case names are `<platform>-<suite>-test`, so the actions
are `test-<suite>-test`.

**Top-level** (`xpack.actions`, no `--config`), all arrays run in sequence and
stopping at the first failure:

| action | runs |
|---|---|
| `install`, `test` | the quick set (`qemu-cortex-m7f`, debug + release) |
| `install-all` | `npm install` + `xpm install --all-configs` |
| `test-all` | `test-native-cmake` + `test-cortex-cmake` + `test-smp-cmake` |
| `test-native-cmake` | every `test-native-cmake-<compiler>`: Linux GCC 11–14 + clang 16–19, macOS `sys` + clang 16–19 (clang 13–15 are only echoed, i.e. disabled) |
| `test-native-cmake-<compiler>` | prepare/build/test of that compiler's debug and release |
| `test-cortex-cmake` | the four `test-qemu-cortex-m*-cmake` |
| `test-smp-cmake` | every SMP platform's `test-<platform>-cmake` |
| `test-<platform>-cmake` | prepare/build/test, debug then release, of one platform |
| `build-aarch32-luckfox-lyra-cmake` | build only (the Lyra is hardware-only) |
| `clean-all`, `clean-native-cmake`, `clean-cortex-cmake` | `clean` across configurations |
| `link-deps`, `link-deps-all`, `git-clone-deps`, `git-pull-deps`, `git-status-deps` | writable development packages (upstream workflow) |
| `deep-clean` | removes `build/`, `node_modules/`, `xpacks/`, `package-lock.json` |

An array action accepts no extra command-line arguments.

---

## 6. Layer 2 — the CMake harness (`tests/`)

```
tests/
├── CMakeLists.txt                project, C11/C++20, enable_testing(), build helper,
│                                 then cmake/global-definitions.cmake + cmake/tests-main.cmake
├── cmake/
│   ├── tests-main.cmake          chooses the port from PLATFORM_NAME, adds the platform
│   ├── common-options.cmake      warnings and options shared by every target
│   └── global-definitions.cmake  ENABLE_*_TEST switches (read by upstream platforms only)
├── platforms/<platform>/         one folder per PLATFORM_NAME (§6.4)
├── sources/<suite>/              the harness suites (§10.3)
├── device-qemu-cortexm/          device support for the QEMU Cortex-M boards
└── package.json                  Layer 1
```

### 6.1 `tests/CMakeLists.txt`

Refuses an in-source build, sets the language standards, loads
`micro-os-plus-build-helper` from `xpacks/@micro-os-plus/build-helper`, and
includes `global-definitions.cmake` and `tests-main.cmake`. You should not
need to edit it.

### 6.2 `cmake/tests-main.cmake` — which library is under test

In order:

1. includes `platforms/${PLATFORM_NAME}/cmake/definitions.cmake` and
   `…/dependencies-folders.cmake`, and adds each folder listed in
   `xpack_dependencies_folders` (the suites, CMSIS, …);
2. resolves the sibling repositories into cache variables (§6.3);
3. adds **the library under test**, chosen by the **first matching prefix**
   of `PLATFORM_NAME`:

| `PLATFORM_NAME` starts with | added as `port-bin` | platforms |
|---|---|---|
| `aarch32` | `UOS_AARCH32_DIR` | `aarch32-rpi-zero-2w`, `aarch32-rpi3b`, `aarch32-luckfox-lyra` |
| `aarch64` | `UOS_AARCH64_DIR` | `aarch64-rpi-zero-2w`, `aarch64-rpi3b` |
| `native` | `UOS_POSIX_ARCH_DIR` | `native` |
| `cortexm`, `qemu-cortex` | `UOS_CORTEXM_DIR` | `cortexm-*` boards, `qemu-cortex-m0/m3/m4f/m7f` |
| `pico2`, `2xcortex` | `UOS_CORTEXM_DIR` | `pico2-1cpu`, `2xcortex-m33` |
| anything else | the kernel itself (`..`, as `top-bin`) | `nucleo-*`, `raspberrypi-pico` |

Each port brings the kernel (`micro-os-plus::iii`) and the devices library
with it; **never add the kernel a second time** (`alias micro-os-plus::iii
already exists`).

4. finally `add_subdirectory(platforms/${PLATFORM_NAME} platform-bin)`.

### 6.3 Where the repositories come from

| cache variable | default |
|---|---|
| `UOS_SMP_DIR` | `tests/..` (this kernel, forced) |
| `UOS_AARCH32_DIR` | `<tests>/../../micro-os-plus-iii-aarch32` |
| `UOS_AARCH64_DIR` | `<tests>/../../micro-os-plus-iii-aarch64` |
| `UOS_POSIX_ARCH_DIR` | `<tests>/../../micro-os-plus-iii-posix-arch` |
| `UOS_CORTEXM_DIR` | `<tests>/../../micro-os-plus-iii-cortexm` |

If the plain name has no `CMakeLists.txt` but `<name>.git` does, the `.git`
name is used. Override on the command line to test another working copy:

```sh
cd ~/Work/micro-os-plus/micro-os-plus-iii/tests
PATH="$PWD/build/C/xpacks/.bin:$PATH" \
  cmake -S . -B build/C -D UOS_CORTEXM_DIR=$HOME/src/my-cortexm
```

### 6.4 A platform folder

```
tests/platforms/<platform>/
├── CMakeLists.txt                    registers the CTest cases           (§6.5)
├── cmake/
│   ├── definitions.cmake             xpack_platform_compile_definition;
│   │                                 on a port platform: set (BOARD "<id>" CACHE STRING "" FORCE)
│   ├── dependencies-folders.cmake    xpack_dependencies_folders: sources/<suite>, CMSIS, …
│   └── platform-library.cmake        micro-os-plus::platform (flags, linker, port libs)
│                                     [+ micro-os-plus::platform-support on some platforms]
├── include/cmsis-plus/platform.h     compile-time contract, included by each suite's config
└── src/platform-support.cpp          startup hooks + a strong main() calling os_main()
                                      (only platforms that run harness suites through it)
```

**`dependencies-folders.cmake` is per platform.** A suite that is not listed
there does not exist on that platform: `test::<suite>` is undefined and the
configure fails.

### 6.5 The two shapes of a platform `CMakeLists.txt`

**(a) Port platforms** (`aarch32-*`, `aarch64-*`, `cortexm-*`, `native`)
reuse the port's own builder and **glob** the board's test folders:

```cmake
include ("cmake/platform-library.cmake")
include ("${UOS_CORTEXM_DIR}/test/boards/${BOARD}/board.cmake")   # board facts
add_subdirectory ("${UOS_CORTEXM_DIR}/test" "port-tests/test")     # builds the images

file (GLOB _test_dirs LIST_DIRECTORIES true "${UOS_CORTEXM_DIR}/test/${BOARD}/*")
foreach (_dir IN LISTS _test_dirs)
  # skip files, include/, src/ and folders without *.c/*.cpp
  if (TARGET "${_app}-qemu")
    add_test (NAME "${PLATFORM_NAME}-${_app}-qemu" COMMAND <qemu> … -kernel …/${_app}-qemu.elf …)
    set_tests_properties (… PROPERTIES LABELS "qemu" TIMEOUT 300)
  endif ()
  add_test (NAME "${PLATFORM_NAME}-${_app}-hwd" COMMAND bash <board>/hw.sh "${_app}" 600)
  set_tests_properties (… PROPERTIES ENVIRONMENT "BUILD=…" LABELS "hwd" TIMEOUT 1200)
endforeach ()
```

Consequence: **adding a board test needs no edit in `tests/platforms/`.**
Creating the folder in the port and re-running `prepare` is enough for the
CTest case to exist. (The xpm action is still yours to add — §5.4.)

The differences between the port platforms:

| platform family | `-qemu` case runs | `-host` | `-hwd` case runs |
|---|---|---|---|
| `aarch32-rpi*`, `aarch64-rpi*` | `test_smpl/run-qemu.sh <bin> <qemu> -M raspi3b -smp 4` (`UOS_QEMU_ONLY=<app>`) | — | the board's `hw.sh <app> 600` |
| `aarch32-luckfox-lyra` | — (hardware only) | — | the board's `hw.sh` |
| `cortexm-*` | `qemu-system-arm -M mps2-an500 -cpu cortex-m7 -kernel <app>-qemu.elf …`, only if the port built `<app>-qemu` | — | the board's `hw.sh <app> 600` |
| `native` | — | `test_smpl/run-host.sh <bin>` (`UOS_RUN_ONLY=<app>`) | — |

**(b) Upstream-style platforms** (`qemu-cortex-m*`, `pico2-1cpu`,
`2xcortex-m33`, `nucleo-*`, `raspberrypi-pico`) build the harness suites
themselves:

```cmake
function (add_suite_executable name suite)
  add_executable (${name})
  target_link_libraries (${name} PRIVATE micro-os-plus::common-options
                         test::${suite} micro-os-plus::iii micro-os-plus::platform ${ARGN})
  add_test (NAME "${PLATFORM_NAME}-${name}"
            COMMAND "${_qemu}" --machine mps2-an500 --cpu cortex-m7
                    --kernel "$<TARGET_FILE:${name}>" --nographic
                    --semihosting-config enable=on,target=native)
  set_tests_properties ("${PLATFORM_NAME}-${name}" PROPERTIES LABELS "qemu" TIMEOUT 1200)
endfunction ()

add_suite_executable (rtos-apis-test          rtos-apis          xpacks::chan-fatfs)
add_suite_executable (mutex-stress-test       mutex-stress)
add_suite_executable (cmsis-os-validator-test cmsis-os-validator xpacks::arm-cmsis-os-validator)
```

The QEMU binary is found by globbing
`$HOME/.local/xPacks/@xpack-dev-tools/qemu-arm/*/.content/bin` (newest
first), falling back to `PATH`.

---

## 7. Layer 3 — the port test builders

Every port carries the same structure; the harness only includes it.

```
<port>/test/
├── CMakeLists.txt              the builder: one application per folder of test/<BOARD>/
├── boards/<board>/
│   ├── board.cmake             board facts: UOS_BOARD_NCPU, UOS_BOARD_LINKER_HW,
│   │                           UOS_BOARD_LINKER_QEMU, UOS_BOARD_DEFINES, sources, …
│   ├── hw.sh                   hardware runner for this board (OpenOCD)
│   └── openocd.cfg             probe + target
├── boards/shared/              cross-board helpers, e.g. hw_result.hpp (cortexm)
└── <board>/                    the board's TESTS — one folder per application
    ├── include/  src/          support shared by this board's tests (not applications)
    ├── tests.cmake             the per-test knobs a folder listing cannot express
    └── <app>/main.cpp …        one test
```

### 7.1 What the builder produces

For each folder `test/<BOARD>/<app>/` that contains a `*.cpp` — `*.c` alone
does not count (skipping
`include/` and `src/`):

| port | images |
|---|---|
| `cortexm` | `<app>-qemu.elf` if `board.cmake` sets `UOS_BOARD_LINKER_QEMU` and `<app>` is not in `BOARD_TEST_HWD_ONLY`; `<app>-hwd` always |
| `aarch32`, `aarch64` | `<app>-qemu.bin` and `<app>-hwd` |
| `posix-arch` | `<app>-host` |

**Tests are never shared between boards.** Two boards of the same SoC each
have their own `test/<board>/`; changing a test reaches one board only.

### 7.2 `tests.cmake` — the per-test knobs

Lists (variables) and hooks (functions `board_test_<x> (_app _out)` that set
`${_out}` in `PARENT_SCOPE`). The builder defines empty defaults; the board's
`tests.cmake` overrides what it needs.

| knob | kind | ports | effect |
|---|---|---|---|
| `BOARD_TEST_NEED_DEVICES` | list | all | link the board's device drivers (`UOS_BOARD_DEVICES`) |
| `BOARD_TEST_SELF_CONTAINED` | list | all | the test brings its own startup / board glue |
| `BOARD_TEST_NO_KERNEL` | list | all | bare-metal: no kernel, no scheduler, no `OS_NCPU` |
| `BOARD_TEST_HWD_ONLY` | list | cortexm | build `-hwd` only (QEMU cannot model what it tests) |
| `board_test_ncpu` | hook | all | `OS_NCPU` for this app (e.g. 1 for single-core tests) |
| `board_test_defines` | hook | all | extra compile definitions |
| `board_test_sources` | hook | all | extra sources (board glue, PSRAM, ADC, …) |
| `board_test_includes` | hook | all | extra include directories |
| `board_test_linker` | hook | all | a different linker script (e.g. PSRAM) |
| `board_test_options` | hook | all | extra compile options (e.g. `-mlong-calls`) |
| `board_test_libs` | hook | cortexm, aarch32/64 | extra link libraries — used to turn a harness suite into a board app (§10.4) |
| `board_test_libraries` | hook | posix-arch | same, posix-arch spelling |
| `board_test_qemu_libs/_sources/_includes` | hooks | cortexm | replace the board for the `-qemu` image (the generic single-core QEMU core) |

A test that needs none of these needs **no** `tests.cmake` edit.

---

## 8. Layer 4 — CTest, runners and verdicts

### 8.1 Case names and labels

| platform shape | CTest name | label |
|---|---|---|
| port platform | `<platform>-<app>-qemu` / `-hwd` / `-host` | `qemu` / `hwd` / `host` |
| upstream-style platform | `<platform>-<suite>-test` | `qemu` (`hwd` on the nucleo / pico boards) |

`ctest -R` is a **regular-expression substring** match: always pass the full
name, or `-R cortexm-pico2-smp-test1-qemu` also runs
`cortexm-pico2-smp-test1-qemu-something`.

The generic `test` action runs `ctest -V -LE hwd`: **hardware cases are
excluded on purpose**, because each one needs a board and a power cycle.

### 8.2 The verdict protocol

A test passes by saying so, in one of two ways:

| mechanism | used by | how |
|---|---|---|
| **exit status** | upstream-style suites; cortexm `-qemu`; native `cmsis-os-validator` | semihosting `SYS_EXIT` (QEMU returns it as the process status) or the host process exit code; `0` = pass |
| **`RESULT:` line** | runners (`run-qemu.sh`, `run-host.sh`, `run-hw.sh`, the boards' `hw.sh`) | the log is grepped for `RESULT: PASS`, `RESULT: SKIP`, `RESULT: FAIL` |

Board tests do both: print `RESULT: PASS|FAIL` and then **stop the run** —
`hw_result::ok()` / `hw_result::fail()` (cortexm `boards/shared/hw_result.hpp`,
and the aarch/posix equivalents) write the line through semihosting and call
`std::_Exit(0|1)`. A test that prints `RESULT:` but never stops is reported
as a timeout on hardware.

### 8.3 The runners (`test_smpl/`)

| script | arguments | environment | logs |
|---|---|---|---|
| `run-qemu.sh` | `<build-test-dir> <qemu> <machine-args…>` | `UOS_QEMU_ONLY=<app>`, `UOS_QEMU_SHIM` / `UOS_QEMU_LOAD_ADDR` (AArch32 on raspi3b), `UOS_TEST_SRC_DIR` (SD image seeding) | `<dir>/.qemu-logs/<app>.log` |
| `run-host.sh` | `<build-test-dir>` | `UOS_RUN_ONLY=<app>` | `<dir>/.host-logs/<app>.log` |
| `run-hw.sh` | `<build-test-dir> <app> [secs]` or `list` | `UOS_HW_CFG` (required), `UOS_HW_*` | `<dir>/.hw-logs/<app>.log` |

Verdicts: `PASS`, `SKIP` (e.g. `usb_test` under QEMU), `FAIL`, `TIMEOUT`,
`NO RESULT`. Per-test time budgets are in `timeout_for()` of `run-qemu.sh`
and `run-host.sh`: 300 s unless listed (`smp_test0/1/3/4` 150,
`smp_test2` 300, `smp-mat-test` 900, `smp-num/pipeline/pro-cons` 1000,
`smp-mat-sdcard-test` 2000, `sd_test` 450, `usb_test` 200). SD-card tests get
a fresh 4 GiB sparse card image per run, deleted afterwards.

### 8.4 Hardware runs (`-hwd`)

- **OpenOCD only, no GDB.** The runner programs the image, enables
  semihosting and resumes; the verdict comes from the semihosting output.
- **The UART is yours.** No runner opens the serial port; keep your terminal
  (`tio`, `picocom`) on it.
- **One test per power cycle.** Power-cycle the board before each `-hwd`
  case; `run-hw.sh` refuses to run a suite.

---

## 9. Running tests day to day

All commands run in `~/Work/micro-os-plus/micro-os-plus-iii/tests` (or add
`-C ~/Work/micro-os-plus/micro-os-plus-iii/tests`). `C` is a configuration
name.

| goal | command |
|---|---|
| tools, first time | `npm install && xpm install` |
| one configuration, cold | `xpm run install --config C` → `xpm run prepare --config C` → `xpm run build --config C` → `xpm run test --config C` (**this order**) |
| one platform, debug + release | `xpm run test-<platform>-cmake` |
| one compiler, debug + release | `xpm run test-native-cmake-gcc14` |
| one test (builds first) | `xpm run test-<app>-<variant> --config C` |
| list the cases | `PATH="$PWD/build/C/xpacks/.bin:$PATH" ctest --test-dir build/C -N` |
| one case, by hand | `PATH="$PWD/build/C/xpacks/.bin:$PATH" ctest --test-dir build/C -V -R '^<platform>-<app>-<variant>$'` |
| rebuild after editing a test | `xpm run build --config C` (or the per-test action) |
| a new test folder was added | `xpm run prepare --config C` — the glob runs at configure time |
| every broken target at once | `PATH="$PWD/build/C/xpacks/.bin:$PATH" cmake --build build/C -- -k 0` |
| the log of the last run | `build/C/…/.qemu-logs/<app>.log`, `.host-logs/`, `.hw-logs/` |

Standing rules:

- Run QEMU suites **one at a time** on an idle host; parallel emulators turn
  timing-sensitive SMP tests into timeouts. Re-run a lone timeout by itself
  before debugging it.
- `test` never builds. After an edit, `build` first or use the per-test action.
- A release configuration is separate: `install` it before its first `prepare`.

---

## 10. Writing a new test

### 10.1 Which kind of test?

| the test… | it is a… | lives in | its verdict |
|---|---|---|---|
| is portable, has no `main()`, entry `os_main()` | **harness suite** | `tests/sources/<name>/` | `os_main()` return value → exit code |
| needs one board, has its own `main()` / hooks | **board test** | `<port>/test/<board>/<name>/` | prints `RESULT:` and stops |

Rule of thumb: a test of **kernel API behaviour** that should hold on every
architecture is a harness suite. A test of **a board, a driver, an SMP
boot sequence or a port detail** is a board test.

A suite links `micro-os-plus::platform` **and** the platform's startup
support (`platform-support`, or the board's harness wrapper); a board test
links the platform **only**, because it brings its own `main()` — two strong
`main()`s collide at link time.

### 10.2 Recipe A — a board test

1. **Create the folder** `<port>/test/<board>/<name>/` with a `main.cpp`.
   Start from the closest sibling in the same folder (e.g. `smp-test1/` on a
   Pico 2 board, `smp_test0/` on native). Keep its boot sequence; change the
   body. The folder name **is** the application name.

2. **End with a verdict** — print the line, then stop:

   ```cpp
   #include <hw_result.hpp>
   // …
   if (ok)
     {
       uart::write ("RESULT: PASS\n");   // the board's console, for you
       hw_result::ok ();                 // semihosting line + _Exit(0): stops the run
     }
   else
     {
       uart::write ("RESULT: FAIL\n");
       hw_result::fail ();               // _Exit(1)
     }
   for (;;) {}                           // reached only without semihosting
   ```

3. **If needed, declare it** in `<port>/test/<board>/tests.cmake` (§7.2):
   `BOARD_TEST_NEED_DEVICES`, `BOARD_TEST_NO_KERNEL`, `BOARD_TEST_HWD_ONLY`
   (cortexm), a different `board_test_ncpu`, extra sources/defines. Most tests
   need nothing.

4. **If it runs longer than 300 s** under QEMU or on the host, add it to
   `timeout_for()` in `test_smpl/run-qemu.sh` / `run-host.sh`.

5. **Re-configure** so the glob sees it, and check the case exists:

   ```sh
   xpm run prepare --config C
   PATH="$PWD/build/C/xpacks/.bin:$PATH" ctest --test-dir build/C -N | grep <name>
   ```

6. **Add one action per variant** to **each** configuration that builds it
   (the debug one; release inherits it):

   ```json
   "test-<name>-qemu": "{{ properties.commandCMakePrepareWithToolchain }} && {{ properties.commandCMakeBuild }} && cd {{ properties.buildFolderRelativePath }} && ctest -V -R <platform>-<name>-qemu",
   "test-<name>-hwd":  "{{ properties.commandCMakePrepareWithToolchain }} && {{ properties.commandCMakeBuild }} && cd {{ properties.buildFolderRelativePath }} && ctest -V -R <platform>-<name>-hwd"
   ```

7. **Build everything and run it:**

   ```sh
   PATH="$PWD/build/C/xpacks/.bin:$PATH" cmake --build build/C -- -k 0
   xpm run test-<name>-qemu --config C
   ```

   A per-test action builds the **whole** tree: one target that does not
   build makes every action of that configuration fail.

8. **Hardware**: power-cycle the board, then `xpm run test-<name>-hwd --config C`.

### 10.3 Recipe B — a harness suite

1. **Create the files**, copying `tests/sources/mutex-stress/`:

   ```
   tests/sources/<name>/
   ├── CMakeLists.txt
   ├── README.md
   ├── include/cmsis-plus/os-app-config.h    per-suite RTOS configuration
   └── src/main.cpp                          int os_main (int argc, char* argv[])
   ```

2. **`CMakeLists.txt`** — an INTERFACE library with the `test::` alias:

   ```cmake
   cmake_minimum_required (VERSION 3.20)

   add_library (test-<name>-interface INTERFACE EXCLUDE_FROM_ALL)
   target_include_directories (test-<name>-interface INTERFACE "include")
   target_sources (test-<name>-interface INTERFACE src/main.cpp)

   if (COMMAND xpack_display_target_lists)
     xpack_display_target_lists (test-<name>-interface)
   endif ()

   add_library (test::<name> ALIAS test-<name>-interface)
   message (VERBOSE "> test::<name> -> test-<name>-interface")
   ```

3. **`src/main.cpp`** — the entry point is `os_main`, never `main`; return 0
   for pass:

   ```cpp
   #include <cmsis-plus/rtos/os.h>
   #include <cmsis-plus/diag/trace.h>

   using namespace os;
   using namespace os::rtos;

   int
   os_main (int argc __attribute__ ((unused)),
            char* argv[] __attribute__ ((unused)))
   {
     bool ok = true;
     // … exercise the kernel API; set ok = false on any failure …
     return ok ? 0 : 1;
   }
   ```

   Do not trace from the scheduler/tick ISR. Keep the controlling thread
   above the priority of busy worker threads, or on real silicon it may never
   run again (this is what `fp-switch` does).

4. **`include/cmsis-plus/os-app-config.h`** — copy the one from
   `mutex-stress` (or `fp-switch`); it includes `cmsis-plus/platform.h` and
   sets the tick, stack sizes and per-architecture options.

5. **Wire it into each platform that should run it:**

   - add `"${CMAKE_SOURCE_DIR}/sources/<name>"` to that platform's
     `cmake/dependencies-folders.cmake`;
   - upstream-style platform: add to its `CMakeLists.txt`
     `add_suite_executable (<name>-test <name> [extra libs])`;
   - port platform (cortexm, aarch32/64): run it as a board app — §10.4.

6. `prepare`, add the `test-<name>-test` (or `test-<name>-<variant>`) action,
   full build with `-k 0`, run.

### 10.4 Recipe C — a harness suite as a board app (port platforms)

Port platforms build only what the port builder builds, so a suite runs there
as a **board app** that wraps `os_main()`. This is how `cortexm-pico2` runs
`rtos-apis`, `mutex-stress`, `cmsis-os-validator` and `fp-switch`, and how
`cortexm-pico2-rp2350b-psram` runs `fp-switch`. Every step is required:

1. **A folder per suite**: `<port>/test/<board>/<suite>/harness-suite.cpp`
   (the folder gives the app its name). On the Pico 2 boards it is one line:

   ```cpp
   #include "../../pico2/harness-suite.hpp"
   ```

   `harness-suite.hpp` defines `__wrap_os_main()`: it calls
   `__real_os_main()`, prints `RESULT: PASS|FAIL` on the UART **and** through
   semihosting, and returns the code; the kernel's `std::exit(code)` is the
   semihosting `SYS_EXIT`.

2. **`board_test_libs()`** in the board's `tests.cmake` returns
   `test::<suite>` (+ its extras, e.g. `xpacks::chan-fatfs`) **and** an
   INTERFACE target that carries:
   - `OS_USE_OS_APP_CONFIG_H UOS_HARNESS_SUITE _POSIX_C_SOURCE=200809L _GNU_SOURCE`;
   - the include directory `${CMAKE_SOURCE_DIR}/platforms/${PLATFORM_NAME}/include`
     (the harness `platform.h` the suite's config includes);
   - `micro-os-plus::iii-semihosting`, `iii-newlib-reent`, `iii-posix-io`;
   - the link option `-Wl,--wrap=os_main`.

   On cortexm this target is `pico2-harness-suite`; on the Pis it is
   `<platform>-harness-suite` and also adds the platform's
   `src/platform-support.cpp`.

3. **`board_test_ncpu()`** returns 1 for the suite if the suite is
   single-core.

4. The suite folder must be in the platform's `dependencies-folders.cmake`
   (Recipe B, step 5), or `test::<suite>` is undefined.

5. `prepare`, add the `-qemu` / `-hwd` actions, full build, run.

The board's own `os-app-config.h` must `#include_next` the suite's config
under `UOS_HARNESS_SUITE` and wrap its own values in `#ifndef`, so the suite's
settings win and the board's other tests are unchanged.

---

## 11. Adding a configuration or a platform

### 11.1 A new toolchain or build type for an existing platform

1. Copy the nearest **pair** (debug + release) in
   `xpack.buildConfigurations`, rename it
   `<platform>-cmake-<toolchain>-<debug|release>`.
2. Change the dependency mixin (`gccNN-dependencies`, …), the
   `toolchainFileName`, and a unique `shortConfigurationName`.
3. Copy the `test` override and the per-test actions from the sibling.
4. Add it to the relevant top-level array (`test-native-cmake`, …) and give
   it a `test-<platform>-cmake`-style action if it needs one.
5. `xpm install --config <new>-debug`, then the cold sequence of §9.

For clang < 19 on a host with a newer GCC, inherit `gcc14-dependencies` and
`clang-gcc14-properties` as `native-cmake-clang16/17/18-*` do.

### 11.2 A new platform

1. **Name it** with a prefix that `tests-main.cmake` maps to the right port
   (§6.2), or add a branch there.
2. **Copy the nearest sibling folder** under `tests/platforms/` and adapt:
   - `cmake/definitions.cmake`: `xpack_platform_compile_definition`, and
     `set (BOARD "<board>" CACHE STRING "" FORCE)` for a port platform;
   - `cmake/dependencies-folders.cmake`: the suites and packages it needs;
   - `cmake/platform-library.cmake`: `micro-os-plus::platform` (the port
     library, startup, semihosting, flags);
   - `CMakeLists.txt`: the shape of §6.5 (a) or (b);
   - `include/cmsis-plus/platform.h`.
3. **On the port side** (port platforms): `test/boards/<board>/board.cmake`,
   `hw.sh`, `openocd.cfg`, and `test/<board>/` with its tests and
   `tests.cmake`. The builder fails at configure time if `test/<board>/` is
   missing.
4. **Add the configuration pair** (§11.1) with the right dependency mixins:
   an emulator needs `qemu-arm-dependencies`, a board needs
   `openocd-dependencies`.
5. Add `test-<platform>-cmake` and, if it is emulated, list it in
   `test-smp-cmake` (or the relevant top-level set).
6. Re-run the emulated sets of the **other** platforms of the same port: a new
   board must not change their results.

Some files carry a "DO NOT EDIT … generated from build-helper" header
(`cmake/tests-main.cmake`, `cmake/common-options.cmake`, several upstream
`platform-library.cmake`). This tree has diverged from those templates on
purpose: edit the local copy, do not regenerate it.

---

## 12. Checklist before you commit

- [ ] `xpm run prepare --config C` done after adding or removing a test folder.
- [ ] `ctest -N` shows the new case with the full name you expect.
- [ ] `cmake --build build/C -- -k 0` builds **every** target (not only yours).
- [ ] Every CTest case of every configuration that builds it has a
      `test-<app>-<variant>` action. A quick cross-check:

      ```sh
      cd ~/Work/micro-os-plus/micro-os-plus-iii/tests
      C=cortexm-pico2-cmake-gcc-debug
      PATH="$PWD/build/$C/xpacks/.bin:$PATH" ctest --test-dir build/$C -N \
        | sed -n 's/.*Test *#[0-9]*: //p' | while read -r t; do
          grep -q "ctest -V -R $t\"" package.json || echo "missing action: $t"
        done
      ```

- [ ] The test passes alone, and in its configuration's full `test` run.
- [ ] Debug **and** release (release often exposes timing and optimisation
      issues — see the clang TLS defect in `docs/posix-arch-port.md` §2).
- [ ] For a port change: the emulated sets of the port's other boards still
      pass.
- [ ] For hardware: the `-hwd` case passes on the board, one per power cycle.
- [ ] `docs/tests/TESTS-CATALOG.md` updated if you added a test or a platform.

---

## 13. Troubleshooting

| symptom | cause and fix |
|---|---|
| `found /usr/bin/cc`, or the toolchain guard says the compiler "must be …" | configured before `install`, or `build` before `prepare`. Run `install` → `prepare` again. If the cache is poisoned, delete only `build/C/CMakeCache.txt`. |
| `Missing …/build/C/xpacks/…` on a **release** configuration | release has its own build folder: `xpm run install --config <release>` |
| `no *-host executables` / every case fails at once | `test` does not build: run `build` first, or use the per-test action |
| the test runs in CTest but not in VS Code | its `test-<app>-<variant>` action is missing from `package.json` |
| every `test-*` action of one configuration fails at the build step | one target in that tree does not build: `cmake --build build/C -- -k 0` lists them all |
| a new port test is not in `ctest -N` | not re-prepared; or the folder has no `*.cpp` (the builders glob `*.cpp` only — a folder with just `*.c` gets a CTest case on cortexm but no image); or the port clone is not the one CMake uses (`UOS_*_DIR` in `CMakeCache.txt`) |
| `Cannot find the <port> port at …` | the sibling repository is missing or misnamed (§2); pass `-D UOS_<PORT>_DIR=…` |
| `alias micro-os-plus::iii already exists` | the kernel was added twice; the port adds it — never add it again |
| `undefined reference to os_startup_initialize_hardware…` | a harness suite linked without the platform support / harness wrapper |
| `undefined reference to test::<suite>` / target not found | the suite is not in the platform's `dependencies-folders.cmake` |
| two definitions of `main` | a board test linked with `platform-support`, or a suite given its own `main()` |
| a QEMU case times out with no fault in the log | host contention (parallel emulators) or a missing `timeout_for` entry: re-run alone |
| `sd_test` fails at once: `no flatfs_tool.py (set UOS_TEST_SRC_DIR)` | the CTest case must pass `UOS_TEST_SRC_DIR` in its `ENVIRONMENT` |
| `NO RESULT` although the test printed PASS | the runner read the log before it was complete; fixed in `run-host.sh` / `run-qemu.sh` (pipeline + `PIPESTATUS`) — update your clone |
| a hardware test never ends | it prints `RESULT` but does not stop: call `hw_result::ok()` / `fail()` |
| a hardware test hangs after the first print | the controlling thread starves behind busy workers: raise its priority |
| a native test hangs only with clang 16–18 release | the CPU id was read through a cached thread pointer — fixed in posix-arch; see `docs/posix-arch-port.md` §2 |

---

## 14. Reference tables

### 14.1 Files, by layer

| file | layer | edit when |
|---|---|---|
| `tests/package.json` | 1 | new configuration, new test action, new toolchain |
| `tests/CMakeLists.txt` | 2 | practically never |
| `tests/cmake/tests-main.cmake` | 2 | a new platform prefix / a new port |
| `tests/cmake/global-definitions.cmake` | 2 | an upstream-platform suite switch |
| `tests/platforms/<p>/cmake/definitions.cmake` | 2 | new platform, board id |
| `tests/platforms/<p>/cmake/dependencies-folders.cmake` | 2 | a suite added to that platform |
| `tests/platforms/<p>/cmake/platform-library.cmake` | 2 | flags, linker, port libraries |
| `tests/platforms/<p>/CMakeLists.txt` | 2 | new platform; new suite on an upstream-style platform |
| `tests/sources/<suite>/…` | 2 | new or changed harness suite |
| `<port>/test/CMakeLists.txt` | 3 | the builder itself (rare, affects every board) |
| `<port>/test/boards/<b>/board.cmake`, `hw.sh`, `openocd.cfg` | 3 | new board, probe, memory map |
| `<port>/test/<b>/tests.cmake` | 3 | per-test knobs |
| `<port>/test/<b>/<app>/…` | 3 | new or changed board test |
| `test_smpl/run-{qemu,host,hw}.sh` | 4 | timeouts, verdict parsing |

### 14.2 Environment variables

| variable | read by | meaning |
|---|---|---|
| `UOS_QEMU_ONLY` | `run-qemu.sh` | run only this app |
| `UOS_RUN_ONLY` | `run-host.sh` | run only this app |
| `UOS_QEMU_SHIM`, `UOS_QEMU_LOAD_ADDR` | `run-qemu.sh` | AArch32 on `raspi3b`: shim image and load address |
| `UOS_TEST_SRC_DIR` | `run-qemu.sh` | where the board's tests (and `flatfs_tool.py`) are |
| `UOS_HW_CFG`, `UOS_HW_*` | `run-hw.sh` | OpenOCD configuration and ISA facts |
| `BUILD` | the boards' `hw.sh` | the build folder holding `test/<app>-hwd` |
| `OPENOCD` | the boards' `hw.sh` | an explicit OpenOCD binary |

### 14.3 CMake cache variables

| variable | meaning |
|---|---|
| `PLATFORM_NAME` | the platform (set by `package.json`) |
| `CMAKE_BUILD_TYPE` | `Debug`, `Release`, `MinSizeRel` (set by `package.json`) |
| `CMAKE_TOOLCHAIN_FILE` | from `build-helper/cmake/toolchains/<toolchainFileName>` |
| `BOARD` | the port's board id (set by the platform's `definitions.cmake`) |
| `UOS_SMP_DIR`, `UOS_AARCH32_DIR`, `UOS_AARCH64_DIR`, `UOS_CORTEXM_DIR`, `UOS_POSIX_ARCH_DIR` | the repositories in use (§6.3) |
| `UOS_DEBUG_BOOT` | cortexm: compile the `hwd` images with early-boot markers |

### 14.4 Related documents

- [`README-DEVELOPER.md`](../../README-DEVELOPER.md) — the upstream quick start this guide follows.
- [`TESTS-CATALOG.md`](TESTS-CATALOG.md) — every platform, test and probe.
- [`STEPS.md`](STEPS.md) — step-by-step install, build and run.
- [`TESTS-XPACK-SYSTEM.md`](TESTS-XPACK-SYSTEM.md) — the xPack system in depth.
- [`../posix-arch-port.md`](../posix-arch-port.md) — the native port, including the verdict and timing traps.
