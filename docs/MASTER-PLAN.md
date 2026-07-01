# mdeditor — MASTER PLAN (multi-session)

> **Status doc. SSOT = this file in the `mdeditor` GitHub repo.** Each session, a Claude takes
> ONE bite (a phase or a sub-step), ships it, ticks the box, and improves this plan + the handoff.
> Paint-by-numbers on purpose: a zero-memory future Claude should be able to act from this alone.
>
> Owner: Jason (`jasoncbraatz`). Repo: `github.com/jasoncbraatz/mdeditor` (master = SSOT).
> Working copy on darwin: `~/Desktop/downloads/strike-zone/1216089018004712/macdown`.
> Toolchain: Xcode 26.6, CocoaPods 1.16.2. Fresh clone: `git submodule update --init --recursive && pod install`.
> Created 2026-06-29 (co-pilot cowork). Supersedes the ad-hoc "Open work" list in `mdeditor-SESSION-2026-06-29-launchfix.md`.

---

## 0. The North Star (read this first, every time)

mdeditor is Jason's daily markdown editor and is **"ours now"** — abandoned-upstream fork, we own
the whole stack. The goal of this plan is to turn it from "a fork that builds" into **a tool Jason
and future Claudes can co-develop safely, mostly without taking over his desktop.**

Three product goals, one architecture:

1. **A SOTA no-UI test harness** *(TOP PRIORITY)* — drive the app's behavior through a programmatic
   control surface that gets **as close to real UI controls as possible** (open docs, type, run
   bold/italic/heading/list commands, read the rendered preview), runnable headless in CI. The real
   AppKit UI then only has to *confirm what the harness already proves* — so day-to-day dev does not
   require commandeering Jason's daily-driver Mac.
2. **An MCP server that piggybacks on that same control surface** — so the Claude desktop app can
   open files, build/return documents, and exercise the editor through the *exact same intent-level
   commands the harness uses*. No second behavior path to maintain.
3. **A security audit + attack-surface reduction** — it's ours and Jason lives in `.md` all day; it
   must be auditable and hardened (WebView XSS is the #1 risk), with anything that opens an attack
   surface removed or locked down.

### The unifying idea — ONE control surface, three consumers

```
                 ┌─────────────────────────────────────────────┐
                 │   MPAutomation  (intent-level command API)   │
                 │  openDocument · newDocument(text) · text     │
                 │  setText · invokeCommand("toggleStrong") ·   │
                 │  renderedHTML · exportHTML · previewReady ·  │
                 │  diagnostics                                 │
                 └───────────────┬───────────────┬─────────────┘
            (in-process, headless)│               │(thin transport: CLI verb / URL / socket)
                 ┌────────────────▼───┐   ┌───────▼──────────┐   ┌──────────────────────┐
                 │  XCTest HARNESS     │   │  MCP server      │   │  Real AppKit UI       │
                 │  (Phase 1 — top)    │   │  (Phase 3)       │   │  (IBActions funnel    │
                 │  proves behavior    │   │  Claude app      │   │   through MPAutomation │
                 │  headless in CI     │   │  drives the app  │   │   = confirms harness) │
                 └─────────────────────┘   └──────────────────┘   └──────────────────────┘
```

The **same `MPAutomation` command registry** backs all three. Tests call it directly in-process; the
MCP reaches it over a thin transport; the GUI's toolbar/menu actions are refactored to *route
through it*. That is what makes "the UI just confirms what the harness can already confirm" literally
true rather than aspirational.

---

## 1. Cross-cutting rules (apply to EVERY bite)

- **Reversibility first.** Before changing anything: `git tag pre-<phase>` or a `.bak`. Create the
  undo path *before* the edit. Test the restore at least once per risky phase.
- **gh is the SSOT.** Reconcile in (`git pull --ff-only`) → work → sync out (commit + push)
  continuously. darwin holds the *working copy*; never bank only on darwin (it's an uninsured SSD —
  the missing `MPTestHarness.m` below is proof of what gets lost otherwise).
- **Student in / teacher out.** `lessons.py search "<task>" --scope global,strike-zone` before;
  `lessons.py add ...` after, for every hard-won fact.
- **One bite per session, then improve the handoff.** Don't try to eat the whole plan. Leave the
  next Claude a cushier oasis: tick boxes here, update the LUT (§9), refresh the handoff prompt.
- **Belt & suspenders.** When a phase looks done, look once more in a place you haven't checked.
  Headless test green ≠ GUI works; spot-check the real UI once at the end of UI-touching phases.

---

## 2. Current state — verified facts (2026-06-29)

| Area | Reality (verified this session) |
|---|---|
| Build | Release pinned to `GCC_OPTIMIZATION_LEVEL=0` (launch-path UB workaround, commit e645264). Builds clean on Xcode 26.6. |
| Install | `/Applications/mdeditor.app`, ad-hoc signed, bundle id `com.jasoncbraatz.mdeditor`. |
| Toolbar | Grouped-button crash FIXED (commit d0e2853) — dispatch via `sendAction:to:from:`. |
| **Test target** | ✅ GREEN. `MacDownTests` compiles & runs headless: **26 tests, 0 failures** (verified 2026-06-29, master, Xcode 26.6). `MPTestHarness.{h,m}` are **present and committed** at `MacDown/Code/Testing/` (commits `09cfad8` + `1da04da`) — NOT lost. The earlier "MISSING" claim was a wrong-directory check: it looked at `MacDownTests/MPTestHarness.*`, but the files live under `MacDown/Code/Testing/`. `MPTestHarnessTests` 6/6 incl. `testSequentialFileOpensWithIdle` (blank-canvas repro). Other tracked suites: `MPAssetTests`, `MPColorTests`, `MPHTMLTabularizeTests`, `MPPreferencesTests`, `MPStringLookupTests`, `MPUtilityTests`. **Cold-clone-safe as of `12fafb5`** — generated `pmh_parser.c` is now committed (was gitignored); a fresh clone builds first-try. |
| Harness spec (already written) | `MPTestHarnessTests.m` calls: `+openFileAtPath:error:`, `+openFileAtPath:timeout:error:`, `+isPreviewBlank`, `+previewText`, `+isPreviewReady`, `+isPreviewWebViewValid`, `+forceRefreshPreview`, `+simulateIdleForSeconds:`, `+diagnosticReport`. tearDown closes all `NSDocumentController` documents. |
| CLI | `macdown-cmd` target builds the `macdown` CLI. `MPArgumentProcessor` is minimal today (help/version/arguments only). Opening/piping handled in `MPMainController` via the prefs domain (see rename footgun, Phase 6). |
| URL scheme | `x-macdown://` declared (`CFBundleURLTypes`, name "Macdown custom control"). Good transport seed for the MCP. |
| Document types | Correct already: `CFBundleDocumentTypes` declares `md`/`markdown`, MIME `text/x-markdown`, UTI `net.daringfireball.markdown`, role **Editor**, `NSDocumentClass = MPDocument`. |
| Scripting | **No** AppleScript/`sdef`/`NSScriptCommand` support today. |
| CI | **No** GitHub Actions. Legacy `.travis.yml` only. |
| Updater | **Sparkle REMOVED** (commit 7627fef, 2026-06-30) — pod dropped, code/nib/plist refs gone; Debug build green, headless 51/0, no framework embedded. (was: disabled b40195c, pod still linked.) |
| Default-handler | Launch Services is polluted with ~17 registered bundles (old x86 `~/Desktop/downloads/MacDown.app`, DerivedData + `/tmp/ddopt|ddtest` copies, 3 AppTranslocation copies, Warp claiming markdown). This is why "set default" reverts. See Phase 3.5 / done-this-session note. `duti` is installed at `/opt/homebrew/bin/duti`. |

---

## 3. PHASE 0 — Foundations: get the harness target GREEN headless ✅ DONE (verified 2026-06-29)

**✅ STATUS: COMPLETE.** `xcodebuild test -workspace MacDown.xcworkspace -scheme MacDown -configuration Debug CODE_SIGNING_ALLOWED=NO` → **TEST SUCCEEDED, 26 tests / 0 failures** on master (2026-06-29). The premise below ("MPTestHarness is missing") was FALSE — the files exist at `MacDown/Code/Testing/MPTestHarness.{h,m}`, committed (`09cfad8`/`1da04da`) and pushed. No rebuild was needed. A thorough re-verification (2026-06-29) then went further: a **from-scratch clone** test exposed a real cold-build defect — the project compiles the *generated* `Dependency/peg-markdown-highlight/pmh_parser.c`, but it was gitignored with no pre-build phase producing it, so the FIRST build of a fresh clone failed (`Build input file cannot be found: pmh_parser.c`); a 2nd build passed because attempt #1 left the file behind. darwin's warm working copy hid this. **FIXED** (commit `12fafb5`): the generated parser is now committed. **Proven:** a brand-new clone now builds+tests green on the FIRST build (26/0, RC=0). **Next bite: Phase 1.**

**Goal (met):** `xcodebuild test` runs the existing `MacDownTests` to completion, headless, pass/fail visible. This is the floor everything stands on.

**Why:** You cannot have a "harness-first" workflow until the test target compiles and runs — it already does. (The steps below are retained as historical context for how the harness was built; they are no longer action items.)

**Steps (paint-by-numbers):**
1. Reconcile in. Confirm the gap: `git ls-files MacDownTests | grep TestHarness` (you'll see only
   the `*Tests.m`, no facade). `ls MacDownTests/MPTestHarness.* ` → missing.
2. Decide the home of the control surface. **Recommended:** create `MPAutomation` in the **app
   target** (`MacDown/Code/Automation/MPAutomation.{h,m}`) — NOT test-only — because Phase 3 (MCP)
   and the GUI refactor need it in the shipping binary. Make `MPTestHarness` a thin test-only shim
   that forwards to `MPAutomation` (keeps the existing spec compiling unchanged).
3. Implement the minimum `MPAutomation`/`MPTestHarness` API the spec needs (see §2 list). It must
   reach the running app objects in-process: `NSDocumentController.sharedDocumentController` to open
   files and get the current `MPDocument`; read the preview via the document's WebView (rendered
   HTML / DOM text); `forceRefreshPreview` calls the document's existing render path;
   `simulateIdleForSeconds:` spins the runloop (`[[NSRunLoop currentRunLoop] runUntilDate:]`), it must
   NOT `sleep()` (the WebView render is async on the main runloop).
4. Add `MPAutomation.{h,m}` to the **MacDown app target** and `MPTestHarness.{h,m}` (shim) to the
   **MacDownTests target** in `project.pbxproj`. Add the new files to git (this is the step that was
   missed before — *commit and push immediately* so they can't be lost again).
5. Make the test runnable headless. Standard invocation (see §7 runner). Some AppKit calls need a
   GUI session; darwin has Jason's logged-in session so `xcodebuild test` works locally. For true
   headless CI, prefer pure-logic tests + an `NSApplication` test host; gate WebView-dependent
   assertions behind availability so CI without a window server can still run the logic suite.
6. Acceptance: `xcodebuild test ... -scheme MacDown` exits 0 with a green `MPTestHarnessTests`
   (preview/blank-canvas scenarios) + the pre-existing unit suites. Capture the `.xcresult`.
7. Reversibility: all additive; `git tag pre-phase0` first. Nothing destructive.

**Files:** `MacDown/Code/Automation/MPAutomation.{h,m}` (new), `MacDownTests/MPTestHarness.{h,m}`
(new shim), `MacDown.xcodeproj/project.pbxproj` (target membership), `Scripts/test.sh` (new, §7).

**Done when:** ☑ test target compiles · ☑ `xcodebuild test` green headless (26/0, 2026-06-29) · ☑ new files committed+pushed (master `1da04da`) · ☑ **FRESH-CLONE first-build green** (cold-build defect found+fixed `12fafb5`; verified by a brand-new clone, 26/0 RC=0).

---

## 4. PHASE 1 — The harness as UI-grade control surface *(TOP PRIORITY)*

> **PROGRESS 2026-06-29 (commits `6ae2634`, `a29aea0`).** The harness now affords driving EVERY
> toolbar/menu editing action one-by-one, **headless**: a command registry (`+invokeCommand:error:`
> over stable ids → the 31 `MPDocument` IBActions), editor input (`setMarkdown`/`selectRange`/
> `selectSubstring`/…), layout-state getters, and a **no-flicker headless mode** (app = accessory;
> document windows transparent + off-screen; process-only env flag). 44 tests / 0 failures, fully
> headless (verified: 2 docs + switch, zero on-screen windows). Reference: `docs/TEST-HARNESS.md`;
> coverage + pre-ship pipeline: `docs/TEST-MATRIX.md`; runner: `Scripts/test.sh`.
> **UPDATE 2026-06-29 (co-pilot):** the GUI-routing refactor is DONE — registry moved to the app
> target on `MPDocument`; all 32 IBActions delegate into it; harness is a façade over it; 44/44 green.
> See the "PHASE 1 ~DONE" note under "Done when" below. **Remaining for Phase 1:** just the human GUI
> parity spot-check (the every-5th-handoff UI pass, §11 — not due yet). Optional polish carried to
> §5/TEST-MATRIX §5: the cheap-win round-trips (h4–h6, link/image w/ seeded pasteboard, view-toggle
> state asserts). The app-target `MPAutomation` idea was dropped as unnecessary (the document is the
> control surface; the MCP calls `invokeCommandID:` directly).


**Goal:** Grow `MPAutomation` until it can drive **every user-facing editing action** the toolbar &
menus expose, and read back the result — so a test (or the MCP, or an auto-tester) can do anything a
human does in the UI, headless.

**Why:** This is the heart of the whole plan and Jason's #1 ask. It is also our best bug net — it
would have caught BOTH the no-UI launch bug (preview-blank scenarios already in the spec) AND today's
toolbar crash (had a command-dispatch test existed).

**Steps:**
1. **Command registry.** Enumerate the editing commands from `MPDocument` IBActions
   (`toggleStrong:`, `toggleEmphasis:`, `toggleUnderline:`, `toggleInlineCode:`,
   `toggleStrikethrough:`, `toggleHighlight:`, `toggleComment:`, `toggleLink:`, `toggleImage:`,
   `convertToH1:`…`convertToH6:`, `convertToParagraph:`, `toggleOrderedList:`,
   `toggleUnorderedList:`, `toggleBlockquote:`, `indent:`, `unindent:`, `copyHtml:`). Map each to a
   **stable string id** (e.g. `"strong"`, `"emphasis"`, `"h1"`, `"ul"`). Expose
   `-invokeCommand:(NSString*)id error:` on `MPAutomation`.
2. **Editor I/O.** `currentText`, `setText:`, `selectRange:`, `selectedText`, `replaceSelection:`.
3. **Render readback.** `renderedHTML`, `previewPlainText`, `previewReady`, `exportHTMLToPath:`.
4. **Refactor the GUI to funnel through the registry.** Make `selectedToolbarItemGroupItem:` and the
   IBActions call `MPAutomation invokeCommand:` (or have the registry be the single implementation
   the IBActions delegate to). THIS is what makes "UI confirms what the harness proves" real.
   Keep it behavior-preserving; the toolbar fix from d0e2853 stays.
5. **Regression tests** (`MacDownTests/MPCommandTests.m`, new):
   - For each command id: set known text + selection → `invokeCommand` → assert exact resulting
     markdown. (e.g. select `boldcheck` → `"strong"` → `**boldcheck**`.)
   - A crash-safety sweep: invoke every command on empty doc / no selection / out-of-range — must
     not crash (the class of bug d0e2853 fixed).
   - Heading/list idempotency & toggle-off.
6. **Acceptance:** every command has a green round-trip test; the suite is the contract. Spot-check
   the real GUI once (open app, click a couple buttons) to confirm parity — should match the tests.
7. Reversibility: `git tag pre-phase1`; GUI refactor is behavior-preserving and covered by the new
   tests (run them before/after).

**Done when:** ☑ command registry (`+invokeCommand:`) · ☑ GUI routes through it · ☑ per-command round-trip tests green ·
☑ crash-safety sweep green · ☑ GUI parity spot-check (human/computer-use, TEST-MATRIX §3 — **done 2026-06-30, ledger row 5**).

> **PHASE 1 ~DONE (commit pending, 2026-06-29).** The command registry now lives in the **app
> target** on `MPDocument` (`+availableCommandIDs`, `-invokeCommandID:sender:error:`, private
> `mp_commandRegistry` of id→work blocks). **All 32 editing IBActions are now one-line delegations
> into it** — so the menu (responder chain) and the toolbar (`sendAction:`, d0e2853 path untouched)
> reach the editing commands through the *same* registry the harness/MCP use. The `MPTestHarness`
> registry is now a thin façade over the document's (`availableCommands`/`invokeCommand:` forward to
> it; the old test-only `commandSelectorMap` was removed). `link`/`image` de-duped into one helper.
> Behavior-preserving: **44/44 green headless** before AND after (`Scripts/test.sh`). Reversible:
> tag `pre-phase1-gui-route`. The remaining unticked box is the **human GUI parity spot-check**,
> which is the every-5th-handoff UI pass (see §11) — **DONE 2026-06-30 (ledger row 5): launch/preview, toolbar parity, HTML+PDF export, and the `x-macdown://command?id=h1` live smoke all green via computer-use.** An app-target
> `MPAutomation` (vs. the registry living on `MPDocument`) was deemed unnecessary surgery: the
> document IS the natural in-process control surface; Phase 3's MCP can call `invokeCommandID:`
> directly. Files: `MPDocument.{h,m}`, `MPTestHarness.{h,m}`.

---

## 5. PHASE 2 — SOTA CI/CD

**Goal:** Every push runs the harness in the cloud; coverage + result artifacts visible; red bar
blocks merges. Local fast loop too.

**Steps:**
1. **Local:** `Scripts/test.sh` (xcbeautify-piped `xcodebuild test`, `-enableCodeCoverage YES`,
   `-resultBundlePath build/last.xcresult`). A `Scripts/pre-push` git hook that runs the logic suite.
2. **Cloud:** `.github/workflows/ci.yml` on `macos-15` (or latest GH image w/ Xcode 26): **check out a
   FRESH CLONE** (no darwin working-copy state), cache Pods, `pod install`, `xcodebuild build` + `test`,
   upload `.xcresult` + coverage as artifacts, fail on test failure or `xcodebuild analyze` warnings.
   Matrix: Debug + Release (Release catches the kind of `-Os`/optimization regressions we hit). The
   fresh-clone build is also our **mechanical guard for HANDOFF-GATE G-S #45**: a source file that was
   saved only on darwin and never committed (how `MPTestHarness.{h,m}` was lost) fails to compile here
   even when darwin's dirty checkout builds green.
3. Decommission `.travis.yml` (dead) — remove or replace; note in commit why.
4. **Acceptance:** a PR shows a green check; an intentionally-broken command turns it red.
5. Reversibility: CI is additive; deleting `.travis.yml` is reversible via git.

**Done when:** ☑ `Scripts/test.sh` · ☑ pre-push hook (`Scripts/pre-push` + `Scripts/install-git-hooks.sh`) · ☑ GH Actions **GREEN from a fresh clone** (`.github/workflows/ci.yml`, `macos-26`/Xcode 26, Debug+Release matrix — G-S #45 guard; verified run [28405776615](https://github.com/jasoncbraatz/mdeditor/actions/runs/28405776615) @ `eba20dc`, all jobs green incl. informational analyze) · ☑ coverage artifact (xcresult uploaded + xccov summary) · ☑ `.travis.yml` retired.

---

## 6. PHASE 3 — MCP server (piggyback on MPAutomation)

> **PROGRESS 2026-06-30 (co-pilot, commit `46d7bfe`).** Landed the **command-push** half of
> the transport: extended the existing `x-macdown://` AppleEvent handler with a `command` verb
> (`x-macdown://command?id=<id>`) routing 1:1 to `-[MPDocument invokeCommandID:sender:error:]`
> on the front document — same registry the harness drives. Added two pure, allowlist-style
> validators on `MPMainController` (`+validatedCommandID:`, `+validatedFileURLFromParam:`) and
> routed the pre-existing `open` verb through the file-URL guard (Phase 4 pre-pay). Handler now
> emits a JSON status into the AppleEvent reply (seeds read-back). Headless contract tests
> (`MacDownTests/MPURLCommandTests.m`, 5) cover both validators; full suite **49/0** Debug.
> Trust model + verb contract: `docs/MCP-TRANSPORT.md`. **Next bite:** read-back (send the
> `GetURL` AppleEvent directly + read the reply) → then the FastMCP wrapper (`mcp/`). The live
> GUI smoke of `command` folds into the §11 handoff-#5 UI pass (fire `x-macdown://command?id=h1`
> end-to-end).

> **PROGRESS 2026-06-30 (co-pilot, read-back).** Landed the **read-back** half. The
> handler gained four read verbs — `get-text` / `render-html` / `export-html?path=file://…`
> / `status` — that return the front `MPDocument`'s state in the JSON reply (shared
> `-mp_frontDocumentOrNil`; export gated by a new `+validatedExportPathFromParam:` that
> requires an absolute `.html`/`.htm` `file://` path, Phase-4 write-surface guard). The
> CLI `macdown-cmd` gained `--control <url> [--bundle <id>]`, which sends the `GetURL`
> AppleEvent **directly** (`AESendMessage`, waits for the reply) and prints the JSON —
> because `open` is fire-and-forget and drops the reply. Headless suite **51/0** (+2
> export-path validator tests). **KEY FINDING:** the live cross-process smoke is
> **GUI-session-only** — AppleEvents do NOT cross from a non-GUI ssh session into the GUI
> app (send returns "no reply"; `launchctl asuser` → "Could not switch to audit session …
> Operation not permitted"). So the live tick must come from Jason's login session:
> repo'd **`Scripts/readback-smoke.sh`** launches the fresh Debug build *headless*
> (`MPHeadlessTestMode=1`, no visible window), fires all four verbs, and quits. Live tick
> pending that run. **Next bite:** the FastMCP wrapper (`mcp/`, fork-and-own) over
> `--control`, then per-tool contract tests + Claude-app smoke.

> **PROGRESS 2026-06-30 (co-pilot, FastMCP).** Built the MCP server `mcp/mdeditor_mcp.py`
> (Python FastMCP, fork-and-own, repo-backed) — 7 tools (`status`, `get_text`, `render_html`,
> `open_file`, `new_document`, `run_command`, `export_html`) that shell to `macdown --control`
> and return the handler's JSON. `new_document(text)` writes a temp `.md` and reuses the `open`
> verb (no new transport verb). Contract tests `mcp/test_mdeditor_mcp.py` **mock the CLI** and
> assert each tool's verb/URL mapping + JSON/error contract (**13/0**, run anywhere); the server
> also lists all 7 tools with clean schemas. `mcp/README.md` has the config block + verbs;
> `mcp/mcp-live-smoke.sh` drives the real app through the MCP code (GUI session). **Deferred:**
> `set_text` (needs a new `set-text` transport verb to carry large input off-URL). **Next bite:**
> register in the Claude desktop config + restart + in-app smoke ("make a doc that says X and
> open it"); then optionally `set_text` + publish to the MCP registry.

**Goal:** The Claude desktop app can open files, push/build documents, read rendered output, and run
editing commands in mdeditor — through the **same** `MPAutomation` surface the harness uses.

**Design decision (Jason, 2026-06-29):** MCP is a *piggyback* on the harness control surface, not a
separate behavior path. Transport recommendation (lowest surgery, reuses what exists): extend the
`macdown` CLI and/or the `x-macdown://` URL scheme with verbs that map 1:1 to `MPAutomation`
commands; the MCP shells to those. Phase later to a richer AppleScript `sdef` only if needed.

**Steps:**
1. **Transport.** Extend `MPArgumentProcessor` + `macdown-cmd` (or add `x-macdown://command?...`
   handling in `MPMainController`) with verbs: `open <path>`, `new --stdin`, `get-text`, `set-text`,
   `render-html [--out p]`, `cmd <id>`, `export-html <out>`, `status`. Each routes to `MPAutomation`
   on the main thread of the running app (launch if needed). Return results on stdout as JSON.
2. **Security on the transport (do NOT skip — see Phase 4).** Validate/normalize paths; refuse paths
   outside an allowed set unless explicitly passed; never `eval`/exec content; the URL scheme must
   reject command injection; document the trust model.
3. **MCP server** (`mcp/` — Python FastMCP, fork-and-own; its own files, repo-backed). Tools:
   `open_file(path)`, `new_document(text)`, `get_text()`, `set_text(text)`, `render_html()`,
   `run_command(id)`, `export_html(path)`. Thin wrappers over the CLI/URL transport. Follow the
   `mcp-builder` skill conventions. Reuse Jason's existing MCP patterns (see other `~/Scripts/*-mcp`).
4. **Wire to Claude app**; smoke test: "make a document that says X and open it in mdeditor."
5. **Acceptance:** from a fresh Claude session, drive a full open→edit→render→export cycle via MCP;
   each MCP tool has a contract test that exercises the same `MPAutomation` path the harness covers.
6. Reversibility: new files only; transport verbs are additive and behind explicit args.

**Done when:** ☑ transport verbs (☑ `open`+`command` push; ☑ read-back verbs `get-text`/`render-html`/`export-html`/`status` + `--control` GetURL direct-send — headless 51/0 AND ☑ live in-session smoke GREEN 2026-06-30 via `Scripts/readback-smoke.sh`) · ☑ input validation (+`validatedExportPathFromParam:`) · ☑ FastMCP server (`mcp/`, 8 tools incl. `set_text`) · ☑ **Claude-app smoke (register + restart + live in-app round-trip GREEN from a Claude session, 2026-06-30, Bite A)** · ☑ MCP contract tests (validator + per-tool, 14/0) · ☑ live MCP round-trip GREEN (`mcp-live-smoke.sh`). **→ PHASE 3 COMPLETE.**

> **Known cosmetic glitch (teed up, LOW pri — found 2026-06-30 during the §11.2 pass).** Applying an
> inline-format command (e.g. bold via ⌘B / toolbar) **occasionally** leaves a one-frame ghost: the
> old (larger, un-bolded) glyph run paints under the new `**word**` run on the edited line. It is
> **intermittent** (did not reproduce on a 2nd attempt) and **self-heals** on the next redraw (scroll,
> keystroke, relaunch). Text + preview are always correct — purely visual. Root cause: a redraw/
> invalidation race at the seam between MacDown's *async* `HGMarkdownHighlighter` re-attributing the
> range and AppKit's `NSTextView`/`NSLayoutManager` layout after a programmatic edit. **Fix when
> convenient:** after `invokeCommandID:`/an inline edit, force a redraw of the edited line range
> (`invalidateDisplayForCharacterRange:` or a synchronous re-highlight). Don't bank a hard negative
> lesson (intermittent → dated-negative autophagy risk); re-test before trusting.

---

## 7. PHASE 4 — Security audit & attack-surface reduction

> **PROGRESS 2026-06-30 (co-pilot, Phase 4 kickoff).** Hit-list **item 2 (Sparkle) DONE** — fully removed (commit 7627fef): pod dropped (`pod install`→"Removing Sparkle"), `#import <Sparkle/SUUpdater.h>` + `feedURLStringForUpdater:` deleted, the `SUUpdater` object + "Check for Updates…" menu item removed from `MainMenu.xib`, dead `SUEnableAutomaticChecks` plist key removed. Debug build green, headless **51/0**, no `Sparkle.framework` embedded, GUI launch eyeball (computer-use) confirms full menu bar + item gone. Also **scaffolded `docs/SECURITY-AUDIT.md`** (threat model + 9 findings, decisions log). **Next bite = item 1, WebView XSS** (the #1 risk; recon is in SECURITY-AUDIT §1: legacy JS-enabled `WebView`, `loadHTMLString:` at `MPDocument.m:1170`, unsanitized hoedown HTML, and the existing `willSendRequest:` hook at `MPDocument.m:868` as the remote-load choke point). Findings 3/4/5/7/8/9 are teed up in SECURITY-AUDIT as smaller follow-on bites.

> **PROGRESS 2026-06-30 (co-pilot, item 1 — WebView XSS hardening).** The #1 risk is MITIGATED with
> 3 layers: (a) `MPSanitizeHTMLBody()` (MPRenderer.m) sanitizes the hoedown body `currentHtml` at the
> source (strips script/iframe/object/embed + `on*=` + neutralizes javascript:/vbscript:/non-image
> data: — covers preview+export+copy+MCP); (b) a strict CSP `<meta>` in `Default.handlebars` (egress
> locked to local origins; `'unsafe-inline'`/`'unsafe-eval'` kept so bundled Prism/MathJax run); (c)
> `+[MPDocument mp_isAllowedPreviewResourceURL:]` in `willSendRequest:` cancels remote subresource
> loads (anti-beacon/SSRF). +16 tests (`MPXSSHardeningTests`), headless **67/0** Debug, live preview
> eyeball GREEN (script/onerror did not fire; legit md+Prism+table render). Reversible: tag
> `pre-phase4-xss`. **Scoped, not done:** WKWebView migration (process isolation). **Next bites**
> (SECURITY-AUDIT): finding 3 ATS (now that remote loads are blocked, drop `NSAllowsArbitraryLoads`
> + the dead `uranusjr.com` exception), finding 4 AppleScript sdef, finding 5 Hardened Runtime,
> finding 7 parser fuzz, finding 8 CVE sweep.

> **PROGRESS 2026-06-30 (co-pilot, plist/hardening cluster — findings 3+4+5 DONE).** All three
> small reversible plist/build legs shipped in one bite. **(3) ATS:** `NSAllowsArbitraryLoads`→`false`
> and the whole `NSExceptionDomains` dict removed (both `cdnjs.cloudflare.com` and dead `uranusjr.com`)
> — every preview subresource is bundled (Prism, MathJax) and the MathJax CDN URL is rewritten to the
> bundled file in `willSendRequest:` before any network load, so no exception is load-bearing (no other
> network API in the app). **(4) AppleScript:** `NSAppleScriptEnabled` + dangling `OSAScriptingDefinition`
> (→ non-existent `MacDown.sdef`) removed; `x-macdown` URL scheme preserved. **(5) Hardened Runtime:**
> `ENABLE_HARDENED_RUNTIME = YES` on both app build configs (prereq for Phase-7 notarization; App Sandbox
> deferred as a larger bite). Headless **67/0**; GUI launch+render eyeball GREEN (separate `open -n`
> instance so a running Debug instance with Jason's unsaved doc was untouched). Reversible: tag
> `pre-phase4-plist-hardening`. SECURITY-AUDIT findings 3/4 = DONE, 5 = PARTIAL (HR done, Sandbox open).
> **Next bites** (SECURITY-AUDIT): finding 7 parser fuzz (hoedown+pmh under ASan/UBSan), finding 8 CVE
> sweep (LibYAML 0.1 first), or finding 5 App Sandbox (bigger).

> **PROGRESS 2026-06-30 (co-pilot, finding 8 — dependency CVE sweep DONE).** All 8 pods enumerated
> vs known CVEs (table in SECURITY-AUDIT §8). One real reachable vuln found & fixed: **LibYAML 0.1.4
> CVE-2014-2525** — heap overflow in `yaml_parser_scan_uri_escapes` (no `STRING_EXTEND` before the
> octet copy), reachable via a malicious `.md`'s YAML front-matter (`NSString+Lookup -[frontMatter:]`
> -> `YAMLSerialization` -> LibYAML). The CocoaPods `LibYAML` spec is frozen at 0.1.4 (no patched
> release), so the official upstream guard is applied via a **`Podfile` `post_install` hook**
> (idempotent, chmods the read-only pod source, CI-safe); canonical patch
> `Scripts/patches/libyaml-cve-2014-2525.patch`. Verified: patch lands `scanner.c:2714`, build green,
> headless **67/0**. Tag `pre-cve-libyaml`. Other 7 pods clean. hoedown 3.0.7 = no formal CVE; its
> memory-safety is finding 7 (ASan fuzz), into which the YAML URI-escape path is also folded.
> **Next bites** (SECURITY-AUDIT): finding 7 parser fuzz (hoedown + pmh + the LibYAML scanner under
> ASan/UBSan), or finding 5 App Sandbox (bigger).

> **PROGRESS 2026-06-30 (co-pilot, finding 7 — parser fuzz first pass).** Built ASan/UBSan
> harnesses + adversarial corpus, repo-backed at `Scripts/fuzz/` (`build.sh`/`run.sh`,
> standalone clang — no app build). Found **5 defects, all the deep-nesting / unbounded-
> recursion class** (clean on the other 31 inputs): **7a** hoedown `parse_block`
> stack-overflow, **7b** pmh `yymatchChar` stack-overflow + `yySet` **heap**-overflow,
> **7c** LibYAML `yaml_parser_load_node` stack-overflow. Also **independently ASan-
> validated the LibYAML CVE-2014-2525 fix** (guard-removed control heap-overflows on the
> PoC; patched build clean). **7a root cause:** `kMPRendererNestingLevel = SIZE_MAX`
> defeats hoedown's built-in `max_nesting` guard, and `parseMarkdown:` runs on the 512KB
> `parseQueue` stack (overflow floor ~2000-3000 @-O0). **Fix = cap at 1000**, proven
> product-safe (clean over corpus; byte-identical shallow output) — but it **hangs
> `testCommand_blockquote`** via a test-harness render-wait race (NOT a product change),
> so it is **NOT landed** (tree stays SIZE_MAX; headless stays 67/0). Tag `pre-fuzz`.
> **Next bite:** de-flake the harness render-wait, land the cap, then 7b (fork-and-own the
> generated pmh val-stack) + 7c (LibYAML depth cap via post_install). Detail: SECURITY-AUDIT #7.

> **PROGRESS 2026-06-30 (co-pilot, finding 7a — nesting cap LANDED + render-wait de-flake).**
> Capped `kMPRendererNestingLevel` SIZE_MAX→**1000** (`MPRenderer.m`), closing the
> `deep_blockquote` `parse_block` stack-overflow on the 512KB `parseQueue` stack
> (`hoedown_thread deep_blockquote 1000` rc 0; unguarded SIZE_MAX rc 138). Output below
> depth 1000 is byte-identical. The prior handoff's blocker — "cap deterministically hangs
> `testCommand_blockquote` via a render-wait race" — was **misdiagnosed**: a `sample` of the
> wedge showed XCTest failure-**symbolication blocking in `open()`** (DebugSymbols/Spotlight)
> after an issue is recorded, triggered by main-thread starvation from a busy-spin in
> `parseAndRenderWithMaxDelay:` (a dead `|| [start timeIntervalSinceNow] >= maxDelay` term).
> De-flaked that loop (yield + 5s safety deadline; termination unchanged) → **7/7 clean**
> full-suite runs at cap=1000; `testCommand_blockquote` also passes in isolation (0.22s).
> `Scripts/fuzz/run.sh` now runs the main hoedown loop at the product cap (`MDFUZZ_NESTING=1000`),
> drops `deep_blockquote` from KNOWN_OPEN, and adds a positive control → **PASS** (4 known-open
> 7b/7c, 0 new). Headless **67/0**. Tags `pre-7a-deflake`/`pre-7a-land`. **Next bites:** 7b
> (pmh fork-and-own: grow/bound the leg val-stack — the `yySet` heap-overflow is higher priority),
> 7c (LibYAML depth cap via `post_install`), finding 5 (App Sandbox), finding 9 (`analyze`
> CI-blocking + wire `Scripts/fuzz/run.sh` in as a gate).

**Goal:** It's ours and auditable. Remove/lock down anything that's an attack surface. Bank a written
audit. (Was "Priority 2" in the original brief — now a first-class phase.)

**Hit list (highest payoff first):**
1. **Preview WebView = #1 XSS surface.** Legacy `WebView` + `loadHTMLString:` + JS-enabled (for
   Prism) renders attacker-controllable markdown→HTML. Actions:
   - Sanitize md-derived HTML (strip `<script>`, `on*=` handlers, `javascript:` URLs).
   - Add a strict **CSP** to the rendered document; disable JavaScript-from-content where possible
     (keep only what Prism needs, or pre-render highlighting at build time).
   - Decide on **blocking remote resource loads** (a malicious `.md` shouldn't beacon out / SSRF).
   - Evaluate **migrating to `WKWebView`** (process isolation, modern security model) — big, scope it.
2. **Remove Sparkle entirely.** It's disabled (b40195c) but the pod is still linked → dead code +
   network/update surface. Remove from Podfile + project; verify build + launch.
3. **Fuzz the C parsers under ASan.** `hoedown 3.0.7` + `Dependency/peg-markdown-highlight/
   pmh_parser.c` with malformed/adversarial `.md`. Fix or wrap any crash/UB. (Ties to Phase 5.)
4. **`xcodebuild analyze`** clean; treat new analyzer findings as CI-blocking (Phase 2).
5. **Dependency CVE sweep.** hoedown, Sparkle (until removed), and the rest of the Podfile.
6. **App hardening posture.** Review entitlements, App Sandbox feasibility, Hardened Runtime,
   `NSAllowsArbitraryLoads`/ATS, and the `x-macdown://` + CLI transports (Phase 3) as *local* attack
   surfaces — validate all inputs, no arbitrary file read/exec.
7. **Write `docs/SECURITY-AUDIT.md`** — findings, decisions, residual risk. Use the `security-review`
   + `code-review` skills.

**Done when:** ☑ WebView hardened (sanitize+CSP+remote-load block, 2026-06-30) · ☑ Sparkle removed (7627fef, 2026-06-30) · ☐ parser fuzz
clean (☐ — 1st fuzz pass done 2026-06-30: 5 deep-nesting overflows; 7a fix identified+proven-safe, NOT landed yet (test race); 7b/7c open; harness at `Scripts/fuzz/`) · ☐ analyze clean · ☑ CVE sweep (2026-06-30, LibYAML 0.1.4 CVE-2014-2525 patched) · ☐ hardening review · ☑ `SECURITY-AUDIT.md` banked (living doc, 9 findings, 2026-06-30).

---

## 8. PHASE 5/6/7 — Carryovers & polish (smaller bites)

- **PHASE 5 — Narrow the `-Os` UB, restore optimization.** Per-file `-O0` bisect of the main-nib
  instantiation path (suspects: `MPMainController` init/copyFiles, `MPPreferences`, early
  `+load`/`+initialize`) to find the offending TU/line; fix the UB; restore Release optimization.
  *Re-run the Phase 1 command tests afterward* — optimization changes ARC retain codegen, which is
  exactly what surfaced today's toolbar crash. verify start: `grep -n GCC_OPTIMIZATION_LEVEL
  MacDown.xcodeproj/project.pbxproj`. ☐
- **PHASE 6 — Finish the rename (live footgun).** `MacDown/Code/Utility/MPGlobals.h` still has
  `kMPApplicationName=@"MacDown"`, `kMPApplicationBundleIdentifier=@"com.uranusjr.macdown[-debug]"`,
  `kMPApplicationSuiteName=@"com.uranusjr.macdown"`. The **suite name** is live: mdeditor reads OLD
  MacDown's prefs domain for `filesToOpen`/`pipedContent` — fix all three → mdeditor identity,
  rebuild Release, verify launch + open/pipe still work. verify start: `grep -n uranusjr
  MacDown/Code/Utility/MPGlobals.h`. ☐
- **PHASE 7 — Packaging & "make default" UX.** Proper signing → notarization; a tiny installer/script
  that registers mdeditor and sets it as the default `.md` handler cleanly (see done-this-session
  note for the `duti` recipe and the LS-pollution caveat). ☐
- **Housekeeping (Jason to triage):** untracked `MacDown/Resources/Styles/GitHub-2020.css` (**0 bytes — looks like an accidental `touch`; safe scratch**) `REDO-PROMPT.md` (historical session log, SUPERSEDED by this plan) is now **tracked & archived** at `docs/archive/REDO-PROMPT-2026-06-29-launchfix.md` (2026-06-30, Jason's call — repo-back it). Remaining: the 0-byte `GitHub-2020.css` — keeper or scratch? ☐

---

## 9. LUT — facts a future Claude should not pay tokens to re-derive

- **CI (Phase 2):** `.github/workflows/ci.yml` on `macos-26`/Xcode 26, fresh clone (submodules recursive) → `pod install --repo-update` (Pods cached on `Podfile.lock`) → `xcodebuild test` Debug+Release. **The Release leg MUST pass `ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES`** or MacDownTests fails to link (Release defaults testability NO → undefined app symbols; and Sparkle 1.18 is single-arch). Coverage = `.xcresult` artifact + xccov step-summary. `analyze` job is informational (continue-on-error) until Phase 4 cleans the C. `Scripts/pre-push` runs `Scripts/test.sh` (Debug only) before any push; install via `Scripts/install-git-hooks.sh`; skip with `PRE_PUSH_SKIP=1` / `--no-verify`.
- **gh footgun:** this working copy has remotes `origin`=jasoncbraatz/mdeditor AND `upstream`=MacDownApp/macdown, so bare `gh` resolves to UPSTREAM. Default is now pinned (`gh repo set-default jasoncbraatz/mdeditor`); if a future clone misbehaves, pass `-R jasoncbraatz/mdeditor`.
- **xcodeproj gem footgun (adding a test file):** `Xcodeproj` 1.27.0 is bundled with CocoaPods — load it with `GEM_HOME=/opt/homebrew/Cellar/cocoapods/1.16.2_2/libexec /opt/homebrew/opt/ruby/bin/ruby` (the bare `/opt/homebrew/bin/ruby` lacks it). When adding a file with `group.new_reference('MacDownTests/Foo.m')`, the ref path is taken **literally**, so inside the `MacDownTests` group (which already has `path = MacDownTests`) it resolves to `MacDownTests/MacDownTests/Foo.m` (doubled, build-input-not-found). Fix: set `ref.path = 'Foo.m'` (basename, group-relative) like the siblings. Always assert `ref.real_path` matches a sibling before saving.
- **MCP transport (Phase 3):** the `x-macdown://` scheme is the transport (existing `kAEGetURL` AppleEvent handler in `MPMainController`). Verbs: `open?url=file://…` and `command?id=<registry id>`. Inputs are allowlist-validated by pure class methods `+[MPMainController validatedCommandID:]` / `+[MPMainController validatedFileURLFromParam:]` (unit-tested in `MPURLCommandTests`). `open <url>` is fire-and-forget (LaunchServices drops the reply); read-back = send `GetURL` directly and read `keyDirectObject`. Full notes: `docs/MCP-TRANSPORT.md`.
- **MCP read-back (Phase 3):** read verbs return the front doc's state in the JSON reply — `get-text` (=`MPDocument.markdown`=`editor.string`), `render-html` (=`MPDocument.html`=`renderer.currentHtml`), `export-html?path=file://…` (writes that html to a validated `.html`/`.htm` path via `+validatedExportPathFromParam:`), `status` (hasDocument/previewReady/commandCount/textLength). Capture path = CLI `macdown-cmd --control <url> [--bundle <id>]` → sends `GetURL` via `AESendMessage` (waits for reply) and prints `keyDirectObject`. `open` can't be used (fire-and-forget drops the reply).
- **MCP server (Phase 3):** `mcp/mdeditor_mcp.py` (FastMCP, fork-and-own, repo-backed). Run with `/opt/homebrew/bin/python3`; 7 tools shell to `macdown --control` (helper `_control` → subprocess → JSON). Tools take a `params: <PydanticInput>` arg (Jason's fintable house style — nested `params`, proven in his desktop config). Config block + verbs: `mcp/README.md`. Contract tests (mock the CLI, run anywhere): `/opt/homebrew/bin/python3 -m unittest mcp/test_mdeditor_mcp.py` (13/0). Live round-trip (GUI session): `mcp/mcp-live-smoke.sh`. `set_text` lands via the `set-text` verb: `x-macdown://set-text?file=file://<tmp>` — the handler reads that file as UTF-8 and sets `doc.markdown` (+`forceRefreshPreview`); the MCP writes a temp `.md`, passes it, and deletes it after. Text rides in the FILE, never the URL (no length/encoding limits). 8 tools now.
- **READ-BACK IS GUI-SESSION-ONLY (hard-won 2026-06-30):** you CANNOT drive the live AppleEvent read-back from a non-GUI ssh session — the send returns `"no reply from app"`, and `launchctl asuser $(id -u) …` fails with `Could not switch to audit session … Operation not permitted`. Run the live smoke from Jason's login-session Terminal: `bash Scripts/readback-smoke.sh` (launches the fresh Debug build with `MPHeadlessTestMode=1` so windows are invisible, fires all 4 verbs, quits). Headless XCTest still covers the validators + JSON plumbing; only the cross-process hop needs the GUI session.
- **`open -b <bundleid>` / bundle-id AppleEvents route via LaunchServices to whatever Debug app is REGISTERED for that id — possibly a STALE DerivedData copy, not your `build/ddata` build.** (A live smoke fired at `com.jasoncbraatz.mdeditor-debug` opened an old `…autgfsmbucav…` DerivedData build, which lacks new verbs.) For a live smoke, launch the freshly-built binary DIRECTLY (kill stale first) so the event reaches your build. Extends the §11.2 bare-`open` footgun.
- **GBCli (macdown-cmd) flags:** a value-taking option is `GBValueRequired` (NOT `GBOptionRequiresValue` — that identifier doesn't exist and fails to compile); `GBOptionNoValue` is the on/off switch. Read parsed values with `[settings objectForKey:@"<long>"]`.
- **Headless-window flag is `getenv("MPHeadlessTestMode")` on `MPDocument.m` (~line 392), NOT XCTest-gated** — set it in the environment on a NORMAL launch and the app's document windows go transparent+off-screen. That's how `Scripts/readback-smoke.sh` runs a live smoke without taking over the desktop.
- **Where the transport code lives (saves a hunt):** the CLI tool sources are in **`macdown-cmd/`** at the *repo root* (NOT under `MacDown/`): `main.m` + `MPArgumentProcessor.{h,m}`; pbxproj target name `macdown-cmd`, product `macdown`. The CLI is fire-and-forget: it stashes file paths / piped content into the prefs **suite** (`kMPApplicationSuiteName`, keys `filesToOpenOnNextLaunch`/`pipedContentFileToOpenOnNextLaunch`) then launches the app, which drains them in `-[MPMainController openPendingFiles]`/`openPendingPipedContent` (`applicationDidBecomeActive:`). The live-app control path is the `x-macdown://` **AppleEvent handler** `-[MPMainController openUrlSchemeAppleEvent:withReplyEvent:]` → `-mp_handleControlURLString:`. Editing commands + their stable ids live on **`MPDocument`** (`+availableCommandIDs`, `-invokeCommandID:sender:error:`).

- Test harness: `docs/TEST-HARNESS.md` (every call), `docs/TEST-MATRIX.md` (coverage + pre-ship pipeline), `Scripts/test.sh` (headless runner). Headless mode auto-enables under XCTest — windows go transparent+off-screen (alpha 0 is the real guarantee; AppKit clamps off-screen position to a sliver). Flag is the PROCESS-ONLY env var `MPHeadlessTestMode` (never NSUserDefaults — that would hide the real app).
- Build/install/verify recipe: see `mdeditor-SESSION-2026-06-29-launchfix.md` §"Build/install recipe".
  DerivedData: `~/Library/Developer/Xcode/DerivedData/MacDown-ayupkpyrvtmaxbcnyzlnauvioyai/...`.
- Release is `-O0` on purpose (e645264). Don't "optimize" it without doing Phase 5.
- Toolbar group dispatch must pass full ObjC signature — see global lesson `objc method imp arity`.
- `MPTestHarness.{h,m}` were NOT lost — they live at `MacDown/Code/Testing/` (committed `09cfad8`/`1da04da`, on master), test target green 26/0. A past handoff/plan wrongly said "MISSING" by checking the wrong dir (`MacDownTests/`). Lesson still stands: **commit + push new files the same session** so a darwin-only save can't strand them — and when a file looks "lost," `git log --all --oneline -- '*Name*'` before rebuilding.
- AX checks over SSH fail (TCC: "not allowed assistive access"). Verify GUI via computer-use, or
  in-process via the harness — not `osascript … System Events`.
- `duti` is at `/opt/homebrew/bin/duti`. LS default for `.md` is unreliable due to ~17 registered
  bundles + Warp claiming `net.daringfireball.markdown`. Old x86 `~/Desktop/downloads/MacDown.app`
  is intentionally LEFT in place (Jason's call 2026-06-29).
- Relevant UTIs to set as handler: `net.daringfireball.markdown`, `public.markdown`,
  `net.ia.markdown`, `com.unknown.md` (+ `.md`/`.markdown` extensions).
- No scripting (`sdef`) today; `x-macdown://` URL scheme + `macdown` CLI are the transport seeds.
- `Dependency/peg-markdown-highlight/pmh_parser.c` is a GENERATED file (greg ← `pmh_grammar.leg`) now COMMITTED (`12fafb5`) — was gitignored, which broke first-build of a fresh clone (no pre-build phase makes it). Regenerate+recommit if the `.leg` grammar changes (Phase 4/5). **Security note (finding 7b, 2026-06-30):** the val-stack grow-guard in `yyPush` is patched in BOTH `pmh_parser.c` AND the greg emitter `greg/compile.c`, so a `make` regeneration reproduces it — do NOT drop the guard when regenerating. Lesson: a warm working copy hides missing generated artifacts — ALWAYS sanity-check a `git clone` build, not just darwin's checkout.

- **CocoaPods over SSH footgun (hard-won 2026-06-30):** `pod install` from a non-UTF-8 ssh session CRASHES with `Encoding::CompatibilityError (Unicode Normalization not appropriate for ASCII-8BIT)` (the ssh login shell lacks a UTF-8 locale). FIX: `export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` before `pod install` (and before any cocoapods/git-hook invocation over ssh). Builds via `xcodebuild` don't need it.
- **Removing a pod touches 4 spots (Sparkle, done 2026-06-30):** (1) `Podfile` line, (2) source `#import` + any delegate methods, (3) `MainMenu.xib` — the pod's `customObject` + ANY menu item/action targeting it (a dangling nib class can abort the WHOLE main-nib load = the old "no UI on launch" bug), (4) any leftover `Info.plist` keys. Then `pod install` REGENERATES the pbxproj `[CP] Embed Pods Frameworks` phase + xcconfig automatically — do NOT hand-edit those. Verify: build + 51/0 + `ls <app>/Contents/Frameworks` shows no framework + GUI launch eyeball (nib edits need a real launch check).
- **MCP zero-input tools (fixed 2026-06-30):** status/get_text/render_html now take `params: Optional[NoInput] = None` so the Claude app no longer errors `Field required` when called with no args (was: required `params: NoInput`). Guard: `ZeroInputErgonomicsTests` asserts the inputSchema doesn't list `params` as required (schema-level, not just signature). Contract tests 15/0.
- **WebView XSS hardening (Phase 4 finding 1) — where it lives (saves a hunt):** render pipeline is `MPRenderer.currentHtml` (= hoedown body, **UNTRUSTED**) → wrapped by `MPGetHTML()` via `MacDown/Resources/Templates/Default.handlebars` (adds the **trusted** bundled Prism/MathJax styleTags/scriptTags) → `-[MPDocument renderer:didProduceHTMLOutput:]` → `loadHTMLString:` (MPDocument.m ~1170). Subresource choke point = `-webView:resource:willSendRequest:` (MPDocument.m ~884). Sanitize the BODY only (`MPSanitizeHTMLBody`, MPRenderer.m) so template scripts are never stripped; CSP lives in the handlebars `<head>`; remote-load policy = `+[MPDocument mp_isAllowedPreviewResourceURL:]` (allow file/applewebdata/about/data, refuse remote). Tests: `MPXSSHardeningTests` (16, pure-logic/headless).
- **Legacy `WebView` (WebKit1) enforces `<meta>` CSP** (shared WebCore), but MathJax needs `'unsafe-eval'` and bundled Prism/MathJax are inline/file: — so the CSP keeps `'unsafe-inline' 'unsafe-eval'` and its real value is **egress-locking** (no remote origins). Don't tighten to `script-src 'self'` without pre-rendering Prism + a JS-light MathJax (that's the WKWebView bite).
- **Remote subresources no longer render in the preview** (`![](http://…)` images / remote CSS) — intended anti-beacon/SSRF behavior of the `willSendRequest` block. To re-enable, gate `mp_isAllowedPreviewResourceURL:` behind a preference (teed up).
- **Codegen escaping footgun:** when a Python patcher EMITS Objective-C regex string literals, backslashes cross two layers — write `\\\\b` in the Python string to land `\\b` in the `.m` (ObjC then compiles `\\b` → regex `\b`). Verify the WRITTEN file with `grep`, not the generator.
- **`open <app> <file>` (two positional paths) opens them as TWO separate items** — the file goes to its DEFAULT handler, NOT `<app>`. To open a file in a SPECIFIC build: `open -a <full-path.app> <file>`. (Bit a live eyeball 2026-06-30.)

- **Pods are patched via a `Podfile` `post_install` hook (not by editing `Pods/`)** — `Pods/` is gitignored, so the SSOT for any dependency patch is the committed `Podfile` hook + a banked patch in `Scripts/patches/`. Current hooks: **LibYAML 0.1.4 CVE-2014-2525** (`STRING_EXTEND` guard in `yaml_parser_scan_uri_escapes`). The hook chmods the read-only pod source, is idempotent (skips if the fix marker `STRING_EXTEND(parser, *string)` is present), aborts loudly if the anchor `*(string->pointer++) = octet;` ever changes, and runs in CI too (CI does `pod install --repo-update`). To verify after `pod install`: `grep -n "CVE-2014-2525" Pods/LibYAML/src/scanner.c`. Reversible: tag `pre-cve-libyaml`.

- **Parser fuzz tooling (finding 7, 2026-06-30):** `Scripts/fuzz/` — `build.sh` (ASan/UBSan
  harnesses for hoedown / pmh / LibYAML; `--cve-control` also builds the guard-removed LibYAML
  to prove CVE-2014-2525), `run.sh` (corpus + run; non-zero only on a NEW defect; `KNOWN_OPEN[]`
  lists accepted **7c only** — **7a + 7b (heap+stack) are FIXED** (7b-heap = val-stack grow-guard
  in `yyPush` patched in both `pmh_parser.c` and the greg emitter `greg/compile.c`; 7b-stack = input
  bracket-nesting cap `PMH_NESTING_CAP=12` in `pmh_markdown_to_elements` patched in `pmh_parser.c`
  + `pmh_parser_head.c`, with `pmh_thread.c` a new 512KB-stack control), the main hoedown loop runs at the product cap
  `MDFUZZ_NESTING=1000` + a positive control that the unguarded SIZE_MAX still overflows), `generate_corpus.py`, `hoedown_thread.c` (renders on a 512KB pthread
  to find the real overflow threshold). Standalone clang — **no Xcode/app build needed**.
  `build/` + `corpus/` are gitignored.
- **pmh highlighter DoS (finding 7b, 2026-07-01) — TWO coupled vectors, both per-block:** the
  generated peg parser has catastrophic **exponential-time backtracking** (parse time triples per
  added unmatched `[` in ONE block — depth 12=0.33 s, 13=1.0 s, 14=3.0 s, 15=8.8 s, 16=25 s+) AND,
  at extreme depth (~thousands), unbounded C recursion `yy_Label`→`yy_ExplicitLink`→`yy_Link`→
  `yy_Inline` that stack-overflows the 512KB `_parseHighlightsQueue` thread. **The time-hang
  DOMINATES** (stack overflow only wins at ~tens of thousands deep) and was NOT noted in prior
  handoffs. Fires on balanced deep `[`, unbalanced open `[` (`a[b`×20), and soft-newline `[`. Both
  fixed by ONE input bracket-nesting cap (`PMH_NESTING_CAP=12`, resets at blank lines → per-block,
  near-zero false-positives). **Sibling 7b-time still OPEN:** `backtick_runs.md` (2 MB of `` ` ``)
  hangs >20 s — the `[`-cap doesn't cover it; softer (cancellable, no crash). `run.sh` has NO
  per-file timeout, so it silently tolerates these slow inputs — fold a `timeout` in with finding 9.
- **hoedown renders on the `parseQueue` (NSOperationQueue) = 512KB stack, NOT main's 8MB**
  (`MPRenderer parseAndRenderWithMaxDelay:` → `parseMarkdown:`). So a deeply-nested `.md`
  stack-overflows at ~2000-3000 levels (-O0) — `kMPRendererNestingLevel = SIZE_MAX` disables
  hoedown's built-in `max_nesting` guard (`document.c` parse_block/parse_inline: `work_bufs
  size > max_nesting → return`). **FIXED 2026-06-30: capped at 1000** in `MPRenderer.m` (finding 7a LANDED; byte-identical output below depth 1000).
- **CORRECTED 2026-06-30 — the cap-hang was NOT a render-wait race (prior handoff misdiagnosis).**
  Landing the cap (SIZE_MAX→1000) made the full headless suite intermittently wedge at
  `MPTestHarnessTests testCommand_blockquote`. A `sample` of the wedge showed the real cause:
  the main thread is in `+[MPTestHarness openFileAtPath:]`'s run-loop pump and XCTest is
  recording an issue → `recordIssue:` → `preferredSourceCodeLocationForSourceCodeFrames:` →
  `XCTSourceCodeFrame symbolInfoWithError:` → **`fopen`/`open$NOCANCEL` blocks forever**
  (XCTest failure-**symbolication** wedging in `open()`, DebugSymbols/Spotlight). The cap is
  inert at the test's depth-1 content (passes in ISOLATION at cap=1000 in 0.22s) — the cap only
  shifts TIMING. The real trigger is main-thread starvation: `parseAndRenderWithMaxDelay:` had a
  busy-spin whose timeout term `[start timeIntervalSinceNow] >= maxDelay` is DEAD (negative ≥
  non-negative is always false), so it hammered the main queue with no yield. **FIX (landed):**
  de-flake that loop — yield 5ms between polls + a 5s absolute safety deadline; termination
  unchanged (wait until `rendererLoading` false) → output byte-identical. Result: **7/7 clean**
  full-suite runs at cap=1000 (the lone wedge in testing coincided with me running `sample`
  against the test proc = external starvation). **STANDING FOOTGUN:** never run the heavy fuzz
  build / `sample` / `spindump` CONCURRENTLY with `xcodebuild test` — the extra load re-starves
  the harness and can re-trip the XCTest symbolication-on-`open()` wedge. Run them serially.
- **zsh footgun (fuzz builds over ssh):** darwin's login shell is zsh, which does NOT word-split
  unquoted `$VAR` — putting compiler flags in a var and passing `$SAN` makes ONE arg
  (`unsupported argument ...`). Inline the flags, or use a bash array (`SAN=(...)`; `"${SAN[@]}"`),
  or `${=SAN}`. `Scripts/fuzz/build.sh` uses a bash array.

## 10. How to take a bite (every session)
1. `git pull --ff-only` (this repo + claude-blackbook). Read this file top-to-bottom.
   - Then run `Scripts/ui-verify-due.sh` — if it shouts (counter ≥ 5), the §11.2 human UI pass is mandatory THIS session.
2. `lessons.py search "<the bite> mdeditor" --scope global,strike-zone` + `lessons.py doctrine`.
3. Pick the lowest unchecked box that's unblocked (phases are ordered by dependency: 0→1→2→3→4, with
   5/6/7 parallelizable). `git tag pre-<bite>` before editing.
4. Ship it. Tick the box(es). Update §9 LUT with anything hard-won.
5. Teacher out (`lessons.py add`), sync out (commit + push), run `~/Scripts/gate-selfcheck.sh`.
6. Improve THIS plan and the handoff prompt for the next Claude. Pay it forward. 🌳

---

## 11. Handoff cadence, UI-verification ledger & the complete-vs-handoff rule

### 11.1 When to hand off (complete vs continue)
This is a **multi-phase** project, so most sessions END WITH A HANDOFF — a copy-pastable continuation
prompt for the next session (suspension-bridge methodology). Crisply:

- **Work remains anywhere** (an unticked box in this plan, an unfinished phase, a long piece still in
  progress) → **EMIT THE HANDOFF.** Between-phase and mid-incremental stops both count. A handoff
  MEANS "there is more to do; here's exactly where to pick up."
- **No work remains anywhere** (every box below ticked, nothing teed up — the whole effort is done)
  → **EMIT NO HANDOFF.** Say "✅ Complete — cleared for takeoff." The *absence* of a handoff is the
  done-signal.
- **Unsure → ask Jason** ("more to do, or complete?") rather than defaulting either way.

(Canonical, project-agnostic version: `~/Desktop/downloads/HANDOFF-GATE.md` §G-F. This is the
mdeditor application of it: until Phases 1–7 are all ticked, the project is NOT complete, so
between-phase sessions hand off.)

### 11.2 Periodic full UI build — every 5th handoff
Headless tests can't catch purely-visual or modal-only regressions (theme rendering, toolbar
appearance, the export panels). So **every 5th handoff, the session MUST run the full human UI
verification** (`docs/TEST-MATRIX.md` §3) against a fresh Debug build, and record it in the ledger.
Between those, headless green is enough — keep dev cheap and flicker-free.

- Rule: if **handoffs-since-last-UI-verification ≥ 5**, do the UI pass THIS session before handing off.
- Force-function: `Scripts/ui-verify-due.sh` parses this ledger's counter and exits non-zero (LOUD) when the pass is due — run it at session start and before composing a handoff so the cadence can't be silently missed.
- Doing it sooner after any UI-touching change is encouraged.

### 11.3 Ledger (append one row per session; reset the counter on a UI pass)
| # | date | session shipped | UI-verified? | handoffs since last UI verify |
|---|---|---|---|---|
| 1 | 2026-06-29 | Phase 0 verified + cold-build fix (`pmh_parser.c`) + Phase 1 harness (registry, editor I/O, headless, docs) | NO (headless only) | 1 |
| 2 | 2026-06-29 | Phase 1 GUI-routing: registry moved to app target on `MPDocument`; all 32 IBActions delegate to it; harness now a façade; link/image de-duped | NO (headless only, 44/44) | 2 |
| 3 | 2026-06-29 | Phase 2 CI/CD: `.github/workflows/ci.yml` (macos-26 / Xcode 26, **fresh-clone**, Debug+Release matrix, coverage artifact, informational `analyze` job) + `Scripts/pre-push` hook & `install-git-hooks.sh` + retired `.travis.yml`. **CI confirmed GREEN** (run 28405776615 @ `eba20dc`) after fixing a Release-only link gap (`ENABLE_TESTABILITY=YES` + `ONLY_ACTIVE_ARCH=YES` on the test step — Release defaults testability NO). Local suite 44/0. | NO (headless only, 44/44) | 3 |
| 4 | 2026-06-30 | Phase 3 transport: `x-macdown://command?id=<id>` verb routing to `invokeCommandID:` on the front doc + allowlist validators (`validatedCommandID:`/`validatedFileURLFromParam:`) + `open` file-URL guard + `MPURLCommandTests` (5) + `docs/MCP-TRANSPORT.md`. Suite 49/0. | NO (headless only, 49/0) | 4 |
| 5 | 2026-06-30 | **UI VERIFICATION PASS** (§11.2 / TEST-MATRIX §3) on a fresh **Debug** build (HEAD `8776396`): launch + **preview renders** ✓; toolbar parity (bold→`**selectme**`, H2→`## …`, ordered-list→`1. …`) ✓; Export **HTML** (9.2 KB, correct `<h1>/<h2>/<strong>/<ol>` reflecting the live edits) ✓; Export **PDF** (valid 1-page `%PDF-1.3`) ✓; **Phase 3 live smoke**: `open -b com.jasoncbraatz.mdeditor-debug "x-macdown://command?id=h1"` applied `# ` to the front-doc line ✓ (verified via **eye/computer-use**, not osascript). Also fixed a `ui-verify-due.sh` off-by-one (see §9 LUT). | **YES** | 0 |
| 6 | 2026-06-30 | **Phase 3 read-back**: handler read verbs `get-text`/`render-html`/`export-html`/`status` (+ `-mp_frontDocumentOrNil`, `+validatedExportPathFromParam:`) + CLI `macdown-cmd --control <url> [--bundle]` sending `GetURL` directly (AESendMessage, waits for reply) + 2 export-path contract tests. **Headless suite 51/0.** **Live read-back smoke GREEN** (GUI-session, `Scripts/readback-smoke.sh`, 2026-06-30): all 4 verbs returned correct JSON — status{hasDocument,previewReady,commandCount:32,textLength:59}, get-text round-trip, render-html `<h1>`+`<strong>`, export-html 97B. One-time "Terminal wants to control mdeditor" TCC Allow needed. | live read-back: YES; §11.2 full-UI: NO (not due) | 1 |
| 7 | 2026-06-30 | **Phase 3 FastMCP server** `mcp/mdeditor_mcp.py`: 7 tools (status/get_text/render_html/open_file/new_document/run_command/export_html) shelling to `macdown --control`. Contract tests mock the CLI — verb/URL mapping + JSON/error contract, **13/0**; server lists all 7 tools with clean schemas. + `mcp/README.md`, `requirements.txt`, `mcp-live-smoke.sh`. **Live MCP round-trip GREEN** (GUI-session, 2026-06-30): all tools drove the real app (status/get_text/run_command h2/render_html/export_html/new_document). | live MCP: YES; §11.2 full-UI: NO | 2 |
| 8 | 2026-06-30 | **Phase 3 `set_text`**: new `set-text` transport verb (`MPMainController`) — reads a local file (file= param, validated like `open`) and sets `doc.markdown` + `forceRefreshPreview`; text rides in a temp FILE not the URL. MCP `mdeditor_set_text(text)` writes+passes+deletes the temp (now **8 tools**). MCP contract tests **14/0** (asserts set-text URL + temp content + cleanup). Headless Xcode suite re-run green (51/0). `set_text` no longer deferred. | NO (headless 51/0 + mocked 14/0; live via mcp-live-smoke.sh) | 3 |
| 9 | 2026-06-30 | **Phase 3 Claude-app wiring (Bite A) — DONE.** Registered `mdeditor` MCP in `claude_desktop_config.json` (env `MDEDITOR_CLI=/Users/jasoncbraatz/bin/macdown` — stable Release CLI, system-frameworks-only, survives DerivedData wipes; `MDEDITOR_BUNDLE=com.jasoncbraatz.mdeditor`), restarted the Claude desktop app, **live in-app round-trip GREEN from a Claude session**: status{ok,commandCount:32} · new_document(ok) · get_text round-trip · render_html `<h1>Hello…</h1>`. Root-caused the smoke's "no reply from app": **stale `/Applications/mdeditor.app` (Jun29, pre-read-back handler)** + **LaunchServices pollution** relaunching old copies — rebuilt app from HEAD, reinstalled to `/Applications`, trashed stale-code copies (`/tmp/ddopt`,`/tmp/ddtest`,backup). Also: **fixed the out-of-order ledger** (was 1,2,3,4,8,7,6,5) and **hardened `ui-verify-due.sh`** to pick max row-# not `tail -1`. **§11.2 full-UI pass DONE this session** (computer-use, fresh **Debug** @ `ec8f004`): launch + **preview renders** ✓; **bold parity** (⌘B → `**boldme**` → preview bold) ✓; H1/H2 + bullet list render ✓; **Export HTML** (9.2 KB — `<h1>/<h2>/<strong>/<ul>/<li>` reflecting the live edits) ✓; **Export PDF** (valid `%PDF-1.3`, 1 page, 16.7 KB) ✓. | live Claude-app MCP smoke: **YES**; §11.2 full-UI: **YES** (computer-use) | 0 |
| 10 | 2026-06-30 | **Phase 4 kickoff.** (1) MCP `params` ergonomics footgun FIXED — zero-input tools (status/get_text/render_html) now `Optional[NoInput]=None`, so the Claude app no longer needs `params:{}`; added a schema-level regression test (`ZeroInputErgonomicsTests`), contract tests **14→15/0** (commit 36fbae5). (2) **Sparkle REMOVED entirely** (commit 7627fef) — Podfile pod dropped (`pod install`→"Removing Sparkle"), import + `feedURLStringForUpdater:` deleted, `SUUpdater` object + "Check for Updates…" item removed from MainMenu.xib, dead `SUEnableAutomaticChecks` plist key gone; Debug build green, headless **51/0**, no `Sparkle.framework` embedded, **GUI launch eyeball** (computer-use): full menu bar + no "Check for Updates…". (3) `docs/SECURITY-AUDIT.md` scaffolded (threat model + 9 findings; WebView XSS = next bite). | Sparkle launch eyeball: YES; §11.2 full-UI: NO (not due) | 1 |
| 11 | 2026-06-30 | **Phase 4 item 1 — WebView XSS hardening (SECURITY-AUDIT finding 1).** 3 layers: (a) body sanitizer `MPSanitizeHTMLBody()` (MPRenderer.m) on `currentHtml` — strips `<script>/<iframe>/<object>/<embed>`, inline `on*=`, neutralizes `javascript:`/`vbscript:` + non-image `data:` (covers preview+export+copy+MCP); (b) strict **CSP** `<meta>` in `Default.handlebars` (egress locked local; `'unsafe-inline/eval'` kept for bundled Prism/MathJax); (c) **remote-load block** `+[MPDocument mp_isAllowedPreviewResourceURL:]` in `willSendRequest:` (cancels non-local subresources — anti-beacon/SSRF). +16 tests (`MPXSSHardeningTests`), headless **67/0** Debug. **Live eyeball** (computer-use, fresh Debug @ `pre-phase4-xss`+patch): `<script>` did NOT change title, `<img onerror>` did NOT mutate body (neither executed), iframe stripped, remote img blocked; legit md + Prism code block + table render. WKWebView migration SCOPED (not done). Tag `pre-phase4-xss`. | XSS render eyeball: YES; §11.2 full-UI: NO (not due) | 2 |
| 12 | 2026-06-30 | **Phase 4 plist/hardening cluster — SECURITY-AUDIT findings 3+4+5.** (3) ATS: `NSAllowsArbitraryLoads`→`false` + entire `NSExceptionDomains` removed (`cdnjs.cloudflare.com` + dead `uranusjr.com`) — safe: all preview subresources bundled, MathJax CDN URL rewritten to bundled file: in `willSendRequest:` before any net load, no other network API. (4) Removed `NSAppleScriptEnabled` + dangling `OSAScriptingDefinition` (→ absent `MacDown.sdef`); `x-macdown` scheme preserved. (5) `ENABLE_HARDENED_RUNTIME = YES` on both app configs (App Sandbox deferred). `plutil -lint` OK on both plist+pbxproj; built bundle's embedded Info.plist verified. Headless **67/0**. **GUI launch eyeball** (separate `open -n` fresh Debug instance — did NOT disturb the running instance holding Jason's unsaved doc): app launches with new plist, preview renders (bold/italic/Prism), `<script>` stripped + `<img onerror>` did not fire. Tag `pre-phase4-plist-hardening`. | plist launch eyeball: YES; §11.2 full-UI: NO (not due) | 3 |
| 13 | 2026-06-30 | **Phase 4 finding 8 — dependency CVE sweep** + **§11.2 full-UI pass**. (a) Swept all 8 pods vs known CVEs (table in SECURITY-AUDIT §8); found & fixed **LibYAML 0.1.4 CVE-2014-2525** (heap overflow in `yaml_parser_scan_uri_escapes`, reachable via `.md` YAML front-matter `NSString+Lookup -> YAMLSerialization -> LibYAML`) — official upstream `STRING_EXTEND` guard applied via a `Podfile` `post_install` hook (idempotent, chmods read-only source, CI-safe); canonical patch `Scripts/patches/libyaml-cve-2014-2525.patch`; other 7 pods clean; build green, headless **67/0**, pushed **`3cd72af`** (pre-push suite green). Tag `pre-cve-libyaml`. (b) **§11.2 full UI pass** (computer-use, fresh **Debug** @ `3cd72af` post-patch, separate `open -n` instance so Jason's running instance + unsaved doc were untouched): launch + **preview renders** ✓; toolbar parity **bold** (`**ParityBold**`), **H2** (`## ` + heading render), **bullet list** (`* ` + bullet) ✓; **Export HTML** (9.9 KB — correct `<h1>/<strong>/<h2>/<li>/<table>`) ✓; **Export PDF** (valid `%PDF-1.3`, 1 page) ✓; no visual glitches. | §11.2 full-UI: **YES** (computer-use) | 0 |

| 14 | 2026-06-30 | **Phase 4 finding 7 — parser fuzz (first pass).** Built repo-backed ASan/UBSan harnesses + adversarial corpus (`Scripts/fuzz/`: `build.sh`/`run.sh`/`generate_corpus.py`/`hoedown_thread.c` + README; standalone clang, no app build). Found **5 defects, all deep-nesting/unbounded-recursion** (clean on the other 31 inputs): **7a** hoedown `parse_block` stack-overflow, **7b** pmh `yymatchChar` stack-overflow + `yySet` **heap**-overflow, **7c** LibYAML `yaml_parser_load_node` stack-overflow. **Independently ASan-validated CVE-2014-2525** (`build.sh --cve-control`: unpatched heap-overflows on the PoC via `yaml_parser_load`; patched clean). **7a fix = cap `kMPRendererNestingLevel` at 1000** (root cause: SIZE_MAX defeats hoedown's guard; parse runs on the 512KB `parseQueue` stack, floor ~2000-3000 @-O0) — **proven product-safe** (clean over corpus; byte-identical shallow output) but it **deterministically hangs `testCommand_blockquote`** (test-harness render-wait race, NOT a product change; baseline+force-rebuild control = 67/0), so **NOT landed** — tree left at SIZE_MAX so the gate stays green. Docs updated (SECURITY-AUDIT #7 7a/7b/7c + decisions; MASTER-PLAN §7/§9). Tag `pre-fuzz`. | headless **67/0** (SIZE_MAX baseline+control); §11.2 full-UI: NO (not due) | 1 |
| 15 | 2026-06-30 | **Phase 4 finding 7a — hoedown nesting cap LANDED** (+ render-wait de-flake). Capped `kMPRendererNestingLevel` SIZE_MAX→**1000** (`MPRenderer.m`) — stops the `deep_blockquote` `parse_block` stack-overflow on the 512KB `parseQueue` stack; byte-identical output below depth 1000; `hoedown_thread deep_blockquote 1000` rc 0 vs unguarded SIZE_MAX rc 138 (bus error). **Corrected the prior handoff's misdiagnosis**: the cap-hang was NOT a render-wait race but XCTest failure-**symbolication wedging in `open()`** (DebugSymbols/Spotlight) once an issue is recorded, triggered by main-thread starvation from a busy-spin (dead `\|\| [start timeIntervalSinceNow] >= maxDelay` term) in `parseAndRenderWithMaxDelay:`. De-flaked it (yield 5ms + 5s safety deadline; termination unchanged → byte-identical) → **7/7 clean** full-suite runs at cap=1000 (lone wedge coincided with concurrent `sample`). `Scripts/fuzz/run.sh` updated (main hoedown loop at `MDFUZZ_NESTING=1000`, `deep_blockquote` out of KNOWN_OPEN, + positive control) → **PASS** (4 known-open 7b/7c, 0 new). Tags `pre-7a-deflake`/`pre-7a-land`. | headless **67/0** ×7 + fuzz run.sh PASS; §11.2 full-UI: NO (not due) | 2 |
| 16 | 2026-06-30 | **Phase 4 finding 7b-heap — pmh val-stack heap-overflow FIXED & LANDED** (fork-and-own). Root cause: the greg-generated leg runtime advanced the value-stack pointer `G->val` by `count` in `yyPush` with **no grow/bounds guard** (unlike `yyDo`'s thunk stack / `yyText`'s text buffer), so deeply-nested input (`deep_nested_links.md`) walked `G->val` past the `G->vals` allocation and `yySet` (`pmh_parser.c:1258`) wrote OOB — ASan **heap-buffer-overflow**, reachable via a malicious `.md` through `HGMarkdownHighlighter`. **Fix:** grow `G->vals` on demand in `yyPush`, preserving the offset across `realloc` (exactly Ian Piumarta's later upstream peg/leg guard, which this vendored copy predated). Applied to **both** the compiled artifact (`pmh_parser.c`) **and** the greg emitter template (`greg/compile.c`) so `make`-regeneration reproduces it. **Proof:** `deep_nested_links.md` ASan-clean (rc 0, was rc 134); removed from `run.sh` KNOWN_OPEN so the gate now FAILS on any regression; full `run.sh` **PASS** (3 known-open = 7b-stack + 7c×2, 0 new; 7a cap + CVE control still green). **7b-stack** (`deep_brackets.md` → `yy_Label` recursive-descent stack-overflow) is a *separate* DoS, still OPEN, teed up next. Tag `pre-7b`. | headless **67/0**; §11.2 full-UI: NO (not due) | 3 |
| 17 | 2026-07-01 | **Phase 4 finding 7b-stack — pmh recursive-descent DoS FIXED & LANDED** (co-pilot; **finding 7b now fully closed** = heap + stack). Measuring the real 512KB `_parseHighlightsQueue` floor with a new `Scripts/fuzz/pmh_thread.c` surfaced a worse, previously-unnoted vector: **catastrophic EXPONENTIAL-TIME backtracking** in the generated peg parser — parse time **triples per added unmatched `[`** in one block (depth 12=0.33 s, 13=1.0 s, 14=3.0 s, 15=8.8 s, 16=25 s+), which DOMINATES the stack overflow (that only wins at ~tens of thousands deep). Fires on balanced deep `[`, unbalanced open `[` (`a[b`×20), and soft-newline `[`. **Fix (fork-and-own):** `pmh_markdown_to_elements` refuses the parse (empty element array = no highlighting for that one file) when any **block's** unmatched-`[` nesting > `PMH_NESTING_CAP=12` (>2× real docs' ≤5; counter resets at blank lines → per-block, near-zero false-positives); patched BOTH `pmh_parser.c` + `pmh_parser_head.c` so `make` reproduces it. New `pmh_thread` 512KB control (guard-off overflows rc 138, guard-on rc 0) wired into `build.sh`/`run.sh`; `deep_brackets` removed from `run.sh` KNOWN_OPEN → gate now FAILS on regression; `run.sh` **PASS** (2 known-open = 7c only, 0 new); boundary exact (depth 12 parses, 13 refused); normal corpus + 5-deep nested links parse fine. Found a **sibling 7b-time** (`backtick_runs.md` non-bracket exponential hang >20 s) — teed up (bundle a `run.sh` per-file timeout with finding 9). Tags `pre-7b-stack`; pushed `878e487`. | headless **67/0** + fuzz `run.sh` PASS; **§11.2 full-UI: YES** (computer-use, fresh Debug @ `e7e2ac5`, separate `open -n`) | 0 |

> Next session: add your row and increment the counter. At **4** (read at session start), do the UI pass, set "UI-verified? = YES", and reset the counter to 0.
> **✅ §11.2 FULL-UI PASS DONE 2026-07-01 (row 17, this session, via computer-use)** on a fresh **Debug** build @ `e7e2ac5` (separate `open -n` so Jason's Release instances / REPORT.md were untouched): launch + **preview renders** ✓; **syntax highlighting** works (H1/H2, `**bold**`, `*italic*`, `` `code` ``, links incl. the nested `[inner]` link — the exact content the cap must NOT falsely refuse) ✓; toolbar **Bold** command functional (inserts `**` markers) ✓; **7b-stack guard in the live UI** — opened `/tmp/ui_deepbrackets.md` (80 KB, `[`×40000): app stayed **responsive at 0.1% CPU**, brackets shown as **plain unhighlighted text** (guard refused that block), NO hang/crash ✓; **Export HTML** (10001 B — correct `<h1>/<strong>/<em>/<h2>/<code>/<li>/<blockquote>` + `nested [inner] link`) ✓; **Export PDF** (valid `%PDF-1.3`, 1 page, 30674 B) ✓. Initially blocked (approval timed out ×2 while Jason was away); completed later the same session on his return. **Counter RESET to 0.** Next mandatory full-UI pass: when the counter next reads 4 (5 handoffs from row 17).
> **✅ §11.2 FULL-UI PASS DONE 2026-06-30 (row 13, this session, via computer-use)** on a fresh **Debug** build @ `3cd72af` (post-CVE-patch): preview renders · toolbar parity bold/H2/bullet-list · Export HTML (correct `<h1>/<strong>/<h2>/<li>/<table>`) · Export PDF (valid 1-page `%PDF-1.3`). Pulled forward one session early (the script read "due NEXT session, counter=3") because rows 10/11/12 were three consecutive render/launch-touching security changes verified only by launch-eyeball — §11.2 explicitly encourages a full pass sooner after UI-touching work. **Counter RESET to 0.** Next mandatory full-UI pass: when the counter next reads 4 (5 handoffs from row 13).
> **Ledger reconciled 2026-06-30 (row 9, Bite A).** The rows had drifted physically out of order (1,2,3,4,**8,7,6,5**) and handoffs #6–#8 had only updated prose notes, so the old `ui-verify-due.sh` `tail -1` read row 5 (counter 0) and **falsely reported "not due"** — a silent force-function failure. Rows are now chronological and the script picks the MAX row-# (hardened). Counter history since the row-5 reset: **row6=1, row7=2, row8=3, row9=4**.
> **✅ §11.2 FULL-UI PASS DONE 2026-06-30 (row 9, this session, via computer-use)** on a fresh Debug build @ `ec8f004`: preview renders · bold parity (⌘B) · H1/H2/list render · Export HTML (correct `<h1>/<h2>/<strong>/<ul>`) · Export PDF (valid 1-page `%PDF-1.3`). **Counter RESET to 0.** Next mandatory full-UI pass: when the counter next reads 4 (5 handoffs from row 9). Row 9 also carries the live Claude-app MCP transport round-trip (Bite A).
