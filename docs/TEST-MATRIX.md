# mdeditor — Test Matrix & Pre-Ship Checklist

> **Purpose.** One page a Claude (or Jason) runs **before every ship** of a Debug→Release.
> The whole point: get as far as possible **headless** (automated, no UI on the desktop), and
> leave only a tiny, explicit list for a **human** to eyeball. Paint-by-numbers on purpose.
>
> Pipeline (the forcing function):
>
> ```
> Debug build  ->  automated headless matrix (Scripts/test.sh)  ->  human UI verification  ->  ship Release
>     §1               §2  (Claude, deterministic)                      §3 (Jason, ~2 min)        §4
> ```
>
> SSOT: this file in the repo. Harness reference: `docs/TEST-HARNESS.md`. Updated 2026-06-29.

---

## 1. Debug build

```bash
Scripts/test.sh            # builds Debug + runs the whole suite headless
```

Green here is the gate for everything below. A fresh clone builds first-try (the generated
`pmh_parser.c` is committed). Current suite: **44 tests, 0 failures.**

---

## 2. Automated function matrix (headless — Claude runs this)

Every editing command has a stable id in the harness registry (`+availableCommands`). Coverage
legend: **✅ round-trip** = exact-output assertion · **🟡 swept** = invoked by the crash-safety
sweep (proves no-crash; add an exact assertion when behavior is pinned) · **👤 UI** = needs a human
(modal panel or purely visual) — see §3.

### Inline formatting (`self.editor` ops — fully headless)
| id | selector | coverage | test |
|---|---|---|---|
| `strong` | toggleStrong: | ✅ round-trip | `testCommand_strong` → `**x**` |
| `emphasis` | toggleEmphasis: | ✅ round-trip | `testCommand_emphasis` → `*x*` |
| `code` | toggleInlineCode: | ✅ round-trip | `testCommand_inlineCode` → `` `x` `` |
| `strikethrough` | toggleStrikethrough: | ✅ round-trip | `testCommand_strikethrough` → `~~x~~` |
| `underline` | toggleUnderline: | ✅ round-trip | `testCommand_underline` → `_x_` |
| `highlight` | toggleHighlight: | ✅ round-trip | `testCommand_highlight` → `==x==` |
| `comment` | toggleComment: | ✅ round-trip | `testCommand_comment` → `<!--x-->` |
| `link` | toggleLink: | 🟡 swept | reads pasteboard; add round-trip w/ seeded pasteboard |
| `image` | toggleImage: | 🟡 swept | reads pasteboard; add round-trip w/ seeded pasteboard |

### Headings / paragraph (fully headless)
| id | selector | coverage | test |
|---|---|---|---|
| `h1` | convertToH1: | ✅ round-trip | `testCommand_heading1` → `# x` |
| `h2` | convertToH2: | ✅ round-trip | `testCommand_headingTogglesBackToParagraph` → `## x` |
| `h3` | convertToH3: | ✅ round-trip | `testCommand_heading3` → `### x` |
| `h4`–`h6` | convertToH4:…H6: | 🟡 swept | **TODO:** add explicit round-trips (paint-by-numbers, ~3 lines each) |
| `paragraph` | convertToParagraph: | ✅ round-trip | toggles heading back to plain |

### Blocks (fully headless)
| id | selector | coverage | test |
|---|---|---|---|
| `ul` | toggleUnorderedList: | ✅ round-trip | `testCommand_unorderedList` |
| `ol` | toggleOrderedList: | ✅ round-trip | `testCommand_orderedList` → `1. x` |
| `blockquote` | toggleBlockquote: | ✅ round-trip | `testCommand_blockquote` → `> x` |
| `indent` | indent: | ✅ round-trip | `testCommand_indentUnindent` |
| `unindent` | unindent: | ✅ round-trip | `testCommand_indentUnindent` |
| `newParagraph` | insertNewParagraph: | 🟡 swept | add round-trip when semantics pinned |

### Output / view (invokable headless; assert via state getters)
| id | selector | coverage | notes |
|---|---|---|---|
| `copyHtml` | copyHtml: | 🟡 swept | writes pasteboard; assert `currentRenderedHTML` |
| `render` | render: | 🟡 swept | re-renders preview |
| `togglePreviewPane` | togglePreviewPane: | 🟡 swept | assert via `+previewVisible` |
| `toggleEditorPane` | toggleEditorPane: | 🟡 swept | assert via `+editorVisible` |
| `toggleToolbar` | toggleToolbar: | 🟡 swept | assert via `+toolbarVisible` |
| `editorOneQuarter` / `editorThreeQuarters` / `equalSplit` | setEditor…/setEqualSplit: | 🟡 swept | split ratios |

### Document / preview lifecycle (headless)
| area | coverage | test(s) |
|---|---|---|
| open + render | ✅ | `testSequentialFileOpensWithIdle`, `testRapidFileSwitching` |
| blank-canvas bug | ✅ | sequential/rapid/repeated open scenarios |
| preview state flags | ✅ | `testPreviewStateConsistency` |
| force refresh | ✅ | `testForceRefreshRecovery` |
| diagnostics | ✅ | `testDiagnosticReporting` |
| **headless invisibility** | ✅ | `testHeadlessModeKeepsEveryWindowInvisible` (2 docs + switch, 0 on-screen) |
| crash-safety sweep | ✅ | `testCrashSafetySweepEmptyDocument` (every non-modal cmd) |

### NOT automatable (modal panels) → must be human-verified (§3)
| id | selector | why |
|---|---|---|
| `exportHtml` | exportHtml: | opens a modal `NSSavePanel` (would hang automation) |
| `exportPdf` | exportPdf: | modal `NSSavePanel` + print pipeline |

---

## 3. Human UI verification (Jason — ~2 minutes, only what can't be headless)

Run the **Debug** app once and confirm:

- [ ] App launches, a document window appears and the **preview renders** (not blank).
- [ ] Click a few toolbar buttons (bold, a heading, a list) — editor changes as expected
      (this is the *parity* check: the GUI should match what the headless tests already prove).
- [ ] **File ▸ Export ▸ HTML** writes a file; open it — content looks right. *(exportHtml)*
- [ ] **File ▸ Export ▸ PDF** writes a file; open it — content looks right. *(exportPdf)*
- [ ] Toolbar/menu look correct; no visual glitches in the rendered themes you use.

> Everything else is already covered headless. If a behavior here ever surprises you, that's a
> signal to grow the harness so the *next* ship catches it automatically.

---

## 4. Ship the Release build

- [ ] Headless matrix green (§1–§2) **and** UI verification done (§3).
- [ ] Build Release: `xcodebuild -workspace MacDown.xcworkspace -scheme MacDown -configuration Release build`
      — note Release is pinned to `GCC_OPTIMIZATION_LEVEL=0` on purpose (launch-path UB workaround,
      commit `e645264`); don't "optimize" without doing MASTER-PLAN Phase 5.
- [ ] Install / archive as needed; record the shipped commit.

---

## 5. Paint-by-numbers TODOs (grow coverage, cheap wins)

- [ ] Explicit round-trips for `h4`–`h6` (mirror `testCommand_heading1`).
- [ ] `link`/`image` round-trips with a seeded pasteboard URL.
- [ ] State-getter assertions for the view-toggle commands (`previewVisible` etc.).
- [ ] `copyHtml` → assert pasteboard / `currentRenderedHTML`.
- [ ] (Optional) split the command tests into their own `MacDownTests/MPCommandTests.m`
      (needs a pbxproj target-membership add — verify with a fresh-clone build).
