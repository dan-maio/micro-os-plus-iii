#!/usr/bin/env bash
# scripts/smp/check-pristine.sh [NN] — enforce the pristine-test-framework rule,
# part-aware.
#
# The xpack-development test framework must stay still. What a step may change
# depends on which part it belongs to:
#
#   Parts A/B (steps 1-23): the frozen set is TOTAL. No add/modify/delete of any
#     of: package.json, package-lock.json, everything under tests/, .github/**.
#     Library CMake (outside tests/) may change only additively.
#
#   Part C (steps 24-28): still no MODIFY/DELETE of existing entries, but ADDING
#     is allowed — new test files/platforms, and additive edits to config:
#       * package.json / package-lock.json — new keys/entries only; every
#         existing key and value must be preserved (semantic JSON subset check).
#       * tests/ CMake harness — append-only (no removed lines).
#       * existing test source/platform files stay immutable; NEW ones are fine.
#     .github/** stays frozen (restored only by finalize.sh at Step 30).
#
#   Part D (steps 29-30): not gated here (Step 30 legitimately restores/merges).
#
# Compares each touched repo's WORKING TREE to origin/xpack-development, so it
# runs before the build (verify-step Stage 0) and before the commit (advance).
source "$(dirname "$0")/common.sh"

NN="${1:-}"
BASE_REF="origin/${BASE_BRANCH}"
n="$([ -n "$NN" ] && echo $((10#$NN)) || echo 0)"

if [ "$n" -ge 29 ]; then
  ok "pristine check skipped for step $NN (Part D restores/merges by design)"
  exit 0
fi
PART="AB"; [ "$n" -ge 24 ] && [ "$n" -le 28 ] && PART="C"

repos_to_check() { if [ -n "$NN" ]; then step_repos "$NN"; else echo "$K"; fi; }

# Semantic JSON subset: every key/value in OLD must be preserved in NEW (only
# additions allowed). Prints nothing on success, a reason on failure; rc!=0 fail.
#
# Exception: the top-level "version" field is the RELEASE mechanism (Step 24's
# release-port.sh bumps it), not a test-framework entry, so a change to it is
# allowed. Everything else — scripts, buildConfigurations, actions, dependencies
# — stays frozen against modify/delete.
json_preserved() {  # json_preserved <old-json-file> <new-json-file>
  python3 - "$1" "$2" <<'PY'
import json, sys
def preserved(o, n, path="$"):
    if type(o) is not type(n):
        return f"{path}: type changed"
    if isinstance(o, dict):
        for k, v in o.items():
            if path == "$" and k == "version":
                continue                       # release bump — allowed
            if k not in n: return f"{path}.{k}: removed"
            r = preserved(v, n[k], f"{path}.{k}")
            if r: return r
        return None
    if isinstance(o, list):
        for i, item in enumerate(o):
            if not any(preserved(item, cand, "") is None for cand in n):
                return f"{path}[{i}]: existing entry modified or removed"
        return None
    return None if o == n else f"{path}: value changed"
try:
    o = json.load(open(sys.argv[1])); nw = json.load(open(sys.argv[2]))
except Exception as e:
    print(f"parse error: {e}"); sys.exit(2)
r = preserved(o, nw)
if r: print(r); sys.exit(1)
sys.exit(0)
PY
}

removed_lines() {  # count real removed lines in a modified tracked file
  git diff "$BASE_REF" -- "$1" | grep -E '^-' | grep -vcE '^---'
}

FLAG="$(mktemp)"; OLD="$(mktemp)"; trap 'rm -f "$FLAG" "$OLD"' EXIT
fail() { printf '    \033[1;31m%-3s %-11s %s\033[0m — %s\n' "$1" "$2" "$3" "$4"; echo x >>"$FLAG"; }

for repo in $(repos_to_check); do
  [ -d "$repo/.git" ] || continue
  cd "$repo"
  git rev-parse --verify --quiet "$BASE_REF" >/dev/null || { warn "$(basename "$repo"): no $BASE_REF, skipped"; continue; }
  R="$(basename "$repo")"

  while IFS=$'\t' read -r status path _; do
    [ -n "${path:-}" ] || continue
    st="${status:0:1}"

    is_ci=0;       printf '%s' "$path" | grep -qE '^\.github/'                         && is_ci=1
    is_json=0;     printf '%s' "$path" | grep -qE '(^|/)package(-lock)?\.json$'         && is_json=1
    # Harness wiring that legitimately grows when a new test/platform is added:
    is_harness=0;  printf '%s' "$path" | grep -qE '(^|/)tests/CMakeLists\.txt$|(^|/)tests/cmake/' && is_harness=1
    is_tests=0;    printf '%s' "$path" | grep -qE '(^|/)tests/'                         && is_tests=1
    is_libcmake=0; printf '%s' "$path" | grep -qE '((CMakeLists\.txt)$|\.cmake$)'       && [ "$is_tests" -eq 0 ] && is_libcmake=1

    # .github/ is frozen in both A/B and C.
    if [ "$is_ci" -eq 1 ]; then fail "$status" "FROZEN-CI" "$R/$path" "CI must not change before Step 30"; continue; fi

    if [ "$PART" = "AB" ]; then
      # Total freeze of the test framework.
      if [ "$is_json" -eq 1 ] || [ "$is_tests" -eq 1 ]; then
        fail "$status" "FROZEN" "$R/$path" "test framework frozen in Parts A/B"; continue
      fi
    else
      # Part C: additions allowed; existing entries preserved.
      if [ "$is_json" -eq 1 ]; then
        case "$st" in
          A) : ;;
          D|R) fail "$status" "JSON-DEL" "$R/$path" "config file removed/renamed" ;;
          M) if git show "$BASE_REF:$path" >"$OLD" 2>/dev/null; then
               reason="$(json_preserved "$OLD" "$path")" \
                 || fail "$status" "JSON-EDIT" "$R/$path" "existing entry changed (${reason:-non-additive})"
             else fail "$status" "JSON-EDIT" "$R/$path" "cannot read baseline to compare"; fi ;;
        esac
        continue
      fi
      if [ "$is_harness" -eq 1 ]; then
        case "$st" in
          A) : ;;                                   # new harness fragment — ok
          D|R) fail "$status" "HARNESS-DEL" "$R/$path" "harness file removed/renamed" ;;
          M) [ "$(removed_lines "$path")" -eq 0 ] || fail "$status" "HARNESS-EDIT" "$R/$path" "non-additive change (removed lines)" ;;
        esac
        continue
      fi
      if [ "$is_tests" -eq 1 ]; then
        case "$st" in
          A) : ;;                                   # new test file/platform dir — ok
          *) fail "$status" "TEST-EDIT" "$R/$path" "existing test file modified/removed" ;;
        esac
        continue
      fi
    fi

    # Library CMake (outside tests/): additive modification only, both parts.
    if [ "$is_libcmake" -eq 1 ]; then
      case "$st" in
        A) : ;;
        D|R) fail "$status" "BUILD-DEL" "$R/$path" "build file removed/renamed" ;;
        M) [ "$(removed_lines "$path")" -eq 0 ] || fail "$status" "BUILD-EDIT" "$R/$path" "non-additive change (removed lines)" ;;
      esac
      continue
    fi
    # else: include/ src/ and new source files — unrestricted.
  done < <( { git diff --name-status "$BASE_REF" --; \
              git ls-files --others --exclude-standard | sed 's/^/A\t/'; } )
done

cnt="$(wc -l <"$FLAG" | tr -d ' ')"
if [ "${cnt:-0}" -ne 0 ]; then
  die "pristine check FAILED (Part $PART): $cnt forbidden change(s) above."
fi
ok "pristine check passed (Part $PART): frozen test framework preserved"
