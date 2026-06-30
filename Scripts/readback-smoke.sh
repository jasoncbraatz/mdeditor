#!/usr/bin/env bash
#
# readback-smoke.sh — live end-to-end smoke for the Phase 3 read-back transport.
#
# WHY THIS EXISTS (and why it can't run over SSH): the read-back path sends a GetURL
# AppleEvent to the *running* app and reads the JSON reply. AppleEvents do NOT cross from a
# non-GUI ssh session into the GUI login session (the send returns "no reply"; `launchctl
# asuser` is denied with "Could not switch to audit session"). So this smoke MUST be run
# from inside Jason's GUI session — i.e. from a Terminal he is logged into, or by him.
#
# It launches the FRESHLY-BUILT Debug app with MPHeadlessTestMode=1 so its windows are
# transparent + off-screen (no desktop takeover), fires the four read verbs through the
# freshly-built `macdown` CLI, prints each JSON reply, then quits the app. Reversible/
# self-cleaning: it only touches the instance it launched.
#
# Usage (from a GUI-session Terminal):
#   bash Scripts/readback-smoke.sh
#
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"
PROD="$REPO/build/ddata/Build/Products/Debug"
APP="$PROD/mdeditor.app/Contents/MacOS/mdeditor"
CLI="$PROD/macdown"
BUNDLE="com.jasoncbraatz.mdeditor-debug"
DOC="/tmp/readback-smoke.md"
OUT="/tmp/readback-smoke.html"

[ -x "$APP" ] || { echo "FAIL: fresh Debug app not built at $APP (run Scripts/test.sh or an Xcode Debug build first)"; exit 2; }
[ -x "$CLI" ] || { echo "FAIL: fresh macdown CLI not built at $CLI"; exit 2; }

printf '# Readback Smoke\n\nHello **world** from the read-back path.\n' > "$DOC"

# Kill any stale instance so the AppleEvent (targeted by bundle id) reaches OUR fresh one,
# not a different DerivedData copy LaunchServices might have registered.
pkill -f "Build/Products/Debug/mdeditor.app/Contents/MacOS/mdeditor" 2>/dev/null
sleep 1

echo ">> launching fresh Debug build HEADLESS (no visible window) ..."
MPHeadlessTestMode=1 "$APP" "$DOC" >/dev/null 2>&1 &
APPPID=$!
# Give AppKit time to open the doc and render the preview.
sleep 5

run() { echo "--- $1"; "$CLI" --control "$1" --bundle "$BUNDLE"; echo "(rc=$?)"; }

run "x-macdown://status"
run "x-macdown://get-text"
run "x-macdown://render-html"
run "x-macdown://export-html?path=file://$OUT"
echo "--- exported file head:"; head -c 200 "$OUT" 2>/dev/null; echo

echo ">> quitting the headless instance (pid $APPPID) ..."
kill "$APPPID" 2>/dev/null
echo ">> done."
