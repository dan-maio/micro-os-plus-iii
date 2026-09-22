#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# verify-no-absolute-paths.sh - the Section 9 absolute-path gate.
#
#     tools/verify-no-absolute-paths.sh [workspace-dir]
#
# Reports any MACHINE-SPECIFIC absolute path written into a tracked script,
# CMake file or probe configuration, anywhere in the workspace.
#
# WHY. An absolute path under a home directory or a local install prefix is a
# particular computer's name written into a repository. The predecessor tree
# had 32 of them across roughly 20 shell scripts, and every one was a reason
# the project built on exactly one machine. The rule is that a repository
# describes where things are relative to ITSELF, and asks the environment for
# everything else.
#
# WHAT IT LOOKS FOR, and why it is a denylist rather than an allowlist.
#
# The first version of this script flagged every path starting at the root and
# then tried to permit the harmless ones. That is the wrong shape: it reported
# "/path/to/it" in a usage message, "/usr/bin/fsck.fat", "/etc/udev/rules.d/..."
# named in a diagnostic, and a macOS SDK path quoted inside a comment -- none
# of which is a portability problem, because none of them names THIS machine.
# The allowlist would have grown for ever and the gate would have been noise.
#
# So the test is the actual concern: roots that differ from one person's
# computer to another.
#
#     /home/...  /Users/...  /root/...      a home directory
#     /opt/...   /usr/local/...             a local install prefix
#     /mnt/...   /media/...  /srv/...       a mount point
#     ~/... written literally               the same thing, spelled shorter
#
# System paths that are identical on every machine of a given OS (/usr/bin,
# /etc, /dev, /proc, /sys, /lib) are not flagged: naming them is not a
# portability defect, and forbidding them would only push scripts into worse
# workarounds. `$HOME`-rooted paths are not flagged either -- $HOME is asked
# for, not assumed, which is exactly the behaviour this gate wants.
#
# THE TWO PERMITTED EXCEPTIONS, from the spec, and no others: the compiler
# toolchains and OpenOCD (with its scripts and probe configurations). Both are
# installed outside the workspace by something this project does not control,
# and guessing would be worse. A line is permitted when the path clearly names
# one of them.
#
# WHAT IS SCANNED: tracked *.sh, *.cmake, *.py, *.cfg and CMakeLists.txt, in
# every sibling repository except the read-only migration source. Upstream's
# own tree (tests/) is skipped -- it is carried as shipped (spec Section 10).
#
# This script is skipped too, and it has to be: the comment block above spells
# every denied root out loud, so the gate matched itself four times the moment
# it was committed and could never pass again. That is a narrow, deliberate
# hole -- a real absolute path added to THIS file would not be caught -- and it
# is the price of the denylist being readable. Nothing else is exempt.
# Documentation is not scanned: a README may legitimately quote a path.
#
# Exit status: 0 if clean, 1 if anything is reported, 2 on a usage error.
# -----------------------------------------------------------------------------
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${1:-$(cd "$HERE/../.." && pwd)}"

if [[ ! -d "$WORKSPACE" ]]; then
  echo "verify-no-absolute-paths.sh: $WORKSPACE is not a directory" >&2
  exit 2
fi

# Machine-specific roots, preceded by a delimiter rather than a word character
# so that "https://host/home/x" and "a/home/b" do not match.
PATTERN='(^|[^A-Za-z0-9_.-])(~|/home|/Users|/root|/opt|/usr/local|/mnt|/media|/srv)/[A-Za-z0-9_.+-]'

# The spec's two exceptions. A line naming one of them is permitted.
TOOLCHAIN='xPacks|openocd|OpenOCD|[Tt]oolchain|gcc-arm|arm-none-eabi|aarch64-none-elf|-none-elf-gcc|jlink|JLink|[Ss]egger'

repos=()
for d in "$WORKSPACE"/micro-os-plus-iii*; do
  [[ -d "$d/.git" ]] || continue
  [[ "$(basename "$d")" == "micro-os-plus-iii-smp-old" ]] && continue
  repos+=("$d")
done

if [[ ${#repos[@]} -eq 0 ]]; then
  echo "verify-no-absolute-paths.sh: no repositories under $WORKSPACE" >&2
  exit 2
fi

echo "workspace : $WORKSPACE"
printf 'repos     : %d  (%s)\n' "${#repos[@]}" \
       "$(for r in "${repos[@]}"; do basename "$r"; done | tr '\n' ' ')"

scanned=0
findings=0
permitted=0

for repo in "${repos[@]}"; do
  name="$(basename "$repo")"
  while IFS= read -r f; do
    [[ -f "$repo/$f" ]] || continue
    scanned=$((scanned + 1))
    while IFS= read -r hit; do
      n="${hit%%:*}"
      text="${hit#*:}"
      if printf '%s\n' "$text" | grep -qE "$TOOLCHAIN"; then
        permitted=$((permitted + 1))
        continue
      fi
      findings=$((findings + 1))
      printf '  %s/%s:%s\n      %s\n' "$name" "$f" "$n" \
             "$(printf '%s' "$text" | sed 's/^[[:space:]]*//')"
    done < <(grep -nE "$PATTERN" "$repo/$f" 2>/dev/null)
  done < <(cd "$repo" && git ls-files \
             | grep -E '\.(sh|cmake|py|cfg)$|(^|/)CMakeLists\.txt$' \
             | grep -v '^tests/' \
             | grep -v '^tools/verify-no-absolute-paths\.sh$')
done

printf 'files     : %d scanned, %d permitted occurrence(s) (toolchains, OpenOCD)\n' \
       "$scanned" "$permitted"

if [[ $findings -eq 0 ]]; then
  echo
  echo "PASS: no machine-specific absolute paths"
  exit 0
fi

echo
echo "FAIL: $findings machine-specific absolute path(s)"
exit 1
