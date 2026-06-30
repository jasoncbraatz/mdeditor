#!/usr/bin/env python3
"""Generate an adversarial corpus for the mdeditor parser fuzz harnesses.

Targets the three attacker-reachable parsers a malicious .md can drive:
  - hoedown 3.0.7 (markdown body)            -> *.md
  - peg-markdown-highlight pmh_parser.c      -> *.md
  - LibYAML 0.1.4 scanner (YAML front-matter)-> *.yaml

Pathological cases focus on the real risk surfaces: unbounded nesting
(MacDown runs hoedown at SIZE_MAX max_nesting), unbalanced span markers,
huge/degenerate tables, ref-definition floods, and the CVE-2014-2525
URI-escape overflow path.
"""
import os, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/mdfuzz/corpus"
os.makedirs(OUT, exist_ok=True)

def w(name, data):
    path = os.path.join(OUT, name)
    mode = "wb" if isinstance(data, (bytes, bytearray)) else "w"
    with open(path, mode) as f:
        f.write(data)
    print(f"  {name:42s} {os.path.getsize(path):>9d} B")

print("markdown (hoedown + pmh):")
# Deep nesting — the SIZE_MAX max_nesting stack-exhaustion candidate
w("deep_blockquote.md", "> " * 50000 + "x\n")
w("deep_list.md", "".join("  " * i + "- a\n" for i in range(2000)))
w("deep_emphasis.md", "*" * 60000 + "x" + "*" * 60000 + "\n")
w("deep_brackets.md", "[" * 40000 + "x" + "]" * 40000 + "\n")
w("deep_nested_links.md", ("[" * 5000) + "x" + ("](u)" * 5000) + "\n")
w("deep_atx_hash.md", "#" * 60000 + " heading\n")
w("deep_paren.md", "(" * 60000 + ")" * 60000 + "\n")
# Unbalanced / degenerate spans
w("unbalanced_emphasis.md", ("*a_b`c~d" * 20000) + "\n")
w("backtick_runs.md", ("`" * 1000 + "\n") * 2000)
w("tilde_strike.md", "~" * 100000 + "\n")
# Tables (HOEDOWN_EXT_TABLES is on)
w("wide_table.md", "|" + "h|" * 20000 + "\n|" + "-|" * 20000 + "\n|" + "c|" * 20000 + "\n")
w("tall_table.md", "|a|b|\n|-|-|\n" + "|c|d|\n" * 50000)
w("ragged_table.md", "".join("|" * (i % 50) + "\n" for i in range(20000)))
# Reference / footnote floods (FOOTNOTES ext on)
w("ref_flood.md", "".join(f"[{i}]: http://x/{i}\n" for i in range(50000)))
w("footnote_flood.md", "".join(f"[^{i}] " for i in range(50000)) + "\n")
w("autolink_flood.md", "<http://" + "a" * 100000 + ">\n")
# Fenced code chaos (FENCED_CODE on)
w("unclosed_fence.md", "```" + "x\n" * 50000)
w("nested_fences.md", ("```\n" * 20000))
# Math (MATH ext on)
w("math_runs.md", "$" * 100000 + "\n")
w("math_blocks.md", ("$$\n" * 20000))
# Encoding edge cases
w("nul_bytes.md", b"a\x00b\x00" * 20000 + b"\n")
w("invalid_utf8.md", b"\xff\xfe\x80\x81" * 30000 + b"\n")
w("high_bytes.md", bytes(range(128, 256)) * 2000 + b"\n")
w("crlf_mix.md", b"a\r\n\r b\r\t\n" * 20000)
# Front-matter + body combo (Jekyll detect path)
w("frontmatter_body.md", "---\ntitle: x\ntags: [a,b]\n---\n" + "> " * 10000 + "deep\n")
# Benign sanity control
w("benign.md", "# Title\n\nHello **world** with `code`, a [link](http://e.com),\n\n"
               "| a | b |\n|---|---|\n| 1 | 2 |\n\n- one\n- two\n\n$E=mc^2$\n")

print("yaml (LibYAML front-matter):")
# CVE-2014-2525 PoC — long URI-escape run in a verbatim tag
w("cve_2014_2525.yaml", "--- !<" + "%41" * 5000 + "> v\n")
w("cve_tag_directive.yaml", "%TAG !e! tag:x," + "%41" * 5000 + "\n--- !e!a v\n")
# Other YAML scanner stressors
w("deep_flow_seq.yaml", "[" * 50000 + "]" * 50000 + "\n")
w("deep_flow_map.yaml", "{" * 50000 + "}" * 50000 + "\n")
w("anchor_flood.yaml", "".join(f"a{i}: &x{i} 1\n" for i in range(50000)))
w("alias_loop.yaml", "a: &a [*a]\n")
w("long_scalar.yaml", "k: " + "v" * 500000 + "\n")
w("many_docs.yaml", "--- a\n" * 50000)
w("indent_bomb.yaml", "".join(" " * i + "k: 1\n" for i in range(2000)))
w("bad_escapes.yaml", '"' + "\\x" * 50000 + '"\n')
w("benign.yaml", "title: Hello\ntags:\n  - a\n  - b\ndate: 2026-06-30\n")

print("done.")
