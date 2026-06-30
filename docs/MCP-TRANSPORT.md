# mdeditor MCP transport — `x-macdown://` control surface (Phase 3)

> Status: **in progress.** Command-push AND read-back are now landed (code, headless-green);
> the live cross-process smoke is GUI-session-only and is now VERIFIED GREEN (2026-06-30, all
> 4 verbs); the FastMCP wrapper is the next bite. SSOT for the phase: `docs/MASTER-PLAN.md` §6.

## Why this transport
Phase 3's rule (Jason, 2026-06-29) is that the MCP is a **piggyback** on the same control
surface the test harness uses — *one behaviour path, not two*. The harness drives
`-[MPDocument invokeCommandID:sender:error:]` in-process; the transport reaches that exact
registry from outside the process. We extend the **pre-existing** `x-macdown://` URL scheme
(already wired via an `kAEGetURL` AppleEvent handler in `MPMainController`) rather than
inventing a socket/XPC — lowest surgery, fully additive, reversible.

## Verbs (today)
| URL | Effect | Returns (AppleEvent reply) |
|---|---|---|
| `x-macdown://open?url=file:///abs/path.md` | Open a local file (existing behaviour, now input-validated) | `{"ok":true,"verb":"open","path":"…"}` |
| `x-macdown://command?id=<id>` | Run an editing command on the **front** document | `{"ok":true,"verb":"command","id":"<id>"}` |
| `x-macdown://get-text` | Return the front document's markdown (`editor.string`) | `{"ok":true,"verb":"get-text","text":"…"}` |
| `x-macdown://render-html` | Return the front document's rendered HTML (`renderer.currentHtml`) | `{"ok":true,"verb":"render-html","html":"…"}` |
| `x-macdown://export-html?path=file:///abs.html` | Write the rendered HTML to a validated `.html`/`.htm` path | `{"ok":true,"verb":"export-html","path":"…","bytes":N}` |
| `x-macdown://status` | Liveness/inventory (no doc required) | `{"ok":true,"verb":"status","hasDocument":B,"previewReady":B,"commandCount":N,"textLength":N}` |

`<id>` is any member of `+[MPDocument availableCommandIDs]` (e.g. `strong`, `emphasis`,
`code`, `h1`–`h6`, `ul`, `ol`, `blockquote`, `link`, `image`, `indent`, …). The full,
authoritative list is the registry itself — never hard-code a copy.

Fire one (fire-and-forget) from the shell:
```bash
open "x-macdown://command?id=h1"        # routes to the registered mdeditor
```

## Trust model (Phase 4 tie-in — validate every input)
The scheme is a **local** attack surface (anything that can open a URL can send these). So:

- **Command ids are allowlisted, not sanitised.** `+[MPMainController validatedCommandID:]`
  returns the id **iff** it is an exact, case-sensitive member of the registry; everything
  else (`""`, unknown, `strong; rm -rf /`, `../x`, `STRONG\n`, `<script>`) is rejected and
  nothing is invoked. The transport can therefore *only* trigger known editing commands —
  there is no eval/exec path and no way to reach an arbitrary selector.
- **`open` is a local-file opener only.** `+[MPMainController validatedFileURLFromParam:]`
  requires a `file://` URL with an absolute path; non-file schemes (`http`, `https`,
  `javascript:`, `ftp`, `x-macdown://`, …) are rejected, so the verb can't be turned into a
  fetch / SSRF / scheme-redirect vector.
- **`export-html` is a WRITE surface.** `+[MPMainController validatedExportPathFromParam:]`
  is stricter than the open guard: it requires a `file://` absolute path whose extension is
  `.html`/`.htm` (case-insensitive). A typo can't clobber a dotfile/binary, and the verb can
  only ever write the front doc's *rendered HTML* (not arbitrary content). Phase 4 may further
  confine it to an allowed export dir.
- Both validators are **pure functions** (no UI/document state) and are unit-tested headless
  in `MacDownTests/MPURLCommandTests.m`.

## Read-back (landed + LIVE-VERIFIED 2026-06-30 — headless 51/0 AND GUI-session smoke green)
`open <url>` is fire-and-forget: LaunchServices does not return the AppleEvent reply to the
caller. So read-back sends the `GetURL` AppleEvent **directly** and reads `keyDirectObject`
from the reply (the handler already populates it as JSON). This lives in `macdown-cmd`:

```bash
# from a Terminal in Jason's GUI login session (NOT over ssh — see the caveat below)
macdown --control "x-macdown://get-text"           # default target: release mdeditor
macdown --control "x-macdown://status" --bundle com.jasoncbraatz.mdeditor-debug
```

`--control <url>` builds a `kAEGetURL` event targeted by `typeApplicationBundleID`, sends it
with `AESendMessage` (`NSAppleEventSendWaitForReply`), and prints the reply's
`keyDirectObject` JSON to stdout. On no-reply/denial it prints a structured
`{"ok":false,"error":…}` and exits non-zero.

**Caveat — GUI-session only (hard-won 2026-06-30).** AppleEvents do NOT cross from a non-GUI
ssh session into the GUI-session app: the send returns `"no reply from app"`, and bridging via
`launchctl asuser $(id -u) …` is denied (`Could not switch to audit session … Operation not
permitted`). So the live smoke must run inside Jason's login session. Convenience runner:

```bash
bash Scripts/readback-smoke.sh   # launches the fresh Debug build HEADLESS (MPHeadlessTestMode=1,
                                 # no visible window), fires all 4 read verbs, prints JSON, quits.
```

Also note: a bundle-id-targeted event routes via LaunchServices to whatever Debug app is
*registered* for that id — possibly a stale DerivedData copy, not your `build/ddata` build.
`readback-smoke.sh` sidesteps this by killing stale instances and launching the fresh binary
directly. The headless XCTest suite already covers the validators + JSON plumbing (51/0); only
the cross-process hop needs the GUI session.

**MCP server (landed 2026-06-30):** `mcp/mdeditor_mcp.py` (FastMCP, fork-and-own) shells to
`--control` and exposes `mdeditor_status` / `get_text` / `render_html` / `open_file` /
`new_document` / `run_command` / `export_html`. Contract tests mock the CLI (13/0); see
`mcp/README.md` for the `claude_desktop_config.json` block. **Next bite:** register + restart the
Claude app + in-app smoke; then `set_text` (needs a new `set-text` verb for large input).

## Files
- `MacDown/Code/Application/MPMainController.{h,m}` — verbs (open/command + read-back) + validators + JSON status.
- `macdown-cmd/{main.m,MPArgumentProcessor.{h,m}}` — `--control <url> [--bundle <id>]` GetURL direct-send / read-back.
- `MacDownTests/MPURLCommandTests.m` — headless contract tests for the validators.
- `Scripts/readback-smoke.sh` — GUI-session live smoke (headless windows) for the read verbs.
