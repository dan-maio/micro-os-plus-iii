#!/usr/bin/env bash
# scripts/smp/common.sh — shared config, sourced by every helper.
#
# Both the single-core baseline and the SMP source live in the SAME repos on
# github.com/dan-maio, distinguished only by branch:
#   xpack-development   -> single-core baseline (integrate INTO)
#   smp                 -> multi-core source of truth (lift chunks FROM)
# So there is a single 'origin' remote per repo.

set -euo pipefail

WORK="${WORK:-$HOME/Documents/Work/micro-os-plus}"
K="$WORK/micro-os-plus-iii"
P="$WORK/micro-os-plus-iii-posix-arch"
C="$WORK/micro-os-plus-iii-cortexm"
A32="$WORK/micro-os-plus-iii-aarch32"
A64="$WORK/micro-os-plus-iii-aarch64"
D="$WORK/micro-os-plus-iii-devices"

# Branch references (same repo, two branches).
BASE_BRANCH="xpack-development"     # single-core baseline
SMP_BRANCH="smp"                    # multi-core source
UPSTREAM="origin/${BASE_BRANCH}"    # what step/01 forks from; unifdef compares against this

# Last released port tags — informational only. NOT the integration base: each
# port's xpack-development HEAD is ahead of its last release, and that branch is
# what step/NN forks from (see new-step.sh). Step 24 cuts the next releases.
P_LAST_RELEASE="v1.0.1"   # posix-arch; next will be v1.1.0
C_LAST_RELEASE="v1.1.0"   # cortexm;    next will be v1.2.0

# GitHub org/user hosting all repos (single-core + smp branches).
GH_ORG="dan-maio"
GH_BASE="https://github.com/${GH_ORG}"

# The 12 build configs (× debug/release = 24 builds = 72 test runs).
CONFIGS=(
  native-cmake-gcc11 native-cmake-gcc12 native-cmake-gcc13 native-cmake-gcc14
  native-cmake-clang16 native-cmake-clang17 native-cmake-clang18 native-cmake-clang19
  qemu-cortex-m0-cmake-gcc qemu-cortex-m3-cmake-gcc
  qemu-cortex-m4f-cmake-gcc qemu-cortex-m7f-cmake-gcc
)

# Which repos each step touches (K always; add P/C when the step needs the port).
# NOTE: step 14 is the COLLAPSED Part B (steps 14-23 applied as one blob by
# chunks/part-b.sh); it touches all three repos — kernel, posix-arch AND cortexm
# — so it lives in the "K P C" group, not the K+P group the per-step Step 14
# (port_cpu_id only) would have used.
step_repos() {
  local nn=$((10#$1))
  case "$nn" in
    13|14|15|16|18|19|21) echo "$K $P $C" ;;
    17|23)                echo "$K $P" ;;
    24|25)                echo "$K $P $C" ;;
    26)                   echo "$K $C" ;;   # modular CMake: kernel harness + cortexm m33 target
    28)                   echo "$K $P $C $A32 $A64" ;; # add-only platforms (AArch32/64 + native-smp)
    30)                   echo "$K $P $C $A32 $A64" ;; # final SMP integration
    31)                   echo "$K $C" ;;   # integrated cortexm-pico2 (RP2350)
    *)                    echo "$K" ;;
  esac
}

log()  { printf '\033[1;36m>>> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[+] %s\033[0m\n'  "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n'  "$*" >&2; }
die()  { printf '\033[1;31m[-] %s\033[0m\n'  "$*" >&2; exit 1; }

# Two-digit step label from any input (7 -> 07).
step_label() { printf '%02d' "$((10#${1}))"; }
