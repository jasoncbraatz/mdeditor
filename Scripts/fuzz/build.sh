#!/bin/bash
# build.sh — compile the mdeditor parser fuzz harnesses under ASan + UBSan.
# Builds against the in-tree parser sources (no app build needed). Outputs to
# Scripts/fuzz/build/. Pass --cve-control to also build the guard-removed LibYAML
# control that proves the harness catches CVE-2014-2525.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUT="$HERE/build"
mkdir -p "$OUT"
SAN=(-fsanitize=address,undefined -fno-sanitize-recover=all -g -O1 -fno-omit-frame-pointer)

echo "[build] hoedown (ASan/UBSan)"
clang "${SAN[@]}" -I"$REPO/Pods/hoedown/src" \
  "$HERE/hoedown_harness.c" "$REPO"/Pods/hoedown/src/*.c -o "$OUT/hoedown_fuzz"

echo "[build] hoedown thread-stack threshold finder (plain -O0, 512KB stack)"
clang -O0 -g -I"$REPO/Pods/hoedown/src" \
  "$HERE/hoedown_thread.c" "$REPO"/Pods/hoedown/src/*.c -o "$OUT/hoedown_thread"

echo "[build] pmh_parser (ASan/UBSan)"
clang "${SAN[@]}" -I"$REPO/Dependency/peg-markdown-highlight" \
  "$HERE/pmh_harness.c" "$REPO/Dependency/peg-markdown-highlight/pmh_parser.c" -o "$OUT/pmh_fuzz"

echo "[build] LibYAML patched (ASan/UBSan)"
clang "${SAN[@]}" -DHAVE_CONFIG_H \
  -I"$REPO/Pods/LibYAML" -I"$REPO/Pods/LibYAML/include" -I"$REPO/Pods/LibYAML/src" \
  "$HERE/yaml_harness.c" "$REPO"/Pods/LibYAML/src/*.c -o "$OUT/yaml_fuzz"

if [ "${1:-}" = "--cve-control" ]; then
  echo "[build] LibYAML CVE-2014-2525 CONTROL (guard removed — must crash on the PoC)"
  TMP="$OUT/libyaml_unpatched"; rm -rf "$TMP"; mkdir -p "$TMP"
  cp -R "$REPO"/Pods/LibYAML/* "$TMP/"
  grep -v "SECURITY (CVE-2014-2525)" "$TMP/src/scanner.c" \
    | grep -v "STRING_EXTEND(parser, \*string)) return 0;" > "$TMP/scanner.tmp"
  mv "$TMP/scanner.tmp" "$TMP/src/scanner.c"
  clang "${SAN[@]}" -DHAVE_CONFIG_H \
    -I"$TMP" -I"$TMP/include" -I"$TMP/src" \
    "$HERE/yaml_harness.c" "$TMP"/src/*.c -o "$OUT/yaml_fuzz_unpatched"
fi

echo "[build] done -> $OUT"
