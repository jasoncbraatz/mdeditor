# mdeditor MCP server (Phase 3)

Drive Jason's markdown editor (`mdeditor`) from the Claude desktop app. This is a **thin
piggyback** on the same control surface the XCTest harness uses — it shells to the `macdown`
CLI's read-back transport (`macdown --control "x-macdown://<verb>…"`), which sends a GetURL
AppleEvent to the running app and prints the handler's JSON reply. One behaviour path, not two.

SSOT for the phase: `docs/MASTER-PLAN.md` §6 · transport contract: `docs/MCP-TRANSPORT.md`.

## Tools

| Tool | Verb | Effect |
|---|---|---|
| `mdeditor_status` | `status` | Liveness/inventory (hasDocument, previewReady, commandCount, textLength). No doc needed. |
| `mdeditor_get_text` | `get-text` | Markdown text of the front document. |
| `mdeditor_render_html` | `render-html` | Rendered HTML of the front document's preview. |
| `mdeditor_open_file(path)` | `open` | Open a local `.md` file (absolute path). |
| `mdeditor_new_document(text)` | `open` | Write `text` to a temp `.md` and open it. |
| `mdeditor_run_command(command_id)` | `command` | Run a registry editing command on the front doc (`strong`, `h1`…`h6`, `ul`, `ol`, …). |
| `mdeditor_set_text(text)` | `set-text` | Replace the front document's entire markdown (text passed via temp file). |
| `mdeditor_export_html(path)` | `export-html` | Write the rendered HTML to an absolute `.html`/`.htm` path. |

All inputs are allowlist-validated **server-side** by the app (`+validatedCommandID:` /
`+validatedFileURLFromParam:` / `+validatedExportPathFromParam:`), so the MCP can only trigger
known editing commands and local-file open/export — no eval/exec, no remote fetch.

## Requirements & runtime model

- Python: `/opt/homebrew/bin/python3` with the `mcp` and `pydantic` packages (`pip install -r
  mcp/requirements.txt`). These already exist on darwin (shared with Jason's other MCPs).
- **GUI session only.** Because it talks to the *running* app via AppleEvents, this server must
  run inside the user's login session — which the Claude desktop app does. The **first** call
  pops a one-time macOS Automation consent dialog ("… wants to control mdeditor") → click
  **Allow** once. It cannot work from a headless ssh session (AppleEvents don't cross the
  session boundary — see `docs/MCP-TRANSPORT.md`).
- The `macdown` CLI must be built (target `macdown-cmd`, product `macdown`). Point `MDEDITOR_CLI`
  at it, or the server searches PATH and the `build/ddata` Debug/Release products.

## Config (`claude_desktop_config.json`)

```json
"mdeditor": {
  "command": "/opt/homebrew/bin/python3",
  "args": ["/Users/jasoncbraatz/Desktop/downloads/strike-zone/1216089018004712/macdown/mcp/mdeditor_mcp.py"],
  "env": {
    "MDEDITOR_CLI": "/absolute/path/to/macdown",
    "MDEDITOR_BUNDLE": "com.jasoncbraatz.mdeditor"
  }
}
```

`MDEDITOR_BUNDLE` defaults to the release id; set `com.jasoncbraatz.mdeditor-debug` to drive a
Debug build. `MDEDITOR_TIMEOUT` (seconds, default 20) bounds each call.

## Verify

- **Contract tests (anywhere, no app):** `cd mcp && /opt/homebrew/bin/python3 -m unittest test_mdeditor_mcp -v`
  — mocks the CLI, asserts each tool's verb/URL mapping + JSON/error contract (14 tests).
  ⚠️ Run it from **inside** `mcp/` as a module name (`test_mdeditor_mcp`), NOT `python3 -m unittest mcp/test_mdeditor_mcp.py` from the repo root — the local `mcp/` dir shadows the pip `mcp` package and that form fails with `ModuleNotFoundError`.
- **Live round-trip (GUI session):** `bash mcp/mcp-live-smoke.sh` — launches the fresh Debug build
  headless, calls each MCP tool function against it, prints the JSON, quits. (Same GUI-session
  caveat as `Scripts/readback-smoke.sh`.)
- **Claude-app smoke (DONE 2026-06-30, Bite A):** register the block above, restart the Claude desktop
  app, then ask: "make a document that says Hello and open it in mdeditor." ✅ Live round-trip GREEN from
  a Claude session (status/new_document/get_text/render_html). **Gotcha:** the app the AppleEvent reaches
  must be a CURRENT build — a stale `/Applications/mdeditor.app` (pre-read-back handler) opens the doc but
  never writes a JSON reply → "no reply from app". Keep `/Applications` rebuilt from HEAD and don't let
  stale `com.jasoncbraatz.mdeditor` copies linger in LaunchServices.

## Status

✅ Server + 8 tools, contract tests (14/0), schema-validated (8 tools list clean). Live MCP round-trip GREEN (mcp-live-smoke.sh, 2026-06-30).
✅ Claude-app registration + live in-app smoke GREEN (registered in `claude_desktop_config.json`, restarted, round-trip from a Claude session — 2026-06-30, Bite A). **→ Phase 3 complete.**
✅ `set_text` (set-text verb carries text via temp file, not the URL).
