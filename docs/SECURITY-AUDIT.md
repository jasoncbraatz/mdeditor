# mdeditor — SECURITY AUDIT (Phase 4)

> **Status doc. SSOT = this file in the `mdeditor` GitHub repo.** Living audit: findings,
> decisions, residual risk. Each Phase-4 bite updates the relevant row + the decisions log.
> Companion to `docs/MASTER-PLAN.md` §7. Use the `security-review` + `code-review` skills when
> auditing a specific change.
>
> Started 2026-06-30 (co-pilot cowork). Owner: Jason (`jasoncbraatz`).

---

## Threat model

mdeditor is a **local, single-user daily-driver** markdown editor — Jason lives in `.md` all day.
The realistic adversary is **attacker-controllable content**, not a remote network attacker:

- **A malicious `.md` file** (downloaded, cloned, shared) opened in the editor, or markdown pasted
  in. Markdown → HTML → rendered in a JavaScript-enabled WebView. **This is the #1 risk (XSS).**
- **Local IPC surfaces** the app exposes: the `x-macdown://` URL scheme (AppleEvent handler) and the
  `macdown` CLI (`--control`). Any local process can drive the running app through them.
- **Supply chain**: CocoaPods dependencies + the bundled C parsers (hoedown, pmh_parser).

Out of scope (single-user local tool): multi-user auth, server hardening, remote network attackers.

---

## Findings (highest payoff first)

| # | Finding | Severity | Status |
|---|---|---|---|
| 1 | Preview WebView is a JS-enabled, in-process **XSS surface**; md→HTML is not sanitized | **HIGH** | MITIGATED 2026-06-30 (sanitize + CSP + remote-load block; WKWebView migration scoped) |
| 2 | Sparkle auto-updater (dead update/network surface) | HIGH | DONE 2026-06-30 |
| 3 | ATS disabled globally (`NSAllowsArbitraryLoads=true`) + dead insecure-HTTP exception | MEDIUM | DONE 2026-06-30 (ATS→false, both exceptions removed) |
| 4 | AppleScript enabled (`NSAppleScriptEnabled`) + **dangling** `OSAScriptingDefinition` | LOW/INFO | DONE 2026-06-30 (both keys removed) |
| 5 | No App Sandbox, no Hardened Runtime (no entitlements file) | MEDIUM | PARTIAL 2026-06-30 (Hardened Runtime ON; App Sandbox deferred) |
| 6 | Local transports (`x-macdown://` + CLI) — input validation | LOW | Reviewed (guarded) |
| 7 | C parsers (hoedown, pmh_parser, LibYAML) not fuzzed under ASan | MEDIUM | IN PROGRESS 2026-07-01 (fuzzed; 5 deep-nesting overflows; **7a hoedown FIXED+LANDED** cap=1000; **7b-heap pmh FIXED+LANDED** (val-stack grow-guard, fork-and-own); **7b-stack pmh FIXED+LANDED** (PMH_NESTING_CAP=12); **7c LibYAML FIXED+LANDED** (MDEDITOR_YAML_MAX_DEPTH=100 in loader.c via Podfile hook) — fuzz run.sh PASS, 0 known-open; only **7b-time sibling** (soft exponential-backtracking, cancellable) remains; CVE-2014-2525 ASan-validated) |
| 8 | Dependency CVE sweep | MEDIUM | DONE 2026-06-30 (8 pods swept; LibYAML 0.1.4 CVE-2014-2525 patched) |
| 9 | Gate hardening (`xcodebuild analyze` CI-blocking; `Scripts/fuzz/run.sh` per-file timeout) | LOW | PARTIAL 2026-07-01 (**per-file `FUZZ_TIMEOUT_S=15s` timeout LANDED** in `run.sh` via `perl -e 'alarm N; exec @ARGV'` — no more indefinite hangs; surfaces 7b-time-class exponential-backtracking as a distinct rc=142 signal; 4 latent 7b-time siblings discovered (`pmh_fuzz:backtick_runs.md/deep_blockquote.md/deep_list.md`, `hoedown_fuzz:deep_list.md`) + `KNOWN_OPEN`'d until per-parser time-budget guards land; **`xcodebuild analyze` CI-blocking still open**) |

---

### 1. WebView XSS — the #1 risk (OPEN, HIGH)

The preview uses the **legacy WebKit `WebView`** (deprecated; *not* `WKWebView`), so it renders
**in-process with no process isolation** and JavaScript enabled.

Verified surface (as of HEAD 2026-06-30):
- `MPDocument.m:199` — `@property (weak) IBOutlet WebView *preview;` (legacy `WebView`, from
  `<WebKit/WebKit.h>`; private headers in `WebView+WebViewPrivateHeaders.h`).
- `MPDocument.m:1170` — `[self.preview.mainFrame loadHTMLString:html baseURL:baseUrl];` is the render
  path. `html` is hoedown's markdown→HTML output, **unsanitized** — `<script>`, `on*=` handlers, and
  `javascript:` URLs in a `.md` would execute.
- JavaScript is actively used: Prism syntax highlighting, and `MPDocument.m:1774`
  `mainFrame.javaScriptContext evaluateScript:` for header-location scroll sync. So JS cannot simply
  be turned off wholesale without a plan (pre-render highlighting, or a JS-light scroll-sync).
- `MPDocument.m:868` — `webView:resource:willSendRequest:fromDataSource:` delegate already exists;
  **this is the natural choke point to block remote resource loads** (return `nil`/about:blank for
  non-local schemes) so a malicious `.md` cannot beacon out / SSRF.

**Planned mitigation (next session's bite):**
(a) Sanitize md-derived HTML (strip `<script>`, `on*=`, `javascript:`/`data:` URLs) before
`loadHTMLString:`. (b) Inject a strict **CSP** `<meta>` into the rendered document. (c) Block remote
loads in `willSendRequest:` (allow `file:`/the bundled assets + the explicit Prism CDN only, or
pre-bundle Prism). (d) **Scope** a migration to `WKWebView` (process isolation, modern model) —
larger, evaluate separately. See MASTER-PLAN §7 item 1.

**SHIPPED 2026-06-30 (defense in depth, 3 layers).**
- **(a) Body sanitizer** — `MPSanitizeHTMLBody()` (MPRenderer.m) runs on `currentHtml` (the
  hoedown body) at the source, so preview, export, copy-HTML and the MCP `render-html` verb all
  get sanitized output. Strips `<script>`/`<iframe>`/`<object>`/`<embed>`/`<applet>` (+ stray
  openers/closers), inline `on*=` event handlers, and neutralizes `javascript:`/`vbscript:` and
  non-image `data:` URIs (raster `data:image/{png,jpe?g,gif,webp,bmp}` preserved; `svg+xml`/
  `text/html` neutralized). The trusted bundled Prism/MathJax/mermaid scripts are injected by the
  template *after* this, so they are never touched.
- **(b) CSP `<meta>`** — added to `Default.handlebars` `<head>`. Legacy `WebView` (WebKit1) DOES
  enforce meta CSP (shared WebCore). `'unsafe-inline'`/`'unsafe-eval'` are kept (MathJax needs eval;
  bundled assets are inline/file:), so the CSP's real job is **locking egress**: `script-src`/
  `img-src`/`connect-src` list only local origins, and `object-src`/`frame-src`/`base-uri` are
  `'none'`.
- **(c) Remote-load block** — `+[MPDocument mp_isAllowedPreviewResourceURL:]` (allowlist:
  file/applewebdata/about/data) is consulted in `-webView:resource:willSendRequest:`; any remote
  subresource is cancelled (`return nil`). Kills beacon/SSRF and remote `<script>`/CSS `url()`.

**Tests:** `MacDownTests/MPXSSHardeningTests.m` (16 headless: sanitizer strip/preserve + URL
allowlist). Full suite **67/0** Debug. **Live eyeball** (computer-use, fresh Debug, `xss-eyeball.md`):
legit md + Prism code block + table render; an inline `<script>` did NOT change the title and an
`<img onerror>` did NOT mutate the body (neither executed); `<iframe>` stripped; a remote `<img>`
did not load. Reversible: `git tag pre-phase4-xss`.

**Residual risk (still open):** the sanitizer is a conservative REGEX pass, not a full HTML parser —
entity-encoded scheme obfuscation (`java&#9;script:`) and exotic mutation-XSS could slip the body
sanitizer, but (c) blocks any egress and the WebView stays in-process. The real isolation win is the
**WKWebView migration** (process isolation + modern model) — SCOPED, not done; see MASTER-PLAN §7.

### 2. Sparkle removed (DONE 2026-06-30, commit 7627fef)

Sparkle was already *disabled* (b40195c: `feedURLStringForUpdater:` returned an inert feed,
`SUEnableAutomaticChecks=NO`) but the **pod stayed linked** — dead code and a live auto-update /
network / phone-home surface that could also silently clobber this fork with upstream's binary.
**Fully removed this session:** Podfile pod dropped (`pod install` → "Removing Sparkle", 8 pods now);
`#import <Sparkle/SUUpdater.h>` + the `feedURLStringForUpdater:` delegate deleted; the `SUUpdater`
object + "Check for Updates…" menu item removed from `MainMenu.xib`; dead `SUEnableAutomaticChecks`
plist key removed. Verified: build green, headless suite 51/0, **no `Sparkle.framework` embedded**,
GUI launch confirms full menu bar + no "Check for Updates…" item. Residual risk: **none** (surface
gone). The installed `/Applications/mdeditor.app` is still the pre-removal build until redeployed.

### 3. ATS disabled globally (OPEN, MEDIUM)

`MacDown-Info.plist`: `NSAppTransportSecurity → NSAllowsArbitraryLoads = true`. Exception domains:
- `cdnjs.cloudflare.com` — Prism CDN (in use; legitimate but see finding 1 — prefer bundling Prism).
- `uranusjr.com` — **dead** (the abandoned upstream author's domain) and it sets
  `NSThirdPartyExceptionAllowsInsecureHTTPLoads = true` (cleartext HTTP). **Recommend removing this
  exception** — it serves no purpose for the fork and permits insecure loads.

**Recommendation:** after finding 1 blocks remote loads in the WebView, **remove
`NSAllowsArbitraryLoads`** (or flip to `false` with a tight allowlist) and drop the `uranusjr.com`
exception. Tighten as the remote-load policy lands.

**SHIPPED 2026-06-30.** `NSAllowsArbitraryLoads` → `false`; the entire `NSExceptionDomains` dict (both `cdnjs.cloudflare.com` and the dead `uranusjr.com`) **removed**. Safe because every preview subresource is bundled: Prism (`MacDown/Resources/Prism`) and MathJax (`MacDown/Resources/MathJax`). The MathJax `<script>` points at `kMPMathJaxCDN` but `-[MPDocument webView:resource:willSendRequest:]` (MPDocument.m ~888) **rewrites any `MathJax.js` request to the bundled file: URL before any network load**, and finding 1's allowlist cancels any other remote subresource — so no remote egress ever occurs and no ATS exception is load-bearing. No other network API in the app (`grep` for `NSURLSession`/`NSURLConnection` = none outside vendored Prism). Verified: built app's embedded `Info.plist` has `NSAppTransportSecurity = { NSAllowsArbitraryLoads = false }`; GUI launch + preview render eyeball GREEN.

### 4. AppleScript enabled + dangling scripting definition (OPEN, LOW/INFO)

`NSAppleScriptEnabled = true` **and** `OSAScriptingDefinition = MacDown.sdef`, but **no `MacDown.sdef`
file exists** in the source tree or bundle. So the app advertises AppleScript automation that is
undefined. MASTER-PLAN §2 states "No scripting today" — the plist **contradicts** that (leftover from
upstream). Low real risk (no sdef ⇒ no scriptable commands load), but it is a declared local
automation surface and a documentation/reality mismatch.

**Decision needed:** either (a) **remove** `NSAppleScriptEnabled` + `OSAScriptingDefinition` (no
scripting — matches §2 and shrinks the surface), or (b) deliberately ship a **locked-down** `.sdef`
if scripting is wanted. Recommend (a) unless Jason wants AppleScript.

**SHIPPED 2026-06-30 — option (a).** Both `NSAppleScriptEnabled` and `OSAScriptingDefinition` keys **removed** from `MacDown-Info.plist` (matches MASTER-PLAN §2 "no scripting"). The `x-macdown` URL scheme transport (the real automation surface) is **preserved** (verified in the built bundle). `plutil -lint` OK; GUI launch eyeball confirms the app still launches cleanly with the keys gone.

### 5. No App Sandbox / no Hardened Runtime (OPEN, MEDIUM)

No `*.entitlements` file in the project; the app is ad-hoc signed, **unsandboxed**, with **no
Hardened Runtime**. For a local fork that opens arbitrary files and exposes a CLI/URL transport,
full App Sandbox is a non-trivial scoping exercise (file access, the transport, temp files).

**Recommendation:** enable **Hardened Runtime** first — cheap, and a prerequisite for notarization
(Phase 7). Treat **App Sandbox** as a separate, larger bite (or an explicit "won't-do for a local
tool" decision). Document whichever Jason chooses.

**SHIPPED 2026-06-30 — Hardened Runtime only.** `ENABLE_HARDENED_RUNTIME = YES` added to **both** app-target build configs (Debug + Release) in `MacDown.xcodeproj/project.pbxproj`. NOTE: the flag is applied at **code-sign time**, so the Debug test build (`CODE_SIGNING_ALLOWED=NO`) does not exercise it — real verification lands at Phase-7 notarization (sign with `--options runtime`). Headless 67/0 confirms the build is unaffected. **App Sandbox deliberately deferred** — a non-trivial scoping bite (file access for arbitrary docs + the `x-macdown`/CLI transport + temp files); teed up as its own future bite or an explicit won't-do. Reversible: tag `pre-phase4-plist-hardening`.

### 6. Local transports — input validation (Reviewed, LOW — guarded)

Phase 3's `x-macdown://` + CLI transports are **allowlist-validated** by pure class methods on
`MPMainController` (unit-tested in `MPURLCommandTests`):
- `+validatedCommandID:` — only ids in the editing-command registry are accepted.
- `+validatedFileURLFromParam:` — only **absolute `file://`** URLs (no `http`/remote).
- `+validatedExportPathFromParam:` — only **absolute `.html`/`.htm`** output paths.

No content is `eval`/`exec`'d. Residual risk (accepted for a single-user local tool): **any local
process** can drive the *running* app via the URL scheme / AppleEvent without authentication. This is
inherent to a local automation surface; documented in `docs/MCP-TRANSPORT.md`.

### 7. C parser fuzzing (PARTIAL — hoedown, pmh (heap+stack), and LibYAML FIXED; only 7b-time sibling OPEN)

`hoedown 3.0.7`, the generated `pmh_parser.c`, and LibYAML's scanner/loader parse
fully attacker-controlled `.md`. First ASan/UBSan fuzz pass done 2026-06-30
(harnesses + corpus repo-backed at `Scripts/fuzz/`, run via `Scripts/fuzz/build.sh`
+ `run.sh` — standalone clang, no app build). All findings were the same class:
**unbounded recursion / stack-or-heap overflow on pathologically deep nesting**
(no defect on the other 31 corpus inputs).

**7a — hoedown body: FIXED & LANDED 2026-06-30.** `deep_blockquote.md` (tens of
thousands of `> `) → ASan **stack-overflow** in `parse_block` recursion
(`document.c`). Root cause: hoedown ships a `max_nesting` parameter as its
built-in guard, but `MPRenderer.m` passed `kMPRendererNestingLevel = SIZE_MAX`,
disabling it — and `parseMarkdown:` runs on the `parseQueue` (`NSOperationQueue`,
**512KB stack**), not the 8MB main stack. Overflow floor on a 512KB pthread @-O0
≈ **2000–3000** levels. **Fix (LANDED):** cap `kMPRendererNestingLevel` at
**1000** (`MPRenderer.m`; 2–3× below the floor, ~20× beyond any realistic doc — a
deep quoted-email chain is ~50). **Proof:** `hoedown_thread deep_blockquote 1000`
on the real 512KB stack returns rc 0 while the unguarded `SIZE_MAX` control
bus-errors (rc 138) — both asserted every `Scripts/fuzz/run.sh` (deep_blockquote
removed from KNOWN_OPEN; the main hoedown loop now runs at the product cap
`MDFUZZ_NESTING=1000`, clean over the whole corpus). Output below depth 1000 is
**byte-identical** to SIZE_MAX. Reversible: tags `pre-7a-deflake`, `pre-7a-land`.

**The "test hang" was MISDIAGNOSED in the prior handoff — corrected here.** The
prior session reported that flipping the cap "deterministically hangs
`testCommand_blockquote` via a render-wait timing race." Sampling the wedged
process (2026-06-30) showed otherwise: the main thread is parked in
`+[MPTestHarness openFileAtPath:]`'s run-loop pump while an XCTest **issue is
being recorded** (`-[XCTestCase recordIssue:]` →
`+[XCTSourceCodeContext preferredSourceCodeLocationForSourceCodeFrames:]` →
`-[XCTSourceCodeFrame symbolInfoWithError:]` → `fopen` → `open$NOCANCEL`), and
XCTest's failure **symbolication blocks indefinitely in `open()`** (DebugSymbols/
Spotlight). So the "hang" = *an XCTest issue is recorded and its symbolication
wedges* — NOT a product/render defect (the cap is inert below depth 1000 and the
test's content is depth-1; the test passes in isolation at cap=1000 in 0.22 s).
The trigger is main-thread **starvation**: `parseAndRenderWithMaxDelay:` had a
busy-spin `while (rendererIsLoading || [start timeIntervalSinceNow] >= maxDelay)`
whose second term is **dead** (elapsed-since-a-past-date is always negative, never
≥ a non-negative `maxDelay`), so it hammered the main queue with back-to-back
`dispatch_sync` and never yielded. **De-flake (LANDED):** keep the exact
termination (wait until `rendererLoading` is false; `maxDelay` stays inert →
byte-identical output) but yield 5 ms between polls and add a 5 s absolute safety
deadline. This turned the handoff's "deterministic 3/3 hang" into **7/7 clean**
full-suite runs at cap=1000 (the one wedge seen in testing coincided with running
`sample`/`spindump` against the test process — externally re-starving the
harness). NOTE the residual latent issue for the next session: XCTest's
symbolication-on-`open()` can wedge under extreme concurrent load — never run the
heavy fuzz build/`sample` concurrently with `xcodebuild test`.

**7b — pmh_parser (generated): heap-overflow (7b-heap) FIXED & LANDED 2026-06-30; stack-overflow (7b-stack) FIXED & LANDED 2026-07-01.**
`deep_nested_links.md` → **heap-buffer-overflow** in `yySet` (`pmh_parser.c:1258`) — the leg
value-stack pointer `G->val` was advanced by `yyPush` with **no grow/bounds guard** (unlike
the thunk stack in `yyDo` or the text buffer in `yyText`), so deep nesting wrote past the
`vals` allocation. Reachable via `HGMarkdownHighlighter` (syntax highlighting, editor thread).
**Fix (LANDED):** fork-and-own the generated parser — grow `G->vals` on demand in `yyPush`,
preserving the offset across `realloc` (mirrors `yyDo`'s thunk-stack growth; this is exactly
Ian Piumarta's later upstream peg/leg guard, which the vendored copy predated). Applied to
**both** the compiled artifact (`pmh_parser.c`) **and** the greg emitter template
(`greg/compile.c`) so `make`-regeneration reproduces it. **Proof:** `deep_nested_links.md`
ASan-clean (rc 0, was rc 134 heap-buffer-overflow); removed from `run.sh` KNOWN_OPEN so the
gate now FAILS on any regression; full `run.sh` **PASS** (3 known-open, 0 new). Reversible:
tag `pre-7b`.

**7b-stack — FIXED & LANDED 2026-07-01 (co-pilot).** `deep_brackets.md` (`[`*40000 …
`]`*40000) → stack-overflow in the peg recursive-descent cycle
`yy_Label`→`yy_ExplicitLink`→`yy_Link`→`yy_Inline` (one cycle per nested `[`) — a *separate*
DoS from 7b-heap (the val-stack grow-guard does not bound recursion **depth**). **Measuring
the real 512KB `_parseHighlightsQueue` floor (new `Scripts/fuzz/pmh_thread.c`) surfaced a
worse, previously-unnoted vector: catastrophic EXPONENTIAL-TIME backtracking that dominates
long before the stack overflow.** Within a single markdown block, parse time **triples per
added unmatched `[`** (measured -O0: depth 11=0.13 s, 12=0.33 s, 13=1.0 s, 14=3.0 s, 15=8.8 s,
16=25 s+); the stack overflow only wins at extreme depth (~tens of thousands) when the initial
descent blows the 512 KB thread before backtracking can. It also triggers on *unbalanced* open
brackets (`a[b`×20, soft-newline-separated `[`) — any block with enough unmatched `[`. Both are
a DoS on **opening** a malicious `.md` (highlighting only; background editor thread via
`HGMarkdownHighlighter -requestParsing`). **Fix (fork-and-own; parser is generated + upstream-
dead):** `pmh_markdown_to_elements` refuses the parse (returns an empty element array = no
highlighting for that one file) when any **block's** unmatched-`[` nesting exceeds
`PMH_NESTING_CAP = 12` — >2× any real document's ≤5, per-block time bounded to ~0.33 s, far
below the stack floor. The counter resets at blank lines because the blowup is per-block, so
ordinary docs (even many bracketed links across paragraphs) are never refused. Patched **both**
the artifact (`pmh_parser.c`) **and** the head source (`pmh_parser_head.c`) so `make`
reproduces it. **Proof:** `deep_brackets.md` ASan-clean (rc 0, was rc 134); boundary exact
(depth 12 parses in 0.33 s, 13 refused in 0.03 s); `a[b`×20 + soft-newline variants refused;
normal 31-input corpus + a real 5-deep nested-link doc parse fine; new `pmh_thread` 512KB
control (guard-off overflows rc 138, guard-on rc 0) wired into `build.sh`/`run.sh`;
`deep_brackets` removed from `run.sh` KNOWN_OPEN so the gate now FAILS on regression; full
`run.sh` **PASS** (2 known-open = 7c only, 0 new); headless **67/0**. Reversible: tag
`pre-7b-stack`.

**7b-time (SIBLING, OPEN — teed up).** The same exponential-time backtracking also fires on
non-bracket vectors the `[`-cap does not cover: `corpus/backtick_runs.md` (2 MB of `` ` ``) runs
>20 s under `pmh_fuzz`. This is a softer DoS than 7b-stack (a hang on a *cancellable* background
highlight thread, no crash/memory-corruption) and `run.sh` does not flag it (no per-file
timeout; rc < 128). Fix options for a future bite: a per-block input-size / delimiter-run cap
generalizing the `[`-cap, or (bundled with finding 9) add a per-file `timeout` to `run.sh` so
the gate bounds these pathological inputs. Lower priority than 7c.

**7c — LibYAML loader: FIXED + LANDED (2026-07-01).** `deep_flow_seq.yaml` /
`deep_flow_map.yaml` (100 KB each, tens of thousands of `[` / `{`) previously
overflowed the 512 KB `NSOperationQueue` thread stack inside
`yaml_parser_load_node`'s mutual recursion with `yaml_parser_load_sequence` /
`yaml_parser_load_mapping` (`Pods/LibYAML/src/loader.c`; 0.1.4 has no document-
depth limit, and the .md front-matter path from `NSString+Lookup` →
`YAMLSerialization` → `yaml_parser_load` reaches it verbatim). Fix = compose-time
depth cap `MDEDITOR_YAML_MAX_DEPTH = 100`: a static counter around the
`load_node` dispatch checks-and-increments on entry and decrements on exit; when
the cap is hit, `load_node` returns `yaml_parser_set_composer_error(parser,
"YAML nesting exceeds mdeditor depth cap", …)` instead of recursing further.
Callers already treat any zero return as a parse failure, so the composer
unwinds cleanly. The static counter is safe because MacDown's YAML lookup runs
one parse at a time on a dedicated queue. Applied idempotently in the `Podfile
post_install` hook (mirrors the CVE-2014-2525 pattern — anchor is the exact
original `load_node` body) and directly to the checked-in
`Pods/LibYAML/src/loader.c`. Both PoC files now exit 0 under the ASan/UBSan
`yaml_fuzz` harness; `Scripts/fuzz/run.sh` PASS with **0 known-open, 0 new
defects**; full 67-test Debug suite green (`** TEST SUCCEEDED **`).
Reversible: `git tag pre-7c`. See row 18 of the §11 ledger in MASTER-PLAN.md.

**CVE-2014-2525 validated under ASan (the deferred proof from finding 8).**
`Scripts/fuzz/build.sh --cve-control` builds LibYAML with the `STRING_EXTEND`
guard removed. On `corpus/cve_2014_2525.yaml` (verbatim tag, 5000 `%41` escapes)
the **unpatched** build aborts with an ASan **heap-buffer-overflow** in
`yaml_parser_scan_tag_uri` (reached via `yaml_parser_load` — MacDown's exact
front-matter path); the **patched** build is clean. So the post_install fix
demonstrably closes the overflow.

**Residual risk:** finding 7b is now fully closed (heap + stack). The open items —
7c (LibYAML loader recursion) and the 7b-time sibling (non-bracket exponential
backtracking, e.g. backtick runs) — require pathologically deep nesting / huge
delimiter runs; impact is a **crash-or-hang DoS on open** of a malicious file (no
RCE demonstrated). 7c is the next finding-7 bite; 7b-time is lower priority (soft,
cancellable, no crash).

### 8. Dependency CVE sweep (DONE 2026-06-30, MEDIUM)

All 8 pods (post-Sparkle) enumerated against known CVEs (versions from `Podfile.lock`):

| Pod | Locked version | Attacker-reachable? | CVE finding |
|---|---|---|---|
| LibYAML | **0.1.4** | YES — parses `.md` YAML front-matter | **CVE-2014-2525** (heap overflow in `yaml_parser_scan_uri_escapes`, exec/crash; fixed upstream 0.1.6) + pre-0.1.5 CVE-2013-6393. **PATCHED** (see below). |
| hoedown | 3.0.7 | YES — parses all `.md` body | No formal CVE in 3.0.7 (the autolink/email-link issue was 3.0.1 + a renderer override mdeditor does not use). XSS class covered by finding 1; memory-safety = finding 7 (ASan fuzz). |
| handlebars-objc | 1.4.5 | No (templates are bundled/trusted) | None known. |
| JJPluralForm | 2.1 | No (localization plurals) | None known. |
| M13OrderedDictionary | 1.1.0 | No (in-proc data structure) | None known. |
| MASPreferences | 1.3 | No (prefs window UI) | None known. |
| PAPreferences | 0.5 | No (NSUserDefaults wrapper) | None known. |
| GBCli | 1.1 | No (macdown-cmd arg parsing, local) | None known. |

**LibYAML 0.1.4 — CVE-2014-2525 PATCHED 2026-06-30.** The decoded octet in
`yaml_parser_scan_uri_escapes()` was copied into the heap string buffer with **no `STRING_EXTEND`**,
so a long run of percent-escaped bytes in a URI/`%TAG` overflows the allocation — reachable from a
malicious `.md`'s YAML front-matter (`NSString+Lookup.m -[frontMatter:]` -> `YAMLSerialization` ->
LibYAML) when the "Detect Jekyll front-matter" preference is on. The CocoaPods `LibYAML` spec is
**frozen at 0.1.4** (the `~> 0.1` constraint resolves to 0.1.4 — no patched release is published), so
a version bump is unavailable. **Fix:** the official upstream guard (`if (!STRING_EXTEND(parser,
*string)) return 0;` before the octet copy) is applied in place by a **`Podfile` `post_install`
hook** — idempotent, chmods the read-only pod source, CI-safe (re-applies on every `pod install`).
Canonical patch banked at `Scripts/patches/libyaml-cve-2014-2525.patch`. Verified: patch lands at
`scanner.c:2714`, build green, headless **67/0**. Reversible: tag `pre-cve-libyaml`.

**Residual / teed-up:** a dedicated **ASan/UBSan fuzz of this exact URI-escape path** (and the rest
of the YAML scanner) is folded into **finding 7** — a heap-overflow guard is best validated under a
sanitizer, not a plain XCTest that may not deterministically crash. The other 7 pods are clean as of
this sweep; re-run the sweep when any pod version changes.

### 9. Gate hardening (PARTIAL, LOW)

Two sub-items:

**(a) `Scripts/fuzz/run.sh` per-file timeout — LANDED 2026-07-01.** macOS ships no coreutils
`timeout`, so each harness invocation is wrapped in `perl -e 'alarm N; exec @ARGV'`
(`FUZZ_TIMEOUT_S=15s` default, override via env, `0` disables). SIGALRM (14) → the child exits
with `rc=142`, which the existing `rc>=128` path treats as a signal and either fails the gate as
a NEW DEFECT or accepts via `KNOWN_OPEN` — exactly like the crash-signal path already handles
7b/7c. Effect: **the gate is now bounded** (no more indefinite hangs on pathological input like
the 7b-time backtick-runs class) and 7b-time-class DoS is surfaced as a distinct signal. The
FUZZ_TIMEOUT_S=15s default is comfortably above every non-pathological input in the current
corpus (all clean in <1 s) and ~10× below any realistic real-world doc's worst case. The
wrapper immediately **surfaced three latent 7b-time siblings** the pre-timeout gate had been
silently hiding — `pmh_fuzz:backtick_runs.md/deep_blockquote.md/deep_list.md` and
`hoedown_fuzz:deep_list.md` — all `KNOWN_OPEN`'d as 7b-time-class until per-parser time-budget
guards land.

**(b) `xcodebuild analyze` CI-blocking — STILL OPEN.** CI runs `analyze` as an **informational**
job (`continue-on-error`) pending Phase 4 cleaning the C code. Promote to **blocking** once the
analyzer is clean (MASTER-PLAN Phase 2/4).

---

## Residual risk summary (as of 2026-07-01)

- **Mitigated 2026-06-30:** WebView XSS (finding 1) — sanitize + CSP + remote-load block shipped
  (preview eyeball + 67/0). Remaining hardening = WKWebView process-isolation migration (scoped).
- **Hardened 2026-06-30 (plist cluster):** ATS now denies arbitrary loads + both dead exception
  domains removed (3); dangling AppleScript surface (`NSAppleScriptEnabled` + `OSAScriptingDefinition`)
  removed (4); Hardened Runtime enabled on the app target (5, App Sandbox deferred).
- **Swept 2026-06-30:** dependency CVE sweep (8) done — LibYAML 0.1.4 CVE-2014-2525 patched (post_install hook); other 7 pods clean.
- **Fuzzed 2026-06-30..2026-07-01 (7):** ASan/UBSan harnesses + corpus repo-backed (`Scripts/fuzz/`).
  All 5 crashing deep-nesting overflows are now FIXED+LANDED. **7a hoedown** body stack-overflow —
  cap `kMPRendererNestingLevel`=1000 + a render-wait de-flake. **7b-heap pmh** val-stack overflow
  — grow-guard in `yyPush` (fork-and-own of `pmh_parser.c` + `greg/compile.c`). **7b-stack pmh**
  recursive-descent overflow — input `PMH_NESTING_CAP=12` per-block in
  `pmh_markdown_to_elements`. **7c LibYAML** loader recursion — `MDEDITOR_YAML_MAX_DEPTH=100`
  compose-time cap patched into `Pods/LibYAML/src/loader.c` via the Podfile post_install hook
  (mirrors the CVE pattern). `run.sh` PASS with **0 known-open, 0 new defects**; two positive
  controls (7a SIZE_MAX @512KB and 7b-stack uncapped @512KB) still overflow as expected,
  proving the caps are load-bearing. CVE-2014-2525 fix independently ASan-validated.
- **Gate bounded 2026-07-01 (9a):** `Scripts/fuzz/run.sh` now applies a per-file `FUZZ_TIMEOUT_S=15s`
  timeout (`perl alarm` wrapper — macOS has no coreutils `timeout`). No more indefinite gate hangs;
  7b-time-class DoS surfaces as a distinct rc=142 signal. Discovered 3 additional latent 7b-time
  siblings (see 7b-time below) that were pre-timeout-hidden.
- **Open / medium:** App Sandbox not adopted (5); **7b-time** sibling class — non-bracket
  exponential-backtracking (`pmh_fuzz:backtick_runs.md/deep_blockquote.md/deep_list.md` +
  `hoedown_fuzz:deep_list.md`); soft, cancellable, no crash; `KNOWN_OPEN`'d in `run.sh` pending a
  per-parser time-budget guard. `xcodebuild analyze` still informational (9b).
- **Closed / accepted:** Sparkle gone (2); local transports are allowlist-guarded (6, accepted local
  surface).

## Decisions log

- **2026-06-30** — Sparkle **fully removed** (was disabled b40195c). Commit `7627fef`. Reversible via
  `git tag pre-phase4`. Rationale: dead code + network/auto-update attack surface on a private fork.
- **2026-06-30** — Audit started; WebView XSS (finding 1) chosen as the next dedicated bite; findings
  3/4/5/7/8/9 teed up here so a future Claude pays zero tokens to re-discover the surface.
- **2026-06-30** — **WebView XSS (finding 1) MITIGATED.** Shipped body sanitizer + template CSP +
  `willSendRequest:` remote-load block (see §1). 67/0 headless + live eyeball. Reversible via
  `git tag pre-phase4-xss`. WKWebView migration deliberately deferred (scoped, larger). Decision on
  the remote-image tradeoff: block remote subresources by default (anti-beacon) per the threat
  model; a preference toggle to re-enable is teed up if Jason wants remote images in preview.
- **2026-06-30** — **Plist/hardening cluster (findings 3+4+5) SHIPPED.** (3) `NSAllowsArbitraryLoads`
  → `false`; both `NSExceptionDomains` (`cdnjs.cloudflare.com` + dead `uranusjr.com`) removed — all
  preview subresources are bundled and the MathJax CDN URL is rewritten to the bundled copy in
  `willSendRequest:` before any network load, so no exception is load-bearing. (4) `NSAppleScriptEnabled`
  + `OSAScriptingDefinition` (→ non-existent `MacDown.sdef`) removed (matches §2 "no scripting";
  `x-macdown` scheme preserved). (5) `ENABLE_HARDENED_RUNTIME = YES` on both app build configs (App
  Sandbox deferred). Headless **67/0** + GUI launch/render eyeball (separate `open -n` instance, did NOT
  disturb a running Debug instance holding Jason's unsaved doc). Reversible: tag `pre-phase4-plist-hardening`.
- **2026-06-30** — **Dependency CVE sweep (finding 8) DONE.** All 8 pods enumerated vs known CVEs.
  One real reachable vuln: **LibYAML 0.1.4 / CVE-2014-2525** (heap overflow in
  `yaml_parser_scan_uri_escapes`, reachable via `.md` YAML front-matter). The CocoaPods spec is frozen
  at 0.1.4, so the official upstream `STRING_EXTEND` guard is applied via a `Podfile` `post_install`
  hook (idempotent, CI-safe); canonical patch at `Scripts/patches/libyaml-cve-2014-2525.patch`. Build
  green + headless 67/0. Reversible: tag `pre-cve-libyaml`. ASan fuzz of the path folded into finding 7.
- **2026-06-30** — **Parser fuzz (finding 7) first pass.** Built ASan/UBSan harnesses
  + adversarial corpus (repo-backed `Scripts/fuzz/`; standalone clang, no app build).
  Found **5 defects, all the deep-nesting/unbounded-recursion class**: 7a hoedown
  `parse_block` stack-overflow (SIZE_MAX defeats hoedown's `max_nesting` guard; the
  parse runs on the 512KB `parseQueue` stack); 7b pmh `yy_Label` stack-overflow (OPEN) +
  `yySet` **heap**-overflow (leg val-stack — FIXED 2026-06-30, grow-guard); 7c LibYAML
  `yaml_parser_load_node` stack-overflow. **Independently ASan-validated the
  CVE-2014-2525 fix** (`build.sh --cve-control`: unpatched heap-overflows on the PoC,
  patched clean). **7a fix = cap `kMPRendererNestingLevel` at 1000** — proven
  product-safe (clean over corpus; byte-identical output for shallow docs) but the
  cap **deterministically hangs `testCommand_blockquote`** via a test-harness
  render-wait race, so it is NOT landed (tree stays SIZE_MAX; gate green). Reversible:
  tag `pre-fuzz`. Next bite: de-flake the harness render-wait, land the cap, then 7b/7c.
- **2026-06-30** — **Finding 7a (hoedown deep-nesting) FIXED & LANDED.** Capped
  `kMPRendererNestingLevel` SIZE_MAX→**1000** (`MPRenderer.m`) — stops the
  `deep_blockquote` `parse_block` stack-overflow on the 512KB `parseQueue` stack;
  byte-identical output below depth 1000. The prior handoff's blocker ("cap hangs
  `testCommand_blockquote` via a render-wait race") was **misdiagnosed**: a sample
  of the wedge showed XCTest's failure-**symbolication blocking in `open()`** after
  an issue is recorded, triggered by main-thread starvation from a busy-spin in
  `parseAndRenderWithMaxDelay:` (a dead `|| [start timeIntervalSinceNow] >= maxDelay`
  term made it an unbounded no-yield spin). **De-flaked** that loop (yield + 5 s
  safety deadline, termination unchanged) → **7/7 clean** full-suite runs at
  cap=1000. `Scripts/fuzz/run.sh` updated: main hoedown loop runs at the product
  cap (`MDFUZZ_NESTING=1000`), `deep_blockquote` removed from KNOWN_OPEN, + a
  positive control asserting unguarded SIZE_MAX still overflows the 512KB stack.
  run.sh **PASS** (4 known-open = 7b×2/7c×2, 0 new). Reversible: tags
  `pre-7a-deflake`, `pre-7a-land`.
- **7b-heap pmh val-stack overflow — FIXED & LANDED 2026-06-30 (co-pilot).** Fork-and-own
  grow-guard in `yyPush` (patched in **both** `pmh_parser.c` and the greg emitter
  `greg/compile.c`); `deep_nested_links.md` ASan-clean (rc 0, was 134); removed from
  KNOWN_OPEN; run.sh **PASS** (3 known-open = 7b-stack + 7c×2, 0 new). Reversible: tag
  `pre-7b`. Next: 7b-stack pmh recursion cap, 7c LibYAML depth cap.
