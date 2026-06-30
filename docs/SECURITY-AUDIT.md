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
| 7 | C parsers (hoedown 3.0.7, pmh_parser.c) not fuzzed under ASan | MEDIUM | OPEN |
| 8 | Dependency CVE sweep | MEDIUM | OPEN |
| 9 | `xcodebuild analyze` not yet CI-blocking | LOW | OPEN |

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

### 7. C parser fuzzing (OPEN, MEDIUM)

`hoedown 3.0.7` + generated `Dependency/peg-markdown-highlight/pmh_parser.c` parse fully
attacker-controlled `.md`. **Not yet fuzzed under ASan/UBSan.** A malformed/adversarial document
could trigger a crash or memory-safety UB. Tee up a dedicated bite: build the parsers with
`-fsanitize=address,undefined`, run a corpus of adversarial markdown, fix/wrap any finding. (Ties to
MASTER-PLAN Phase 5, which is already chasing an `-Os` UB.)

### 8. Dependency CVE sweep (OPEN, MEDIUM)

Pods after Sparkle removal (8): `handlebars-objc ~>1.4`, `hoedown ~>3.0.7` (patched fork via the
`MacDownApp/cocoapods-specs` source), `JJPluralForm ~>2.1`, `LibYAML ~>0.1`, `M13OrderedDictionary
~>1.1`, `MASPreferences ~>1.3`, `PAPreferences ~>0.4`, `GBCli ~>1.1` (macdown-cmd only). Several are
old and pinned low (10.6/10.8 deployment targets). **`LibYAML 0.1`** in particular warrants a look
(libyaml has a CVE history). Action: enumerate versions vs known CVEs; fork-and-own + patch per
doctrine §12 if a vuln is found. Not yet performed.

### 9. `xcodebuild analyze` not yet CI-blocking (OPEN, LOW)

CI runs `analyze` as an **informational** job (`continue-on-error`) pending Phase 4 cleaning the C
code. Promote to **blocking** once the analyzer is clean (MASTER-PLAN Phase 2/4).

---

## Residual risk summary (as of 2026-06-30)

- **Mitigated 2026-06-30:** WebView XSS (finding 1) — sanitize + CSP + remote-load block shipped
  (preview eyeball + 67/0). Remaining hardening = WKWebView process-isolation migration (scoped).
- **Hardened 2026-06-30 (plist cluster):** ATS now denies arbitrary loads + both dead exception
  domains removed (3); dangling AppleScript surface (`NSAppleScriptEnabled` + `OSAScriptingDefinition`)
  removed (4); Hardened Runtime enabled on the app target (5, App Sandbox deferred).
- **Open / medium:** unfuzzed C parsers (7), un-swept dependencies (8); App Sandbox not adopted (5).
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
