#!/usr/bin/env bash
# part-b.sh — COLLAPSED Part B (steps 14-23): all SMP multi-core infrastructure,
# applied as whole-smp files across the three repos. Every change is gated by
# #if defined(OS_USE_SMP_SCHEDULER) (or NCPU>1), so the single-core projection is
# unchanged vs step/13 and the single-core build is byte-identical. Not per-step
# bisectable within Part B by design (Part B is one interwoven blob; see runbook
# section 5.0).
set -euo pipefail
source "$(dirname "$0")/../common.sh"   # K P C

# --- kernel ---
git -C "$K" checkout origin/smp -- \
  include/cmsis-plus/rtos/os-c-decls.h \
  include/cmsis-plus/rtos/os-sched.h \
  include/cmsis-plus/rtos/os-thread.h \
  src/rtos/os-c-wrapper.cpp \
  src/rtos/os-core.cpp \
  src/rtos/os-idle.cpp \
  src/rtos/os-main.cpp \
  src/rtos/os-thread.cpp

# fix H: kernel SMP port_cpu_id forward decls (os-core.cpp, os-thread.cpp) clash
#        with the posix-arch port's own file-scope decl (os-inlines.h, pulled in
#        by os.h) under a REAL SMP compile (OS_USE_SMP_SCHEDULER defined as a
#        compile definition, not merely a CMake cache var) with -Werror=redundant-
#        decls. The redeclaration is identical and benign; wrap the kernel decls
#        so the port may also declare it. (cortexm/m33 don't file-scope-declare
#        it, so they were unaffected — this only surfaced on native-smp.)
python3 - "$(dirname "$0")" \
  "$K/src/rtos/os-core.cpp" "$K/src/rtos/os-thread.cpp" <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
from _edit import edit, replace_n
PUSH='#pragma GCC diagnostic push\n#pragma GCC diagnostic ignored "-Wredundant-decls"\n'
POP='#pragma GCC diagnostic pop\n'
decl='extern "C" unsigned port_cpu_id(void);\n'
edit(sys.argv[2], lambda s: replace_n(s, decl, PUSH+decl+POP, "H/os-core port_cpu_id"))
edit(sys.argv[3], lambda s: replace_n(s, decl, PUSH+decl+POP, "H/os-thread port_cpu_id"))
PY

# --- cortexm ---
git -C "$C" checkout origin/smp -- \
  include/cmsis-plus/rtos/port/os-c-decls.h \
  include/cmsis-plus/rtos/port/os-decls.h \
  include/cmsis-plus/rtos/port/os-inlines.h \
  src/rtos/os-core.cpp

# --- posix-arch (headers + os-core + the SMP host support files, 3 port fixes) ---
# The SMP host port is not self-contained in Part B: os-core.cpp's initialize()
# pulls in host_cpu.cpp, and the board/startup hooks it calls
# (os_startup_initialize_hardware*, free store, exception handler) live in files
# the smp branch adds. They land together here.
git -C "$P" checkout origin/smp -- \
  include/cmsis-plus/rtos/port/os-c-decls.h \
  include/cmsis-plus/rtos/port/os-decls.h \
  include/cmsis-plus/rtos/port/os-inlines.h \
  include/host_cpu.hpp \
  include/exception_handler.hpp \
  include/hw_result.hpp \
  src/host_cpu.cpp \
  src/free-store.cpp \
  src/board-contract.cpp \
  src/exception_handler.cpp \
  src/rtos/os-core.cpp

# --- posix-arch port fixes A–G ---------------------------------------------
# All edits go through one python pass that asserts each match is present the
# exact number of times expected. A silently-skipped edit here would let a
# -Werror regression through, or pass the byte-identical check by coincidence,
# so every substitution/insert fails loud if the pristine text has moved.
python3 - "$(dirname "$0")" \
  "$P/src/rtos/os-core.cpp" \
  "$P/src/host_cpu.cpp" \
  "$P/include/cmsis-plus/rtos/port/os-inlines.h" \
  "$P/src/exception_handler.cpp" \
  "$P/CMakeLists.txt" \
  "$P/include/cmsis-plus/rtos/port/os-decls.h" \
  "$P/src/free-store.cpp" <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
from _edit import replace_n, strip_n
PF, PH, PI, PE, CMAKE, PD, PFS = sys.argv[2:9]

def load(p):
    with open(p) as f: return f.read()

def save(p, s):
    with open(p, 'w') as f: f.write(s)

# fix A: `struct timespec` -> `timespec` in os-inlines.h
#        (baseline -Werror=redundant-tags), same as step13.
pi = load(PI)
pi = replace_n(pi, "struct timespec tp;", "timespec tp;", "A/os-inlines timespec")
save(PI, pi)

# fix B + C: os-core.cpp — drop the two forward-decls the headers now provide
#            (-Werror=redundant-decls), and guard the ctx->uc_sigmask block,
#            which exists only on the system <ucontext.h> type, not the xPack
#            libucontext type.
pf = load(PF)
pf = strip_n(pf, '\nextern "C" unsigned\nport_cpu_id (void);\n',
             "B/os-core port_cpu_id decl")
pf = strip_n(pf, '\nextern "C" void\nos_systick_handler (void);\n',
             "B/os-core os_systick_handler decl")
uc_block = ('        ::sigemptyset (&ctx->uc_sigmask);\n'
            '        ::sigaddset (&ctx->uc_sigmask, clock::signal_number ());\n'
            '        ::sigaddset (&ctx->uc_sigmask, clock::ipi_signal_number ());\n')
pf = replace_n(pf, uc_block,
               '#if !defined(OS_INCLUDE_LIBUCONTEXT)\n' + uc_block + '#endif\n',
               "C/os-core uc_sigmask block")
save(PF, pf)

# fix C (cont.) + E + G: host_cpu.cpp.
ph = load(PH)
# C: trampoline blocks irq_set at entry so a libucontext context (no uc_sigmask)
#    also starts masked until the deferred publish.
tramp = 'trampoline (void* func, void* args)\n  {\n'
ins = ("    // libucontext contexts carry no uc_sigmask, so guarantee the masked\n"
       "    // start here, before the deferred publish (unmasked again below).\n"
       "    ::pthread_sigmask (SIG_BLOCK, &interrupts::irq_set, nullptr);\n")
ph = replace_n(ph, tramp, tramp + ins, "C/host_cpu trampoline mask")
# E: drop redundant forward-decls (headers declare them) and add the missing
#    prior declaration for the strong port_smp_ipi override
#    (-Werror=missing-declarations).
ph = strip_n(ph, '\nextern "C" void\nos_systick_handler (void);\n',
             "E/host_cpu os_systick_handler decl")
ph = strip_n(ph, '\nextern "C" unsigned\nport_cpu_id (void);\n',
             "E/host_cpu port_cpu_id decl")
ipi_def = 'extern "C" void\nport_smp_ipi (unsigned cpu)\n{'
ph = replace_n(ph, ipi_def,
               'extern "C" void port_smp_ipi (unsigned cpu);\n\n' + ipi_def,
               "E/host_cpu port_smp_ipi decl")
# G: g_core_stage[] is defined only by the SMP *test board*
#    (test/boards/native/src/smp.cpp), but host_cpu.cpp references it in the
#    always-compiled install_handlers() path (posix os-core.cpp delegates to
#    host_cpu unconditionally — the smp posix port is a refactor, not a pure
#    #if-SMP addition, so these files always build; see fix D). A port-side WEAK
#    definition links a build without the test board; the board's strong
#    definition overrides it when present.
gcs_decl = 'extern "C" volatile uint32_t g_core_stage[OS_NCPU];\n'
gcs_weak = (gcs_decl +
    '\n// Port-side weak default so a build that does not link the SMP test board still\n'
    '// resolves g_core_stage[]. The SMP test board (boards/native/src/smp.cpp)\n'
    '// provides a strong definition that overrides this one when present.\n'
    'extern "C"\n{\n'
    '  __attribute__ ((weak)) volatile uint32_t g_core_stage[OS_NCPU] = {};\n'
    '}\n')
ph = replace_n(ph, gcs_decl, gcs_weak, "G/host_cpu g_core_stage weak")
save(PH, ph)

# fix F: exception_handler.cpp carries the same redundant port_cpu_id forward
#        decl (the header declares it). It has NO os_systick_handler decl, so we
#        strip only the one that exists.
pe = load(PE)
pe = strip_n(pe, '\nextern "C" unsigned\nport_cpu_id (void);\n',
             "F/exception_handler port_cpu_id decl")
save(PE, pe)

# fix D: register the new posix-arch SMP source files ADDITIVELY in the port's
#        xpack-style CMakeLists (INTERFACE target). We do NOT apply smp's own
#        CMakeLists — that is the standalone multi-repo build model (UOS_SMP_DIR /
#        add_subdirectory siblings), incompatible with the xpack-development
#        harness that consumes the port via add_subdirectory as an INTERFACE lib.
#        This is the additive part of Step 26 (modular CMake). board-contract.cpp
#        is board-specific (it #errors without PORT_GREETING) — not built here.
cm = load(CMAKE)
anchor = ('target_sources(micro-os-plus-iii-posix-arch-interface INTERFACE\n'
          '  src/diag/trace-posix.cpp\n'
          '  src/rtos/os-core.cpp\n')
added = ('  src/host_cpu.cpp\n'
         '  src/free-store.cpp\n'
         '  src/exception_handler.cpp\n')
cm = replace_n(cm, anchor, anchor + added, "D/CMakeLists target_sources")
save(CMAKE, cm)

# fix I: the destination harness builds clang with -Weverything (stricter than
#        the smp branch's own build). The SMP additions to the port HEADERS trip
#        pedantic flags the headers' existing clang block doesn't yet ignore:
#        os-decls.h — long-long literals + the _this_cpu/_in_isr reserved names;
#        os-inlines.h — long-long highres literals + per-CPU array indexing.
#        Extend the existing `#pragma clang diagnostic ignored "-Wc++98-compat"`
#        block in each (the codebase's established pattern).
CLANG_ANCHOR = '#pragma clang diagnostic ignored "-Wc++98-compat"\n'
def extend_clang(path, flags, label):
    s = load(path)
    add = ''.join(f'#pragma clang diagnostic ignored "{f}"\n' for f in flags)
    save(path, replace_n(s, CLANG_ANCHOR, CLANG_ANCHOR + add, label))
extend_clang(PD, ["-Wc++98-compat-pedantic", "-Wreserved-identifier"], "I/os-decls clang")
extend_clang(PI, ["-Wc++98-compat-pedantic", "-Wunsafe-buffer-usage"], "I/os-inlines clang")

# fix J: the new SMP host .cpp files (os-core.cpp, host_cpu.cpp,
#        exception_handler.cpp, free-store.cpp) were never built under clang in
#        the smp branch, so they lack the -Weverything preamble every port file
#        needs. Insert one comprehensive clang-ignore block BEFORE the first
#        include (so the port headers they pull in are covered too). Flags: the
#        C++98-compat family, per-CPU buffer access, the signal-macro expansion,
#        the fatal-hook noreturn/unreachable pedantry, and the ucontext
#        makecontext function-pointer cast.
JFLAGS = ["-Wc++98-compat", "-Wc++98-compat-pedantic", "-Wunsafe-buffer-usage",
          "-Wdisabled-macro-expansion", "-Wmissing-noreturn", "-Wunreachable-code",
          "-Wunreachable-code-return", "-Wcast-function-type-strict"]
JBLOCK = ("// Clang -Weverything hardening for the SMP host port (the destination harness is\n"
          "// stricter than the smp branch's own build): nullptr/alias/range-for, per-CPU\n"
          "// array indexing, signal macros, fatal hooks and the ucontext makecontext cast.\n"
          "// Placed before the includes so the port headers are covered too.\n"
          "#if defined(__clang__)\n"
          + ''.join(f'#pragma clang diagnostic ignored "{f}"\n' for f in JFLAGS)
          + "#endif\n\n")
for path, firstinc in ((PF, "#include <cassert>\n"), (PH, "#include <cerrno>\n"),
                       (PE, "#include <csignal>\n"), (PFS, "#include <cstddef>\n")):
    s = load(path)
    save(path, replace_n(s, firstinc, JBLOCK + firstinc, f"J/clang preamble {path.split('/')[-1]}"))

print("[part-b] fixes A-J applied (all anchors matched)")
PY

echo "[part-b] applied whole-smp Part-B across kernel + cortexm + posix-arch (port fixes + additive CMake)"
