# mdeditor — Test Harness Reference (`MPTestHarness`)

> **What this is.** `MPTestHarness` is the programmatic, **no-UI** control surface for mdeditor.
> It lets a test (or, later, an MCP server) **open documents, type into the editor, run every
> toolbar/menu editing command, and read back the rendered preview** — all in-process and
> **headless**, so day-to-day development never has to commandeer Jason's desktop.
>
> Source: `MacDown/Code/Testing/MPTestHarness.{h,m}` (in the **app** target so it can reach the
> running app objects). Tests live in `MacDownTests/MPTestHarnessTests.m`.
> SSOT for the bigger plan: `docs/MASTER-PLAN.md`. Last updated 2026-06-29.

---

## 0. TL;DR — run it

```bash
Scripts/test.sh          # build Debug + run the full suite, headless (no windows on your screen)
```

Or directly:

```bash
xcodebuild test -workspace MacDown.xcworkspace -scheme MacDown \
  -configuration Debug CODE_SIGNING_ALLOWED=NO
```

Under XCTest the harness **auto-enables headless mode** (see §1). Current suite: **44 tests, 0
failures**.

---

## 1. Headless / no-flicker mode (the important part)

**Goal:** a Claude tests the UI **without bringing the UI onto Jason's screen.** The app is AppKit +
a legacy `WebView`, so a window must exist for the preview to render — but it does **not** have to be
*visible*. Headless mode makes each document window:

- **fully transparent** (`alphaValue = 0`) — AppKit clamps off-screen windows back to a sliver, so
  transparency (not position) is the real "invisible" guarantee; the WebView still renders normally;
- **parked off-screen** (`-30000,-30000`) and **non-cascading**, belt-and-suspenders;
- and the **app becomes an accessory** (`NSApplicationActivationPolicyAccessory`) — no Dock icon, no
  focus-steal.

**How it turns on:**
- **Automatically under XCTest** (`+initialize` detects `XCTestConfigurationFilePath`). You don't
  have to do anything — every test is headless.
- **Explicitly** via `+[MPTestHarness enableHeadlessTestMode]` (for an MCP / CLI driver).

**The flag is a process-only env var** (`MPHeadlessTestMode`), read by `MPDocument`'s
`windowControllerDidLoadNib:`. It is **deliberately NOT an `NSUserDefaults` value** — a persisted
default would survive into Jason's real mdeditor and hide *its* windows. Normal app launches never
set it, so normal use is unaffected.

```objc
[MPTestHarness enableHeadlessTestMode];
BOOL headless = [MPTestHarness isHeadlessTestMode];   // YES
```

> Want to *watch* the suite run (debugging the UI itself)? Run from Xcode, or temporarily skip
> `enableHeadlessTestMode`. By default headless wins so your desktop stays still.

---

## 2. Quickstart — drive a command end-to-end

```objc
// 1. Open a document (headless: window is invisible)
NSError *err = nil;
[MPTestHarness openFileAtPath:@"/tmp/test1.md" error:&err];

// 2. Set editor text + selection like a user would
[MPTestHarness setMarkdown:@"boldcheck"];
[MPTestHarness selectAll];                 // or selectSubstring:@"bold"

// 3. Run a toolbar/menu command by stable id
[MPTestHarness invokeCommand:@"strong" error:&err];

// 4. Read the result back
NSString *md = [MPTestHarness currentMarkdownContent];   // @"**boldcheck**"
NSString *previewText = [MPTestHarness previewText];     // rendered DOM innerText
```

---

## 3. API reference (every call)

### 3.1 Document access
| Call | Returns | Notes |
|---|---|---|
| `+currentDocument` | `MPDocument *` | The active doc. Robust under XCTest: falls back to a visible/most-recent `MPDocument` when the app isn't frontmost. |
| `+currentDocumentURL` | `NSURL *` | File URL of the current doc (nil for untitled). |
| `+currentMarkdownContent` | `NSString *` | The editor's markdown (`MPDocument.markdown` = `editor.string`). |
| `+currentRenderedHTML` | `NSString *` | The renderer's current HTML (`MPDocument.html`). |

### 3.2 Preview state verification
| Call | Returns | Notes |
|---|---|---|
| `+isPreviewReady` | `BOOL` | `MPDocument.isPreviewReady` flag. |
| `+isPreviewBlank` | `BOOL` | **Pumps the runloop up to ~3 s**: returns NO the moment content appears, YES only if it stays blank (the real blank-canvas bug). Never `sleep()`s. |
| `+previewContent` | `NSString *` | Raw `innerHTML` of the preview `<html>`. |
| `+previewText` | `NSString *` | `innerText` of the preview `<body>` (rendered text). |
| `+isPreviewWebViewValid` | `BOOL` | Preview WebView exists and has a window. |
| `+lastPreviewError` | `NSError *` | Currently always nil (render errors not yet stored — extension point). |

### 3.3 Editor input (NEW — drive the editor like a user)
| Call | Returns | Notes |
|---|---|---|
| `+setMarkdown:` | `void` | Replace entire editor contents. |
| `+selectRange:` | `BOOL` | Select a character range; NO if out of bounds. |
| `+selectAll` | `void` | Select the whole document. |
| `+selectedRange` | `NSRange` | Current selection (`{NSNotFound,0}` if no editor). |
| `+selectedText` | `NSString *` | Currently selected text (`@""` if none). |
| `+selectSubstring:` | `BOOL` | Select first occurrence of a string; NO if not found. |

### 3.4 Command registry (every toolbar/menu editing action)
> **Phase 1 (2026-06-29): the registry moved into the app target.** It now lives on `MPDocument`
> (`+[MPDocument availableCommandIDs]`, `-[MPDocument invokeCommandID:sender:error:]`, backed by a
> private `mp_commandRegistry` of id→work blocks). **All 32 editing IBActions are one-line
> delegations into it**, so the menu, the toolbar (`sendAction:`), and the harness/MCP all run the
> SAME code — "the GUI only confirms what the harness proves" is now literal, not aspirational. The
> `MPTestHarness` calls below are a thin façade over the document's registry. (The old test-only
> `+commandSelectorMap` was removed — the selector mapping no longer exists; commands are blocks.)

| Call (harness façade) | Returns | Notes |
|---|---|---|
| `+availableCommands` | `NSArray<NSString*>*` | All stable command ids, sorted. Forwards to `+[MPDocument availableCommandIDs]`. |
| `+invokeCommand:error:` | `BOOL` | Invoke a command by id against the current doc, exactly as the toolbar/menu would (same registry). NO + error for unknown id / no document. Forwards to `-[MPDocument invokeCommandID:sender:error:]` (sender = nil), then settles the runloop. |

**Command ids** (see §4 for the full matrix). Inline: `strong`, `emphasis`, `code`,
`strikethrough`, `underline`, `highlight`, `comment`, `link`, `image`. Headings: `h1`…`h6`,
`paragraph`. Blocks: `ul`, `ol`, `blockquote`, `indent`, `unindent`, `newParagraph`. Output:
`copyHtml`, `render`. View: `togglePreviewPane`, `toggleEditorPane`, `toggleToolbar`,
`editorOneQuarter`, `editorThreeQuarters`, `equalSplit`. Modal (NOT for automation):
`exportHtml`, `exportPdf`.

### 3.5 Layout / view state (NEW — assert view-toggle commands)
| Call | Returns | Notes |
|---|---|---|
| `+previewVisible` | `BOOL` | Preview pane width != 0. |
| `+editorVisible` | `BOOL` | Editor pane width != 0. |
| `+toolbarVisible` | `BOOL` | Window toolbar visible. |

### 3.6 Document operations
| Call | Returns | Notes |
|---|---|---|
| `+openFileAtPath:timeout:error:` | `BOOL` | Opens a file and waits (pumping the **main** runloop — must NOT block; the completion handler is delivered on the main thread). Headless: parks the window invisible/off-screen after open. |
| `+openFileAtPath:error:` | `BOOL` | Same, 10 s timeout. |
| `+simulateIdleForSeconds:` | `void` | Spins the runloop (does NOT `sleep()`; the WebView render is async on the main runloop). |
| `+forceRefreshPreview` | `void` | Resets `isPreviewReady` and re-renders. |
| `+switchToDocumentWithURL:error:` | `BOOL` | Brings another open doc's window forward (skips focus-steal in headless mode). |

### 3.7 Diagnostics
| Call | Returns | Notes |
|---|---|---|
| `+diagnosticReport` | `NSString *` | Human-readable dump: document URL, markdown/HTML lengths, preview ready/blank/valid, body text preview, blank-canvas verdict. |
| `+printDiagnosticReport` | `void` | NSLogs the report. |
| `+previewWebViewState` | `NSDictionary *` | Machine-readable preview state (exists/loading/ready/blank/valid/body length…). |

### 3.8 Test assertions (raise on failure)
`+assertPreviewReadyAndNotBlank:`, `+assertPreviewContainsText:context:`,
`+assertNoBlankCanvasBug:`.

### 3.9 `MPTestResult`
A small success/failure value object (`success`, `error`, `data`, `message`) with
`+successWithData:`, `+successWithMessage:`, `+failureWithError:`, `+failureWithMessage:`. Available
for richer return values; the current API mostly uses `BOOL` + `NSError**`.

---

## 4. Adding a test (the pattern)

Per-command round-trip (this is the contract — input + command ⇒ exact markdown):

```objc
- (void)testCommand_strong {
    [MPTestHarness openFileAtPath:self.testFile1 error:NULL];
    [MPTestHarness setMarkdown:@"boldcheck"];
    [MPTestHarness selectAll];
    XCTAssertTrue([MPTestHarness invokeCommand:@"strong" error:NULL]);
    XCTAssertEqualObjects([MPTestHarness currentMarkdownContent], @"**boldcheck**");
}
```

Crash-safety (the `d0e2853` toolbar-crash class of bug) — invoke every non-modal command on an
empty doc / no selection and assert it never crashes (see `testCrashSafetySweepEmptyDocument`).

`tearDown` closes all open `NSDocumentController` documents so windows don't leak across tests.

---

## 5. Gotchas / hard-won facts (don't rediscover these)

- **Open must pump the main runloop, not block.** `-openDocumentWithContentsOfURL:` delivers its
  completion handler on the **main** thread; a blocking semaphore wait deadlocks and every open
  "times out." (fixed 2026-06-29)
- **Blank detection needs a time window.** A freshly-loaded WebView is briefly empty; an
  instantaneous read is a false positive. `isPreviewBlank` pumps up to 3 s. Never `sleep()`.
- **Headless invisibility = alpha 0, not position.** AppKit clamps off-screen windows to a sliver;
  `alphaValue = 0` is the real guarantee (WebView still renders).
- **Headless flag must be process-only.** Use the `MPHeadlessTestMode` env var, never a persisted
  `NSUserDefaults` (which would hide Jason's real app's windows).
- **Editing commands are editor-only.** `toggleStrong:` etc. operate on `self.editor` +
  `selectedRange` — no key window / frontmost app required, so they're fully headless-testable.
- **`exportHtml`/`exportPdf` open a modal `NSSavePanel`** — exclude them from automated runs (they'd
  hang). Verify those by hand (see `docs/TEST-MATRIX.md`).
- **`pmh_parser.c` is a committed generated file** (`Dependency/peg-markdown-highlight/`). A fresh
  clone builds first-try because of it; regenerate + recommit if `pmh_grammar.leg` changes.

---

## 6. Roadmap hooks (where this is going)

The command ids here are the **stable contract** that also backs the **MCP server** (MASTER-PLAN
Phase 3): `run_command(id)` → `-[MPDocument invokeCommandID:sender:error:]` (call it directly — no
need to go through the test harness). **The GUI-routing refactor is DONE (2026-06-29):** the registry
lives on `MPDocument` in the app target and every editing IBAction delegates into it, so the menu,
the toolbar, the harness, and the MCP share one behavior path — "the UI just confirms what the
harness proves" is literally true. An app-target `MPAutomation` class was considered and dropped: the
document already *is* the in-process control surface, so a separate class would be ceremony. The only
Phase-1 item left is the periodic human GUI parity spot-check (MASTER-PLAN §11). See
`docs/MASTER-PLAN.md` §4.
