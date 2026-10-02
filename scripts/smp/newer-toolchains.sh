#!/usr/bin/env bash
# scripts/smp/newer-toolchains.sh — make the tests build under host toolchains
# NEWER than the pinned ones (verified: system gcc 16.2, clang 22.1).
#
# These are BASELINE / upstream compatibility fixes, NOT part of the smp ->
# xpack-development lift: newer clang/libc++ renamed an internal and added new
# -Weverything diagnostics, and a system clang on a GNU distro needs a different
# unwinder than the self-contained xPack clang. They are kept here, separate from
# the integration chunks, so the choice is explicit and reproducible. Every edit
# asserts its anchor (via _edit.py) and is a no-op-safe single application.
#
# Run AFTER the integration is applied (the native-smp platform exists from
# Step 28). LOCAL only; touches no remote.
set -euo pipefail
source "$(dirname "$0")/common.sh"       # K
CH="$(dirname "$0")/chunks"

python3 - "$CH" "$K" <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
from _edit import edit, replace_n
K = sys.argv[2]

# 1) estd/chrono: stop depending on libc++'s internal std::chrono::__is_duration
#    (renamed to __is_duration_v around clang/libc++ 20; libstdc++ never had it).
#    Use a self-contained duration trait — portable across every gcc/clang/libc++.
chrono = f"{K}/include/cmsis-plus/estd/chrono"
old = ("      template <class _To, class Rep_T, class Period_T>\n"
       "      constexpr typename std::enable_if<std::chrono::__is_duration<_To>::value,\n"
       "                                        _To>::type\n"
       "      ceil (std::chrono::duration<Rep_T, Period_T> d)\n")
new = ("      // Portable \"is this a std::chrono::duration\" trait. libc++ exposed an\n"
       "      // internal std::chrono::__is_duration<T>::value for years, then renamed it\n"
       "      // to the variable template __is_duration_v<T> (around clang/libc++ 20), and\n"
       "      // libstdc++ never exposed either. Depending on a standard-library internal\n"
       "      // is what broke this header on newer clang, so we carry our own.\n"
       "      template <class _Tp>\n"
       "      struct is_duration_ : std::false_type\n"
       "      {\n"
       "      };\n"
       "      template <class _Rep, class _Period>\n"
       "      struct is_duration_<std::chrono::duration<_Rep, _Period>> : std::true_type\n"
       "      {\n"
       "      };\n\n"
       "      template <class _To, class Rep_T, class Period_T>\n"
       "      constexpr typename std::enable_if<is_duration_<_To>::value, _To>::type\n"
       "      ceil (std::chrono::duration<Rep_T, Period_T> d)\n")
edit(chrono, lambda s: replace_n(s, old, new, "estd/chrono is_duration_ trait"))

# 2) + 3) native host platforms: new clang-20+ -Weverything flags on baseline /
#    third-party code, and a portable unwinder choice (a self-contained LLVM clang
#    bundles libunwind; a system clang on a GNU distro does not, and -lunwind would
#    pull the distro's nongnu libunwind that lacks _Unwind_Resume).
WNO_ANCHOR = '  $<$<C_COMPILER_ID:Clang,AppleClang>:-Wno-documentation>\n'
WNO_ADD = ('  # clang 20+ added these under -Weverything; harmless on older clang via\n'
           '  # -Wno-unknown-warning-option. They fire on upstream baseline headers\n'
           '  # (block-device thread-safety annotations, strcmp in device-registry) and\n'
           '  # third-party C (arm-cmsis-rtos-validator void* assignments).\n'
           '  $<$<C_COMPILER_ID:Clang,AppleClang>:-Wno-thread-safety-negative>\n'
           '  $<$<C_COMPILER_ID:Clang,AppleClang>:-Wno-unsafe-buffer-usage-in-libc-call>\n'
           '  $<$<C_COMPILER_ID:Clang,AppleClang>:-Wno-implicit-void-ptr-cast>\n')

def unwinder_block(target):
    old = ('if ("${CMAKE_C_COMPILER_ID}" STREQUAL "Clang")\n'
           '  # https://clang.llvm.org/docs/Toolchain.html#compiler-runtime\n'
           '  target_link_options (\n'
           f'    {target} INTERFACE -rtlib=compiler-rt\n'
           '    $<$<PLATFORM_ID:Linux>:-lunwind>\n'
           '    $<$<PLATFORM_ID:Linux,Darwin>:-fuse-ld=lld>\n'
           '  )\n'
           'endif ()\n')
    new = ('if ("${CMAKE_C_COMPILER_ID}" STREQUAL "Clang")\n'
           '  # https://clang.llvm.org/docs/Toolchain.html#compiler-runtime\n'
           '  # Unwinder: a self-contained LLVM clang (e.g. the xPack toolchain) bundles\n'
           '  # libunwind; a system clang on a GNU distro does not, and -unwindlib=libunwind\n'
           "  # would make lld pull the distro's nongnu libunwind (no _Unwind_Resume). Probe\n"
           "  # for LLVM's libunwind and fall back to libgcc's unwinder when it is absent.\n"
           '  execute_process (\n'
           '    COMMAND "${CMAKE_CXX_COMPILER}" --print-file-name=libunwind.a\n'
           '    OUTPUT_VARIABLE _uos_llvm_unwind OUTPUT_STRIP_TRAILING_WHITESPACE)\n'
           '  if (EXISTS "${_uos_llvm_unwind}")\n'
           '    set (_uos_unwindlib "-unwindlib=libunwind")\n'
           '  else ()\n'
           '    set (_uos_unwindlib "-unwindlib=libgcc")\n'
           '  endif ()\n'
           '  message (STATUS "clang unwinder: ${_uos_unwindlib}")\n'
           '  target_link_options (\n'
           f'    {target} INTERFACE -rtlib=compiler-rt\n'
           '    $<$<PLATFORM_ID:Linux>:${_uos_unwindlib}>\n'
           '    $<$<PLATFORM_ID:Linux,Darwin>:-fuse-ld=lld>\n'
           '  )\n'
           'endif ()\n')
    return old, new

for rel, target in (("tests/platforms/native/cmake/platform-library.cmake",
                     "platform-native-interface"),
                    ("tests/platforms/native-smp/cmake/platform-library.cmake",
                     "platform-native-smp-interface")):
    p = f"{K}/{rel}"
    import os
    if not os.path.exists(p):
        print(f"skip (absent): {rel}"); continue
    s = open(p).read()
    s = replace_n(s, WNO_ANCHOR, WNO_ANCHOR + WNO_ADD, f"{rel} clang -Wno")
    o, n = unwinder_block(target)
    s = replace_n(s, o, n, f"{rel} unwinder")
    open(p, "w").write(s); print(f"patched: {rel}")

print("[newer-toolchains] estd/chrono + native/native-smp clang flags & unwinder")
PY
ok "newer host toolchains (gcc 16, clang 22) supported — rebuild to verify"
