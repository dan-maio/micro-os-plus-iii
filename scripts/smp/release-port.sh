#!/usr/bin/env bash
# scripts/smp/release-port.sh <repo-dir> <version> "<notes>" — bump + tag a port.
# e.g. scripts/smp/release-port.sh "$P" 1.1.0 "SMP host CPU model + highres clock"
#
# LOCAL ONLY. We deliberately do NOT use `npm version`: the ports carry an
# upstream `postversion` lifecycle script that runs
#   git push origin --all && git push origin --tags
# and npm runs it even with --no-git-tag-version. This whole workflow forbids
# any push, so we edit package.json's "version" field directly (no npm at all)
# and commit + tag by hand. Nothing here can reach a remote.
source "$(dirname "$0")/common.sh"

REPO="${1:?repo dir}"; VER="${2:?version}"; NOTES="${3:-release v$2}"
cd "$REPO"

if [ -f package.json ]; then
  python3 - package.json "$VER" <<'PY'
import json, sys, re
path, ver = sys.argv[1], sys.argv[2]
assert re.fullmatch(r'\d+\.\d+\.\d+', ver), f"not a semver: {ver}"
with open(path) as f:
    raw = f.read()
d = json.loads(raw)
old = d.get("version")
d["version"] = ver
# Preserve 2-space indentation and a trailing newline, as npm/xpm write it.
with open(path, "w") as f:
    f.write(json.dumps(d, indent=2, ensure_ascii=False))
    f.write("\n")
print(f"version {old} -> {ver}")
PY
  git add package.json
fi

git commit -m "release: v$VER — $NOTES" || warn "nothing to commit"
git tag -f "v$VER"
ok "$(basename "$REPO"): tagged v$VER (local only, no push)"
