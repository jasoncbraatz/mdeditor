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
| **Test target** | `MacDownTests` target EXISTS and is tracked. **BUT** `MPTestHarnessTests.m` `#import "MPTestHarness.h"` and **`MPTestHarness.{h,m}` are MISSING from disk AND from git** → the harness is *specified but not implemented* (or was lost to a darwin-only save). Other tests tracked: `MPAssetTests`, `MPColorTests`, `MPHTMLTabularizeTests`, `MPPreferencesTests`, `MPStringLookupTests`, `MPUtilityTests`. |
| Harness spec (already written) | `MPTestHarnessTests.m` calls: `+openFileAtPath:error:`, `+openFileAtPath:timeout:error:`, `+isPreviewBlank`, `+previewText`, `+isPreviewReady`, `+isPreviewWebViewValid`, `+forceRefreshPreview`, `+simulateIdleForSeconds:`, `+diagnosticReport`. tearDown closes all `NSDocumentController` documents. |
| CLI | `macdown-cmd` target builds the `macdown` CLI. `MPArgumentProcessor` is minimal today (help/version/arguments only). Opening/piping handled in `MPMainController` via the prefs domain (see rename footgun, Phase 6). |
| URL scheme | `x-macdown://` declared (`CFBundleURLTypes`, name "Macdown custom control"). Good transport seed for the MCP. |
| Document types | Correct already: `CFBundleDocumentTypes` declares `md`/`markdown`, MIME `text/x-markdown`, UTI `net.daringfireball.markdown`, role **Editor**, `NSDocumentClass = MPDocument`. |
| Scripting | **No** AppleScript/`sdef`/`NSScriptCommand` support today. |
| CI | **No** GitHub Actions. Legacy `.travis.yml` only. |
| Updater | Sparkle DISABLED (commit b40195c) but the **pod is still linked** (surface to remove in Phase 4). |
| Default-handler | Launch Services is polluted with ~17 registered bundles (old x86 `~/Desktop/downloads/MacDown.app`, DerivedData + `/tmp/ddopt|ddtest` copies, 3 AppTranslocation copies, Warp claiming markdown). This is why "set default" reverts. See Phase 3.5 / done-this-session note. `duti` is installed at `/opt/homebrew/bin/duti`. |

---

## 3. PHASE 0 — Foundations: get the harness target GREEN headless

**Goal:** `xcodebuild test` runs the existing `MacDownTests` to completion, headless, and we can see
pass/fail — even if some tests are stubbed/skipped initially. This is the floor everything stands on.

**Why:** You cannot have a "harness-first" workflow until the test target compiles and runs. Right
now it almost certainly does NOT compile because `MPTestHarness.{h,m}` is missing.

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

**Done when:** ☐ test target compiles · ☐ `xcodebuild test` green headless · ☐ new files committed+pushed.

---

## 4. PHASE 1 — The harness as UI-grade control surface *(TOP PRIORITY)*

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

**Done when:** ☐ command registry · ☐ GUI routes through it · ☐ per-command round-trip tests green ·
☐ crash-safety sweep green · ☐ GUI parity spot-check.

---

## 5. PHASE 2 — SOTA CI/CD

**Goal:** Every push runs the harness in the cloud; coverage + result artifacts visible; red bar
blocks merges. Local fast loop too.

**Steps:**
1. **Local:** `Scripts/test.sh` (xcbeautify-piped `xcodebuild test`, `-enableCodeCoverage YES`,
   `-resultBundlePath build/last.xcresult`). A `Scripts/pre-push` git hook that runs the logic suite.
2. **Cloud:** `.github/workflows/ci.yml` on `macos-15` (or latest GH image w/ Xcode 26): cache Pods,
   `pod install`, `xcodebuild build` + `test`, upload `.xcresult` + coverage as artifacts, fail on
   test failure or `xcodebuild analyze` warnings. Matrix: Debug + Release (Release catches the kind
   of `-Os`/optimization regressions we hit).
3. Decommission `.travis.yml` (dead) — remove or replace; note in commit why.
4. **Acceptance:** a PR shows a green check; an intentionally-broken command turns it red.
5. Reversibility: CI is additive; deleting `.travis.yml` is reversible via git.

**Done when:** ☐ `Scripts/test.sh` · ☐ pre-push hook · ☐ GH Actions green · ☐ coverage artifact ·
☐ `.travis.yml` retired.

---

## 6. PHASE 3 — MCP server (piggyback on MPAutomation)

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

**Done when:** ☐ transport verbs · ☐ input validation · ☐ FastMCP server · ☐ Claude-app smoke ·
☐ MCP contract tests.

---

## 7. PHASE 4 — Security audit & attack-surface reduction

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

**Done when:** ☐ WebView hardened (sanitize+CSP+remote policy) · ☐ Sparkle removed · ☐ parser fuzz
clean · ☐ analyze clean · ☐ CVE sweep · ☐ hardening review · ☐ `SECURITY-AUDIT.md` banked.

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
- **Housekeeping (Jason to triage):** untracked `MacDown/Resources/Styles/GitHub-2020.css` and
  `REDO-PROMPT.md` in the working copy — keeper or scratch? ☐

---

## 9. LUT — facts a future Claude should not pay tokens to re-derive

- Build/install/verify recipe: see `mdeditor-SESSION-2026-06-29-launchfix.md` §"Build/install recipe".
  DerivedData: `~/Library/Developer/Xcode/DerivedData/MacDown-ayupkpyrvtmaxbcnyzlnauvioyai/...`.
- Release is `-O0` on purpose (e645264). Don't "optimize" it without doing Phase 5.
- Toolbar group dispatch must pass full ObjC signature — see global lesson `objc method imp arity`.
- `MPTestHarness.{h,m}` were lost (darwin-only save). **Commit + push new files the same session.**
- AX checks over SSH fail (TCC: "not allowed assistive access"). Verify GUI via computer-use, or
  in-process via the harness — not `osascript … System Events`.
- `duti` is at `/opt/homebrew/bin/duti`. LS default for `.md` is unreliable due to ~17 registered
  bundles + Warp claiming `net.daringfireball.markdown`. Old x86 `~/Desktop/downloads/MacDown.app`
  is intentionally LEFT in place (Jason's call 2026-06-29).
- Relevant UTIs to set as handler: `net.daringfireball.markdown`, `public.markdown`,
  `net.ia.markdown`, `com.unknown.md` (+ `.md`/`.markdown` extensions).
- No scripting (`sdef`) today; `x-macdown://` URL scheme + `macdown` CLI are the transport seeds.

## 10. How to take a bite (every session)
1. `git pull --ff-only` (this repo + claude-blackbook). Read this file top-to-bottom.
2. `lessons.py search "<the bite> mdeditor" --scope global,strike-zone` + `lessons.py doctrine`.
3. Pick the lowest unchecked box that's unblocked (phases are ordered by dependency: 0→1→2→3→4, with
   5/6/7 parallelizable). `git tag pre-<bite>` before editing.
4. Ship it. Tick the box(es). Update §9 LUT with anything hard-won.
5. Teacher out (`lessons.py add`), sync out (commit + push), run `~/Scripts/gate-selfcheck.sh`.
6. Improve THIS plan and the handoff prompt for the next Claude. Pay it forward. 🌳
