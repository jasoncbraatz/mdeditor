# Parser fuzz harnesses (SECURITY-AUDIT finding 7)

ASan/UBSan harnesses for the three parsers a **malicious `.md` can drive** with
fully attacker-controlled bytes:

| Harness | Parser | Reachable via |
|---|---|---|
| `hoedown_harness.c` | hoedown 3.0.7 (`Pods/hoedown/src`) | markdown **body** render (`MPRenderer parseMarkdown:`) |
| `pmh_harness.c` | peg-markdown-highlight `pmh_parser.c` (generated) | **syntax highlighting** (`HGMarkdownHighlighter`) |
| `yaml_harness.c` | LibYAML 0.1.4 (`Pods/LibYAML/src`) | **YAML front-matter** (`NSString+Lookup` → `YAMLSerialization`) |

`hoedown_thread.c` renders on a **512KB pthread stack** (matching the
`NSOperationQueue` `parseQueue` MacDown actually parses on) to measure the real
production stack-overflow threshold.

## Use

```sh
Scripts/fuzz/build.sh                # build harnesses under ASan+UBSan
Scripts/fuzz/build.sh --cve-control  # also build the guard-removed LibYAML control
Scripts/fuzz/run.sh                  # generate corpus + run all; non-zero on a NEW defect
```

`run.sh` knows which defects are accepted-open (finding 7b/7c) and only fails on
**new** ones, so it can be promoted to a CI gate (finding 9). Builds are
standalone clang — **no Xcode/app build required**.

## Findings (2026-06-30, first fuzz pass)

All five were the **deep-nesting / unbounded-recursion** class (no defect on the
other 31 corpus inputs).

- **7a — hoedown body, FIXED.** `deep_blockquote.md` (tens of thousands of `> `)
  → stack-overflow in `parse_block` recursion. hoedown *ships* a `max_nesting`
  guard; MacDown passed `SIZE_MAX`, disabling it. **Fix:** cap
  `kMPRendererNestingLevel` at **1000** (`MPRenderer.m`). Measured overflow floor
  on the 512KB parseQueue stack at -O0 ≈ 2000–3000 → 1000 = 2–3× margin, ~20–30×
  beyond any realistic document. `run.sh` asserts the cap holds every run.
- **7b — pmh_parser, OPEN.** `deep_brackets.md` → stack-overflow
  (`yymatchChar`/`yy_Inline` recursion); `deep_nested_links.md` → **heap**-overflow
  in `yySet` (`pmh_parser.c:1258`) — the leg val-stack (`G->val`) is advanced by
  `yyPush` with no grow-guard, so deep nesting writes OOB. Fix needs a fork-and-own
  of the generated parser (grow/bound the val-stack, or cap input nesting before
  `pmh_markdown_to_elements`). Highlighting only; editor thread.
- **7c — LibYAML loader, OPEN.** `deep_flow_seq.yaml` / `deep_flow_map.yaml`
  (tens of thousands of `[`/`{`) → stack-overflow in `yaml_parser_load_node`
  recursion (`loader.c`). 0.1.4 has no depth limit. Fix: a depth cap via the
  `Podfile post_install` hook (like the CVE patch), or bound front-matter size.
  Front-matter path only (Jekyll-detect pref).

## CVE-2014-2525 validation (the reason a plain XCTest was deferred to here)

`build.sh --cve-control` builds LibYAML with the `STRING_EXTEND` guard removed.
On `corpus/cve_2014_2525.yaml` (a verbatim tag with 5000 `%41` escapes):

- `yaml_fuzz_unpatched` → **ASan heap-buffer-overflow** in `yaml_parser_scan_tag_uri`
  (reached via `yaml_parser_load` — MacDown's exact front-matter path). rc=134.
- `yaml_fuzz` (patched) → clean, rc=0.

So the post_install `STRING_EXTEND` fix demonstrably closes the overflow.
