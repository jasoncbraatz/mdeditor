#!/usr/bin/env bash
#
# mdeditor — headless test runner (the canonical "test this" step of the dev loop).
#
#   do this  ->  Scripts/test.sh  ->  document & bank what you learned
#
# Builds the Debug app and runs the full XCTest suite WITHOUT bringing the UI onto your
# screen: the harness auto-enables headless mode under XCTest (app runs as an accessory;
# document windows are transparent + parked off-screen), so the suite never flickers the
# desktop. See docs/TEST-HARNESS.md and docs/TEST-MATRIX.md.
#
# Usage:
#   Scripts/test.sh             # build Debug + run the whole suite (headless)
#   Scripts/test.sh -q          # quieter (pipe through xcbeautify if installed)
#
# Exit code 0 = all green. Non-zero = something to fix (that's the forcing function).

set -euo pipefail
cd "$(dirname "$0")/.."

export PATH="/opt/homebrew/bin:$PATH"
export LANG="${LANG:-en_US.UTF-8}"

WORKSPACE="MacDown.xcworkspace"
SCHEME="MacDown"
RESULT="build/last.xcresult"
QUIET="${1:-}"

# --- Fresh-clone bootstrap (idempotent): submodule + pods --------------------------------
if [ ! -d "Pods" ]; then
  echo "==> first run: bootstrapping deps (submodules + pods)"
  git submodule update --init --recursive
  pod install
fi

mkdir -p build
rm -rf "$RESULT"

echo "==> xcodebuild test  (Debug, headless, CODE_SIGNING_ALLOWED=NO)"
CMD=(xcodebuild test
     -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration Debug
     CODE_SIGNING_ALLOWED=NO
     -resultBundlePath "$RESULT")

if [ "$QUIET" = "-q" ] && command -v xcbeautify >/dev/null 2>&1; then
  "${CMD[@]}" | xcbeautify
else
  "${CMD[@]}"
fi

echo ""
echo "==> GREEN. Result bundle: $RESULT"
echo "    Next: document anything new in docs/TEST-HARNESS.md and bank hard-won lessons"
echo "    (lessons.py add ...). UI-only changes go to UI verification — see docs/TEST-MATRIX.md."
