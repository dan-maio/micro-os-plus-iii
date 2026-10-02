#!/usr/bin/env bash
# scripts/smp/full-verify.sh — MANDATORY full-matrix gate.
#
# Drives the REAL test-framework tools, in the right order, for every platform:
#
#     (once)  per touched port:  xpm install ; xpm link           # register dev links
#     (per config)               xpm install --config C           # deps + the local:link port
#                                xpm run link-deps --config C      # overlay the dev port(s)
#                                xpm run prepare   --config C      # cmake configure
#                                xpm run build     --config C      # cmake build
#                                xpm run test      --config C      # ctest (-LE hwd)
#
# Unlike the FAST subset in verify-step.sh, this builds AND runs every platform,
# with ONE host gcc (gcc14) and ONE host clang (clang19) plus the single cross
# toolchain each target has. It reports PASS/FAIL per config and exits non-zero if
# any config fails — nothing is assumed by analogy.
#
# LOCAL ONLY: it never pushes. It consumes the dev-linked step/NN port working
# copies (the integrated ports), not the released ones.
source "$(dirname "$0")/common.sh"

S="$HOME/.local/xPacks"
GCC="$S/@xpack-dev-tools/gcc/14.2.0-2.1"
CLANG="$S/@xpack-dev-tools/clang/19.1.7-1.1"
AEABI="$S/@xpack-dev-tools/arm-none-eabi-gcc/15.2.1-1.1.1"
QEMU="$S/@xpack-dev-tools/qemu-arm/8.2.6-1.1"
LIBUCTX="$S/@xpack-3rd-party/libucontext/1.2.0-5"
CMSISCORE="$S/@xpack-3rd-party/arm-cmsis-core/5.4.0-6"
ARMCMSIS="$S/@xpacks/arm-cmsis/4.5.0-7"

# All pinned tool bins on PATH so whichever a config needs resolves to the xPack
# version (never the machine's system compiler, which is too new for µOS++).
export PATH="$GCC/.content/bin:$CLANG/.content/bin:$AEABI/.content/bin:$QEMU/.content/bin:$PATH"

# The one-gcc-one-clang matrix, one representative per platform. debug+release.
CONFIGS=(
  native-cmake-gcc14-debug      native-cmake-gcc14-release
  native-cmake-clang19-debug    native-cmake-clang19-release
  native-smp-cmake-gcc14-debug  native-smp-cmake-gcc14-release
  qemu-cortex-m0-cmake-gcc-debug   qemu-cortex-m0-cmake-gcc-release
  qemu-cortex-m3-cmake-gcc-debug   qemu-cortex-m3-cmake-gcc-release
  qemu-cortex-m4f-cmake-gcc-debug  qemu-cortex-m4f-cmake-gcc-release
  qemu-cortex-m7f-cmake-gcc-debug  qemu-cortex-m7f-cmake-gcc-release
  2xcortex-m33-cmake-gcc-debug     2xcortex-m33-cmake-gcc-release
)

# ---- 0) register the integrated port dev links (idempotent) ----------------
log "registering dev links for the integrated ports (step working copies)"
( cd "$P" && xpm install >/dev/null 2>&1 && xpm link >/dev/null 2>&1 ) && ok "posix-arch dev-linked ($(git -C "$P" branch --show-current))"
( cd "$C" && xpm install >/dev/null 2>&1 && xpm link >/dev/null 2>&1 ) && ok "cortexm dev-linked ($(git -C "$C" branch --show-current))"

cd "$K/tests"

# Defensive repair for the flaky xpm/node that sometimes creates a toolchain's
# .bin shims without linking its package folder, and does not overlay the dev
# ports / 3rd-party folders into a config's build tree. Deterministic; a no-op
# when xpm did its job.
repair_tree () {  # repair_tree <config>
  local c="$1" bt="build/$c"
  mkdir -p xpacks/@xpack-dev-tools xpacks/@xpack-3rd-party xpacks/@xpacks xpacks/@micro-os-plus 2>/dev/null
  [ -e "$GCC" ]       && ln -sfn "$GCC"       xpacks/@xpack-dev-tools/gcc 2>/dev/null
  [ -e "$CLANG" ]     && ln -sfn "$CLANG"     xpacks/@xpack-dev-tools/clang 2>/dev/null
  [ -e "$AEABI" ]     && ln -sfn "$AEABI"     xpacks/@xpack-dev-tools/arm-none-eabi-gcc 2>/dev/null
  [ -e "$QEMU" ]      && ln -sfn "$QEMU"      xpacks/@xpack-dev-tools/qemu-arm 2>/dev/null
  [ -e "$LIBUCTX" ]   && ln -sfn "$LIBUCTX"   xpacks/@xpack-3rd-party/libucontext 2>/dev/null
  [ -e "$CMSISCORE" ] && ln -sfn "$CMSISCORE" xpacks/@xpack-3rd-party/arm-cmsis-core 2>/dev/null
  [ -e "$ARMCMSIS" ]  && ln -sfn "$ARMCMSIS"  xpacks/@xpacks/arm-cmsis 2>/dev/null
  ln -sfn "$P" xpacks/@micro-os-plus/micro-os-plus-iii-posix-arch 2>/dev/null
  ln -sfn "$C" xpacks/@micro-os-plus/micro-os-plus-iii-cortexm 2>/dev/null
  # mirror into the per-config build tree (what the build-helper add_subdirectory reads)
  if [ -d "$bt/xpacks" ]; then
    mkdir -p "$bt/xpacks/@micro-os-plus" "$bt/xpacks/@xpack-3rd-party" "$bt/xpacks/@xpacks" 2>/dev/null
    ln -sfn "$P" "$bt/xpacks/@micro-os-plus/micro-os-plus-iii-posix-arch" 2>/dev/null
    ln -sfn "$C" "$bt/xpacks/@micro-os-plus/micro-os-plus-iii-cortexm" 2>/dev/null
    [ -e "$LIBUCTX" ]   && ln -sfn "$LIBUCTX"   "$bt/xpacks/@xpack-3rd-party/libucontext" 2>/dev/null
    [ -e "$CMSISCORE" ] && ln -sfn "$CMSISCORE" "$bt/xpacks/@xpack-3rd-party/arm-cmsis-core" 2>/dev/null
    [ -e "$ARMCMSIS" ]  && ln -sfn "$ARMCMSIS"  "$bt/xpacks/@xpacks/arm-cmsis" 2>/dev/null
  fi
}

declare -a RESULTS
run_stage () {  # run_stage <config> <stage-label> <cmd...>
  local c="$1" stage="$2"; shift 2
  if "$@" >"/tmp/fv_${c}_${stage}.log" 2>&1; then return 0; fi
  RESULTS+=("FAIL  $c  @${stage}")
  warn "$c: FAILED at ${stage} (see /tmp/fv_${c}_${stage}.log)"
  grep -iE 'error:|FAILED|not found|Missing|undefined reference' "/tmp/fv_${c}_${stage}.log" | head -3 | sed 's/^/      /'
  return 1
}

log "full-matrix gate: ${#CONFIGS[@]} configs (one gcc + one clang + each cross toolchain)"
for c in "${CONFIGS[@]}"; do
  echo; log "==== $c ===="
  rm -rf "build/$c"
  xpm install --config "$c" >"/tmp/fv_${c}_install.log" 2>&1 || true
  repair_tree "$c"
  xpm run link-deps --config "$c" >"/tmp/fv_${c}_linkdeps.log" 2>&1 || true   # libucontext 'no dev link' is benign
  repair_tree "$c"
  run_stage "$c" prepare xpm run prepare --config "$c" || continue
  repair_tree "$c"
  run_stage "$c" build   xpm run build   --config "$c" || continue
  run_stage "$c" test    xpm run test    --config "$c" || continue
  RESULTS+=("PASS  $c")
  ok "$c: PASS (install→link-deps→prepare→build→test)"
done

echo; echo "================ FULL-MATRIX RESULT ================"
printf '%s\n' "${RESULTS[@]}" | sort
fails=$(printf '%s\n' "${RESULTS[@]}" | grep -c '^FAIL')
echo "===================================================="
if [ "${fails:-0}" -ne 0 ]; then
  die "$fails config(s) FAILED — integration is NOT verified until all pass."
fi
ok "ALL ${#CONFIGS[@]} configs PASS (real xpm flow, build + test). Integration verified on this matrix."
