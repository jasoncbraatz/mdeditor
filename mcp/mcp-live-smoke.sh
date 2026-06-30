#!/usr/bin/env bash
#
# mcp-live-smoke.sh — prove the python MCP code drives the live app end-to-end.
#
# Unlike test_mdeditor_mcp.py (which mocks the CLI), this calls the REAL MCP tool functions
# against a REAL running app, so it exercises the full python -> macdown --control -> GetURL
# AppleEvent -> JSON round trip. GUI-session only (same caveat as Scripts/readback-smoke.sh):
# AppleEvents don't cross the ssh/GUI boundary, and the first run pops a one-time "… wants to
# control mdeditor" TCC dialog -> click Allow.
#
# Usage (from a GUI-session Terminal):  bash mcp/mcp-live-smoke.sh
#
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"
PROD="$REPO/build/ddata/Build/Products/Debug"
APP="$PROD/mdeditor.app/Contents/MacOS/mdeditor"
CLI="$PROD/macdown"
PY=/opt/homebrew/bin/python3
DOC=/tmp/mcp-live-smoke.md

[ -x "$APP" ] || { echo "FAIL: build the Debug app first (Scripts/test.sh)"; exit 2; }
[ -x "$CLI" ] || { echo "FAIL: build the macdown CLI first"; exit 2; }

printf '# MCP Live\n\nDriven via the **MCP** wrapper.\n' > "$DOC"
pkill -f "Build/Products/Debug/mdeditor.app/Contents/MacOS/mdeditor" 2>/dev/null; sleep 1
echo ">> launching fresh Debug build HEADLESS ..."
MPHeadlessTestMode=1 "$APP" "$DOC" >/dev/null 2>&1 &
APPPID=$!
sleep 5

MDEDITOR_CLI="$CLI" MDEDITOR_BUNDLE=com.jasoncbraatz.mdeditor-debug "$PY" - <<'PYEOF'
import asyncio, os, sys
sys.path.insert(0, os.path.join(os.getcwd(), "mcp"))
import mdeditor_mcp as M

async def main():
    print("status     :", await M.mdeditor_status(M.NoInput()))
    print("get_text   :", await M.mdeditor_get_text(M.NoInput()))
    print("run_command:", await M.mdeditor_run_command(M.RunCommandInput(command_id="h2")))
    print("get_text2  :", await M.mdeditor_get_text(M.NoInput()))   # should show the applied ## 
    print("render_html:", await M.mdeditor_render_html(M.NoInput()))
    print("export_html:", await M.mdeditor_export_html(M.ExportHtmlInput(path="/tmp/mcp-live-smoke.html")))
    print("set_text   :", await M.mdeditor_set_text(M.SetTextInput(text="# Set via MCP\nreplaced.\n")))
    print("get_text3  :", await M.mdeditor_get_text(M.NoInput()))   # should show the replaced text
    print("new_document:", await M.mdeditor_new_document(M.NewDocumentInput(text="# From MCP\nhi\n")))

asyncio.run(main())
PYEOF

echo ">> quitting headless instances ..."
kill "$APPPID" 2>/dev/null
pkill -f "Build/Products/Debug/mdeditor.app/Contents/MacOS/mdeditor" 2>/dev/null
echo ">> done."
