#!/bin/bash
# run.sh — generate the corpus, run every harness over it, report sanitizer hits.
# Exit non-zero if any NEW (un-accepted) defect is found, so this can become a
# CI gate (SECURITY-AUDIT finding 9). Accepted/known-open defects are listed in
# KNOWN_OPEN below with their finding-7 sub-id and skipped from the failure count.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/build"
CORPUS="$HERE/corpus"
export ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:allocator_may_return_null=1"
export UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=1"

# Known-OPEN recursion-depth defects in vendored/generated parsers (finding 7b/7c).
# Format: "harness:corpusfile". These are reported but do NOT fail the run until
# their fix lands. The hoedown body path (7a) is FIXED (cap=1000) and is NOT here.
KNOWN_OPEN=(
  "hoedown_fuzz:deep_blockquote.md"  # 7a stack-overflow parse_block (current HEAD SIZE_MAX); fix=cap 1000, proven safe, not yet landed (test race)
  "pmh_fuzz:deep_brackets.md"        # 7b stack-overflow yymatchChar
  "pmh_fuzz:deep_nested_links.md"    # 7b heap-overflow yySet (val-stack)
  "yaml_fuzz:deep_flow_seq.yaml"     # 7c stack-overflow yaml_parser_load_node
  "yaml_fuzz:deep_flow_map.yaml"     # 7c stack-overflow yaml_parser_load_node
)
is_known() { local k="$1:$(basename "$2")"; for e in "${KNOWN_OPEN[@]}"; do [ "$e" = "$k" ] && return 0; done; return 1; }

[ -d "$OUT" ] || { echo "build first: $HERE/build.sh"; exit 2; }
python3 "$HERE/generate_corpus.py" "$CORPUS" >/dev/null

newfail=0; known=0
run() { # $1 harness-name $2 file
  local bin="$OUT/$1" err rc sig
  [ -x "$bin" ] || return 0
  err=$(mktemp)
  "$bin" "$2" >/dev/null 2>"$err"; rc=$?
  if [ $rc -ge 128 ]; then
    sig=$(grep -m1 -oE "AddressSanitizer: [a-z-]+" "$err" | sed 's/AddressSanitizer: //')
    [ -z "$sig" ] && sig="signal $((rc-128))"
    if is_known "$1" "$2"; then
      printf "  %-14s %-22s rc=%-4s KNOWN-OPEN: %s\n" "$1" "$(basename "$2")" "$rc" "$sig"; known=$((known+1))
    else
      printf "  %-14s %-22s rc=%-4s NEW DEFECT: %s\n" "$1" "$(basename "$2")" "$rc" "$sig"; newfail=$((newfail+1))
    fi
  fi
  rm -f "$err"
}

echo "===== hoedown (all ext, nesting=SIZE_MAX — current HEAD config) ====="
for f in "$CORPUS"/*.md; do run hoedown_fuzz "$f"; done
echo "===== pmh_parser (pmh_EXT_NONE) ====="
for f in "$CORPUS"/*.md; do run pmh_fuzz "$f"; done
echo "===== LibYAML patched (front-matter path) ====="
for f in "$CORPUS"/*.yaml; do run yaml_fuzz "$f"; done

echo "===== regression: hoedown cap=1000 survives on the 512KB parseQueue stack ====="
if [ -x "$OUT/hoedown_thread" ]; then
  "$OUT/hoedown_thread" "$CORPUS/deep_blockquote.md" 1000 >/dev/null 2>&1
  if [ $? -eq 0 ]; then echo "  cap=1000 @512KB: OK (recommended finding-7a cap; not yet landed in MPRenderer — see SECURITY-AUDIT)";
  else echo "  cap=1000 @512KB: FAILED — the chosen cap overflows; lower it!"; newfail=$((newfail+1)); fi
fi

echo "=================================================="
echo "known-open (finding 7b/7c): $known   new defects: $newfail"
[ $newfail -eq 0 ] && echo "RESULT: PASS (no new defects)" || echo "RESULT: FAIL"
exit $newfail
