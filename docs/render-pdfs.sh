#!/usr/bin/env bash
# render-pdfs.sh -- render every PDF in docs/ from its Markdown.
#
# One renderer (md2pdf.py) and one record of how each document is called, so
# the title pages and running footers are not something to be recovered from
# the PDFs later. Re-running this on an unchanged tree reproduces all sixteen
# files byte for byte.
#
#     ./docs/render-pdfs.sh            # all of them
#     ./docs/render-pdfs.sh STATUS     # only the ones whose name matches

set -e -u -o pipefail

cd "$(dirname "$0")"
FOOT="micro-os-plus-iii-smp"
WANT="${1:-}"

render() {
    local out="$1"; shift
    case "$out" in *"$WANT"*) ;; *) return 0 ;; esac
    python3 md2pdf.py "$out.md" "$out.pdf" "$@"
}

# The reference documents. Five carry no title page: their own H1 opens page 1.
render STATUS
render aarch32-second-board
render building-aarch32-aarch64
render cortexm-port
render posix-arch-port
render agy-review

render smp-construction \
    --title    "SMP Construction" \
    --subtitle "How the kernel, the ports and the boards fit together" \
    --footer   "$FOOT"
render test-smpl \
    --title    "test_smpl/" \
    --subtitle "The two shared test runners" \
    --footer   "$FOOT"
render tests-in-aarch32-aarch64 \
    --title    "How the tests are organised and run" \
    --subtitle "Every board owns its tests" \
    --footer   "$FOOT"
render pool-request \
    --title    "Progressive Pull Request — SMP integration" \
    --subtitle "What, why, file and code, from the corrections to the SMP integration" \
    --footer   "$FOOT" \
    --toc
render GITHUB-PROGRESSIVE-PR-GUIDE \
    --title    "GitHub Progressive Pull Request Playbook" \
    --subtitle "How to write, push, review, and merge the 7 PRs on GitHub" \
    --footer   "$FOOT" \
    --toc

# The harness documents. These came from pandoc --toc --toc-depth=2, so they
# keep their contents list and the display titles pandoc was given.
render tests/AARCH32-RPI-ZERO-2W-TESTS --toc --footer "$FOOT" \
    --title "µOS++ Tests on the Raspberry Pi Zero 2 W (AArch32)"
render tests/HARNESS-BOARD-TEST-CHEATSHEET --toc --footer "$FOOT" \
    --title "µOS++ Harness / Board Test — Cheat Sheet"
render tests/HARNESS-TESTS-PARADIGM --toc --footer "$FOOT" \
    --title "The µOS++ Harness and Tests — a Synthesis"
render tests/TESTS-XPACK-SYSTEM --toc --footer "$FOOT" \
    --title "µOS++ IIIe Tests / xPack System"
render tests/WORK-SMP-AARCH32-AARCH64-HARNESS-GUIDE --toc --footer "$FOOT" \
    --title "Running the µOS++ xPack Test Harness on the AArch32 and AArch64 Ports"

# The catalogue: every registered test, per platform and board, with its
# scheduling mode and probe.
render tests/TESTS-CATALOG --toc --footer "$FOOT" \
    --title "The µOS++ test catalogue" \
    --subtitle "Every test, per architecture, platform and board"

# The workspace log: how the whole test tree was built in $HOME/TMP, from the
# six clones to a green run, kept beside the harness it describes.
render tests/STEPS --toc --footer "$FOOT" \
    --title "The µOS++ test framework" \
    --subtitle "Install, build, run and add tests, step by step" \
    --meta "Kernel:micro-os-plus-iii" \
    --meta "Ports:aarch32, aarch64, cortexm, posix-arch"
