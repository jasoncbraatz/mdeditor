#!/usr/bin/env bash
#
# mdeditor — install repo git hooks (opt-in, MASTER-PLAN Phase 2).
# Symlinks the version-controlled Scripts/pre-push into .git/hooks so it stays in sync
# with the repo. Re-run any time; idempotent.

set -euo pipefail
cd "$(dirname "$0")/.."

src="Scripts/pre-push"
dst=".git/hooks/pre-push"

[ -f "$src" ] || { echo "error: $src not found" >&2; exit 1; }
chmod +x "$src"
mkdir -p .git/hooks
ln -sf "../../$src" "$dst"
echo "Installed: $dst -> $src"
echo "Test it:   PRE_PUSH_SKIP=1 git push   (skips)  |  git push  (runs Scripts/test.sh)"
