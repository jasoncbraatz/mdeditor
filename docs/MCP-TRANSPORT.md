# mdeditor MCP transport — `x-macdown://` control surface (Phase 3)

> Status: **in progress.** This session landed the *command-push* half (verbs that drive
> the running app); the *read-back* half (capturing results on stdout for the MCP) is the
> next bite. SSOT for the phase: `docs/MASTER-PLAN.md` §6.

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
- Both validators are **pure functions** (no UI/document state) and are unit-tested headless
  in `MacDownTests/MPURLCommandTests.m`.

## Read-back (next bite — NOT done yet)
`open <url>` is fire-and-forget: LaunchServices does not return the AppleEvent reply to the
caller. The handler already *populates* a JSON reply descriptor, so the read-back path is to
send the `GetURL` AppleEvent **directly** (e.g. `NSAppleEventDescriptor`/`AESendMessage`
from a tiny helper, or extend `macdown-cmd`) and read `keyDirectObject` from the reply.
Then the FastMCP wrapper (`mcp/`, fork-and-own, per §6 step 3) shells to that and exposes
`open_file` / `run_command` / (later) `get_text` / `render_html` / `export_html`.

## Files
- `MacDown/Code/Application/MPMainController.{h,m}` — verbs + validators + JSON status.
- `MacDownTests/MPURLCommandTests.m` — headless contract tests for the validators.
