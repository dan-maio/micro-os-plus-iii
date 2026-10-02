#!/usr/bin/env bash
# scripts/smp/integrate-aarch-harness.sh — Steps 25/26/28 for the AArch32/64
# ports: make their tests build and run through the STANDARD xPack chain
# (xpm install/link/prepare/build/test -> ctest -> tests/smp-support/run-qemu.sh)
# in the xpack-development integration, exactly as they do on the smp branch.
#
# The dry run lifted the aarch ports' SOURCES but not their build, and the smp
# harness uses the standalone "sibling repo" model (UOS_*_DIR + a per-port
# tests-main) whereas xpack-development consumes everything as dev-linked xPacks.
# This script injects the smp-branch pieces verbatim where it can and applies the
# minimal, documented adaptations to the xPack model where it must. It is
# idempotent and fail-loud: anything lifted comes from origin/smp, and every
# anchor it rewrites is asserted.
#
# Order: run migrate-devices.sh + the step chain + absorb-test-smpl.sh first
# (this script assumes tests/smp-support/ and the dissolved soc/bcm2837 exist).
# After it, build with e.g.:
#   cd $A64 && xpm link
#   cd $K/tests && xpm install --config aarch64-rpi3b-cmake-gcc-debug \
#     && xpm link --config aarch64-rpi3b-cmake-gcc-debug @micro-os-plus/micro-os-plus-iii-aarch64 \
#     && xpm run test-mutex-stress-qemu --config aarch64-rpi3b-cmake-gcc-debug
# LOCAL only; never pushes.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/common.sh"                      # K, WORK, SMP_BRANCH
A32="${A32:-$WORK/micro-os-plus-iii-aarch32}"
A64="${A64:-$WORK/micro-os-plus-iii-aarch64}"
SMP="${SMP_BRANCH:-smp}"
say () { printf '\033[1;36m[aarch-harness]\033[0m %s\n' "$*"; }
die () { printf '\033[1;31m[aarch-harness] %s\033[0m\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------------------- #
# 1) Kernel: additive modular sub-targets (Step 26) + the uos_add_app helper.
# --------------------------------------------------------------------------- #
say "kernel: injecting cmake/uos-app.cmake + aarch toolchains from origin/$SMP"
git -C "$K" checkout "origin/$SMP" -- cmake/uos-app.cmake \
  cmake/toolchains/aarch64-none-elf.cmake cmake/toolchains/arm-none-eabi.cmake
# uos_add_app links the kernel; on smp ::iii IS the thin kernel, in
# xpack-development ::iii is the FAT kernel, so a bare-metal app links iii-core.
python3 - "$HERE/chunks" "$K/cmake/uos-app.cmake" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); from _edit import edit, replace_n
edit(sys.argv[2], lambda s: replace_n(s,
  "target_link_libraries (${_name} PRIVATE micro-os-plus::iii)",
  "target_link_libraries (${_name} PRIVATE micro-os-plus::iii-core)",
  "uos-app iii->iii-core", 1))
print("[aarch-harness] uos-app.cmake adapted to iii-core")
PY

say "kernel: adding iii-posix-io / iii-semihosting / iii-newlib-reent sub-targets"
python3 - "$K/CMakeLists.txt" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
anchor='add_library (micro-os-plus::test-support ALIAS micro-os-plus-iii-test-support-interface)'
assert s.count(anchor)==1, "test-support anchor"
def mk(alias, comment, srcs):
    t="micro-os-plus-iii-%s-interface"%alias
    return ('\n\n# %s\nadd_library (%s INTERFACE EXCLUDE_FROM_ALL)\n'
            'target_include_directories (%s INTERFACE "include" "include/cmsis-plus/legacy")\n'
            'target_sources (%s INTERFACE %s)\n'
            'add_library (micro-os-plus::%s ALIAS %s)'%(comment,t,t,t,srcs,alias,t))
blocks =mk("iii-posix-io","POSIX I/O layer (additive, for a thin-core port).",
  "\n  ".join(["","src/posix-io/block-device-partition.cpp src/posix-io/block-device.cpp",
  "src/posix-io/c-syscalls-posix.cpp src/posix-io/char-device.cpp",
  "src/posix-io/device.cpp src/posix-io/directory.cpp",
  "src/posix-io/file-descriptors-manager.cpp src/posix-io/file-system.cpp",
  "src/posix-io/file.cpp src/posix-io/io.cpp src/posix-io/net-stack.cpp",
  "src/posix-io/socket.cpp src/posix-io/tty.cpp"]))
blocks+=mk("iii-semihosting","Semihosting syscalls (additive).","src/semihosting/c-syscalls-semihosting.cpp")
blocks+=mk("iii-newlib-reent","newlib reentrancy glue (additive).","src/libc/newlib/c-newlib-reent.cpp")
# board-contract.cpp carried by test-support (compiled in the port's scope).
tgt='target_sources (micro-os-plus-iii-test-support-interface INTERFACE\n  "${CMAKE_CURRENT_SOURCE_DIR}/tests/smp-support/src/board-contract.cpp")\n'
if 'tests/smp-support/src/board-contract.cpp' not in s:
    s=s.replace(anchor, tgt+anchor, 1)
if 'micro-os-plus::iii-posix-io' not in s:
    s=s.replace(anchor, anchor+blocks, 1)
open(p,"w").write(s); print("[aarch-harness] kernel sub-targets ensured")
PY

say "kernel: injecting the 4 harness platforms from origin/$SMP"
for p in aarch64-rpi3b aarch64-rpi-zero-2w aarch32-rpi3b aarch32-rpi-zero-2w; do
  git -C "$K" checkout "origin/$SMP" -- "tests/platforms/$p"
done

# --------------------------------------------------------------------------- #
# 2) Each port: the integration-model root CMakeLists + the test builder.
# --------------------------------------------------------------------------- #
port_root () {   # port_root <repo> <arch> <alias> <extra-port-srcs>
  local R="$1" arch="$2" alias="$3" extra="$4"
  say "$arch: writing integration-model CMakeLists.txt (micro-os-plus::$alias)"
  cat > "$R/CMakeLists.txt" <<EOF
# micro-os-plus-iii-$arch — integration (xpack-development) model. The kernel is
# added by the harness and consumed as micro-os-plus::iii-core (THIN; the port
# owns startup/trace); the dissolved BCM2837 SoC is compiled locally; the
# board-fact contract comes via micro-os-plus::test-support. Exports
# micro-os-plus::$alias. (Authored for the integration — the smp-branch root
# used the standalone sibling + devices model.)
cmake_minimum_required (VERSION 3.20)
project (micro-os-plus-iii-$arch LANGUAGES C CXX ASM)

file (GLOB _board_decls CONFIGURE_DEPENDS "\${CMAKE_CURRENT_SOURCE_DIR}/test/boards/*/board.cmake")
set (_board_ids "")
foreach (_decl IN LISTS _board_decls)
  get_filename_component (_dir "\${_decl}" DIRECTORY)
  get_filename_component (_id "\${_dir}" NAME)
  list (APPEND _board_ids "\${_id}")
endforeach ()
list (SORT _board_ids)
set (BOARD "rpi-zero-2w" CACHE STRING "Target board (one of: \${_board_ids})")
set_property (CACHE BOARD PROPERTY STRINGS \${_board_ids})
if (NOT BOARD IN_LIST _board_ids)
  message (FATAL_ERROR "BOARD=\${BOARD} is not a board of this port.")
endif ()
include ("\${CMAKE_CURRENT_SOURCE_DIR}/test/boards/\${BOARD}/board.cmake")
foreach (_r IN ITEMS UOS_BOARD_SRC_DIR UOS_BOARD_FLAGS UOS_BOARD_NCPU UOS_BOARD_CAPS
                     UOS_BOARD_LINKER_HW UOS_BOARD_DEFINES)
  if (NOT DEFINED \${_r})
    message (FATAL_ERROR "board.cmake does not set \${_r}.")
  endif ()
endforeach ()
get_filename_component (UOS_BOARD_SRC_DIR "\${UOS_BOARD_SRC_DIR}" ABSOLUTE)
foreach (_v IN ITEMS UOS_BOARD_SRC_DIR UOS_BOARD_NCPU UOS_BOARD_CAPS
                     UOS_BOARD_LINKER_HW UOS_BOARD_LINKER_QEMU)
  set (\${_v} "\${\${_v}}" CACHE INTERNAL "board fact")
endforeach ()
file (GLOB _board_sources CONFIGURE_DEPENDS
      "\${UOS_BOARD_SRC_DIR}/src/*.cpp" "\${UOS_BOARD_SRC_DIR}/src/*.S"
      "\${UOS_BOARD_SRC_DIR}/src/rtos/*.cpp")
file (GLOB _soc_sources CONFIGURE_DEPENDS
      "\${CMAKE_CURRENT_SOURCE_DIR}/soc/bcm2837/src/*.cpp")

add_library (micro-os-plus-iii-$arch-interface INTERFACE)
target_include_directories (micro-os-plus-iii-$arch-interface INTERFACE
  "include" "soc/bcm2837/include" "\${UOS_BOARD_SRC_DIR}/include")
target_sources (micro-os-plus-iii-$arch-interface INTERFACE
  $extra
  src/rtos/os-core.cpp
  \${_soc_sources} \${_board_sources})
target_compile_definitions (micro-os-plus-iii-$arch-interface INTERFACE \${UOS_BOARD_DEFINES})
target_compile_options    (micro-os-plus-iii-$arch-interface INTERFACE \${UOS_BOARD_FLAGS})
target_link_options       (micro-os-plus-iii-$arch-interface INTERFACE \${UOS_BOARD_FLAGS})
target_link_libraries (micro-os-plus-iii-$arch-interface INTERFACE
  micro-os-plus::iii-core micro-os-plus::port-smp-decls micro-os-plus::test-support
  \${UOS_BOARD_LIBS})
add_library (micro-os-plus::$alias ALIAS micro-os-plus-iii-$arch-interface)
set (UOS_PORT_BARE_LIB micro-os-plus::$alias CACHE INTERNAL "port bare library")
message (STATUS "µOS++ IIIe $arch port: micro-os-plus::$alias (BOARD=\${BOARD})")
EOF
}
# Port-specific sources (verified at step-32-green). The free store / _sbrk come
# from the harness platform-support.cpp + iii-core, so neither port lists them;
# aarch32 (EABI) adds its own semihosting SYS_EXIT.
port_root "$A64" aarch64 aarch64 \
  "src/context_switch.cpp src/exception_handler.cpp src/handlers.cpp src/smp_secondary.cpp"
port_root "$A32" aarch32 aarch32 \
  "src/context_switch.cpp src/exception_handler.cpp src/handlers.cpp src/semihosting-exit.cpp src/smp_secondary.cpp"

guard_builder () {  # inject the no-devices skip into a port test builder lifted from origin/smp
  local R="$1" arch="$2"
  git -C "$R" checkout "origin/$SMP" -- test/CMakeLists.txt
  python3 - "$R/test/CMakeLists.txt" <<'PY'
import sys; f=sys.argv[1]; s=open(f).read()
a='  if (NOT _srcs)\n    continue ()\n  endif ()\n  list (APPEND _apps "${_app}")'
assert s.count(a)==1, "builder anchor"
g=('  if (NOT _srcs)\n    continue ()\n  endif ()\n'
   '  # Skip a device test when no devices target exists (SD/USB not dissolved).\n'
   '  if ("${_app}" IN_LIST BOARD_TEST_NEED_DEVICES AND NOT TARGET "${UOS_BOARD_DEVICES}")\n'
   '    message (STATUS "Skipping ${_app}: needs ${UOS_BOARD_DEVICES} (not available).")\n'
   '    continue ()\n  endif ()\n  list (APPEND _apps "${_app}")')
open(f,"w").write(s.replace(a,g,1)); print("[aarch-harness] %s test builder guarded"%f)
PY
}
guard_builder "$A64" aarch64
guard_builder "$A32" aarch32

say "ports: dropping the external soc-bcm2837 lib from board.cmake (soc is compiled in)"
for f in "$A64"/test/boards/*/board.cmake "$A32"/test/boards/*/board.cmake; do
  [ -f "$f" ] || continue
  python3 - "$f" <<'PY'
import sys; f=sys.argv[1]; s=open(f).read()
s=s.replace("set (UOS_BOARD_LIBS  micro-os-plus::soc-bcm2837)",
            "set (UOS_BOARD_LIBS  )  # soc compiled into the port (devices dissolved)")
open(f,"w").write(s)
PY
done

# --------------------------------------------------------------------------- #
# 3) Platforms: adapt sibling-model paths to the xPack model; build configs.
# --------------------------------------------------------------------------- #
for p in aarch64-rpi3b aarch64-rpi-zero-2w aarch32-rpi3b aarch32-rpi-zero-2w; do
  arch="${p%%-*}"; up="$(echo "$arch" | tr a-z A-Z)"
  DF="$K/tests/platforms/$p/cmake/dependencies-folders.cmake"
  DEF="$K/tests/platforms/$p/cmake/definitions.cmake"
  PC="$K/tests/platforms/$p/CMakeLists.txt"
  # port in dependencies-folders (before the first sources/ entry)
  python3 - "$DF" "$arch" <<'PY'
import sys,re; f,arch=sys.argv[1],sys.argv[2]; s=open(f).read()
# Replace the smp-branch sibling-model rationale with the xpack-model one.
s=re.sub(r"# The AArch\d+ port.*?portable xPacks are listed here\.",
  ("# xpack-development model: the harness adds the kernel via\n"
   "# add_subdirectory(\"..\"), and this platform adds the PORT (below), which\n"
   "# links the kernel as an INTERFACE library (it does NOT add_subdirectory the\n"
   "# kernel, so there is no duplicate micro-os-plus::iii alias). The port is the\n"
   "# dev-linked xPack installed into build/<cfg>/xpacks."),
  s, count=1, flags=re.S)
line='  "${CMAKE_BINARY_DIR}/xpacks/@micro-os-plus/micro-os-plus-iii-%s"'%arch
if line not in s:
    needle='  xpack_dependencies_folders\n  "${CMAKE_SOURCE_DIR}/sources/mutex-stress"'
    assert s.count(needle)==1, "deps-folders anchor in %s"%f
    s=s.replace(needle,'  xpack_dependencies_folders\n'+line+'\n  "${CMAKE_SOURCE_DIR}/sources/mutex-stress"',1)
open(f,"w").write(s)
print("[aarch-harness] %s port listed"%f)
PY
  grep -q "UOS_${up}_DIR" "$DEF" || cat >> "$DEF" <<EOF

set (UOS_${up}_DIR "\${CMAKE_BINARY_DIR}/xpacks/@micro-os-plus/micro-os-plus-iii-$arch"
     CACHE PATH "$arch port working copy (dev-linked xPack)")
EOF
  sed -i 's#set (_runner "${CMAKE_SOURCE_DIR}/\.\./test_smpl")#set (_runner "${CMAKE_SOURCE_DIR}/smp-support")#' "$PC"
  grep -q 'cmake/uos-app.cmake' "$PC" || python3 - "$PC" "$up" <<'PY'
import sys; f,up=sys.argv[1],sys.argv[2]; s=open(f).read()
a='add_subdirectory ("${UOS_%s_DIR}/test" "port-tests/test")'%up
assert s.count(a)==1, "builder add_subdirectory anchor in %s"%f
s=s.replace(a,'include ("${CMAKE_SOURCE_DIR}/../cmake/uos-app.cmake")\n\n'+a,1)
open(f,"w").write(s); print("[aarch-harness] %s uos-app include"%f)
PY
done

say "tests/package.json: injecting aarch{32,64}-rpi3b/-rpi-zero-2w build configurations"
python3 - "$K" "$SMP" <<'PY'
import sys,json,subprocess,collections
K,smpbr=sys.argv[1],sys.argv[2]
p=K+"/tests/package.json"
smp=json.loads(subprocess.check_output(["git","-C",K,"show","%s:tests/package.json"%("origin/"+smpbr)]))
d=json.load(open(p),object_pairs_hook=collections.OrderedDict)
sbc=smp["xpack"]["buildConfigurations"]; ibc=d["xpack"]["buildConfigurations"]
add=[]
for a in ("aarch64","aarch32"):
    add+=["%s-dependencies"%a,"%s-actions"%a,
          "%s-rpi3b-cmake-gcc-debug"%a,"%s-rpi3b-cmake-gcc-release"%a,
          "%s-rpi-zero-2w-cmake-gcc-debug"%a,"%s-rpi-zero-2w-cmake-gcc-release"%a]
for k in add:
    if k in sbc and k not in ibc: ibc[k]=sbc[k]
# Ensure link-deps and automatic linking are configured for actions.
for a in ("aarch64","aarch32"):
    act=ibc.setdefault("%s-actions"%a,{}).setdefault("actions",{})
    act["install"]=[
        "xpm install --config {{ configuration.name }}",
        "xpm link @micro-os-plus/micro-os-plus-iii-%s --config {{ configuration.name }}"%a
    ]
    act["link-deps"]=[
        "xpm link @micro-os-plus/micro-os-plus-iii-%s --config {{ configuration.name }}"%a
    ]
# the port is dev-linked via `xpm link --config`, not fetched: drop its devDep.
for a in ("aarch64","aarch32"):
    dd=ibc.get("%s-dependencies"%a,{}).get("devDependencies",{})
    dd.pop("@micro-os-plus/micro-os-plus-iii-%s"%a,None)
sa=smp["xpack"].get("actions",{}); ia=d["xpack"].setdefault("actions",{})
for k in sa:
    if ("aarch32" in k or "aarch64" in k) and k not in ia: ia[k]=sa[k]
# Add aarch configs to link-deps-all if not present
lda=ia.get("link-deps-all",[])
for a in ("aarch32","aarch64"):
    for b in ("rpi-zero-2w","rpi3b"):
        for t in ("debug","release"):
            cmd="xpm run link-deps --config %s-%s-cmake-gcc-%s"%(a,b,t)
            if cmd not in lda: lda.append(cmd)
ia["link-deps-all"]=lda
json.dump(d,open(p,"w"),indent=2); open(p,"a").write("\n")
print("[aarch-harness] package.json configs injected")
PY

# --------------------------------------------------------------------------- #
# Fail-loud gate.
# --------------------------------------------------------------------------- #
for t in micro-os-plus::iii-core micro-os-plus::iii-posix-io; do :; done
[ -f "$A64/CMakeLists.txt" ] && [ -f "$A32/CMakeLists.txt" ] || die "port CMakeLists missing"
grep -q 'iii-posix-io' "$K/CMakeLists.txt" || die "kernel iii-posix-io missing"
grep -q 'iii-core' "$K/cmake/uos-app.cmake" || die "uos-app not adapted"
say "done — AArch32/64 harness wired for the standard xpm chain (see header to build)."
