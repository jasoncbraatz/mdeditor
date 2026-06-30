#!/usr/bin/env bash
# ui-verify-due.sh — force-function for MASTER-PLAN §11.2 "every-5th-handoff" UI pass.
# Reads the last ledger row's "handoffs since last UI verify" counter (rightmost column of
# §11.3) and shouts if the human GUI verification is due, so it can't be silently skipped.
# Read-only; safe to run anytime. Run at session start AND before composing a handoff.
set -euo pipefail
PLAN="$(cd "$(dirname "$0")/.." && pwd)/docs/MASTER-PLAN.md"
[ -f "$PLAN" ] || { echo "ui-verify-due: MASTER-PLAN.md not found at $PLAN" >&2; exit 2; }

# Last data row of the ledger = last line matching "| <int> | <date> | ...". Take the final
# numeric table cell as the counter.
row="$(grep -E '^\| *[0-9]+ *\| *2[0-9]{3}-' "$PLAN" | tail -1)"
counter="$(printf '%s' "$row" | awk -F'|' '{gsub(/ /,"",$(NF-1)); print $(NF-1)}')"

case "$counter" in
  ''|*[!0-9]*) echo "ui-verify-due: could not parse counter from ledger (last row: $row)"; exit 2;;
esac

if   [ "$counter" -ge 5 ]; then
  echo "🚨🚨 UI VERIFICATION PASS IS DUE NOW (counter=$counter ≥ 5)."
  echo "    Run docs/TEST-MATRIX.md §3 against a fresh Debug build BEFORE handing off,"
  echo "    set the ledger 'UI-verified?' = YES, and reset the counter to 0. (§11.2)"
  exit 1
elif [ "$counter" -eq 4 ]; then
  echo "⚠️  UI pass due NEXT session (counter=4 → becomes 5). Plan to run it then. (§11.2)"
  exit 0
else
  echo "✅ UI pass not yet due (counter=$counter; mandatory at 5). (§11.2)"
  exit 0
fi
