#!/usr/bin/env bash
# ui-verify-due.sh — force-function for MASTER-PLAN §11.2 "every-5th-handoff" UI pass.
# Reads the last ledger row's "handoffs since last UI verify" counter (rightmost column of
# §11.3) and shouts if the human GUI verification is due, so it can't be silently skipped.
# Read-only; safe to run anytime. Run at session start AND before composing a handoff.
set -euo pipefail
PLAN="$(cd "$(dirname "$0")/.." && pwd)/docs/MASTER-PLAN.md"
[ -f "$PLAN" ] || { echo "ui-verify-due: MASTER-PLAN.md not found at $PLAN" >&2; exit 2; }

# Latest data row = the row with the HIGHEST leading row-number — NOT the physically-last
# line. Rows have been appended out of order before (1,2,3,4,8,7,6,5), which silently fooled
# the old `tail -1` into reading the reset row (counter 0) and falsely reporting "not due".
# Sort by the first numeric column and take the max so physical order can't break the gate.
# (Hardened 2026-06-30 after the out-of-order ledger bug — see §9 LUT.)
row="$(grep -E '^\| *[0-9]+ *\| *2[0-9]{3}-' "$PLAN" | sort -t'|' -k2 -n | tail -1)"
counter="$(printf '%s' "$row" | awk -F'|' '{gsub(/ /,"",$(NF-1)); print $(NF-1)}')"

case "$counter" in
  ''|*[!0-9]*) echo "ui-verify-due: could not parse counter from ledger (last row: $row)"; exit 2;;
esac

# Cadence: the session that STARTS with counter=4 IS handoff #5 (it does the pass and
# resets to 0 when it writes its row). So counter==4 means DUE THIS SESSION, not "next".
# counter>=5 means a prior #5 session skipped the pass -> OVERDUE. (Fixed off-by-one 2026-06-30.)
if   [ "$counter" -ge 5 ]; then
  echo "🚨🚨 UI VERIFICATION IS OVERDUE (counter=$counter ≥ 5 — a handoff #5 skipped it)."
  echo "    Run docs/TEST-MATRIX.md §3 against a fresh Debug build NOW, before handing off,"
  echo "    set the ledger 'UI-verified?' = YES, and reset the counter to 0. (§11.2)"
  exit 1
elif [ "$counter" -eq 4 ]; then
  echo "🚨 UI VERIFICATION PASS IS DUE THIS SESSION (counter=4 → you are handoff #5)."
  echo "    Run docs/TEST-MATRIX.md §3 against a fresh Debug build BEFORE handing off,"
  echo "    set the ledger 'UI-verified?' = YES, and reset the counter to 0. (§11.2)"
  exit 1
elif [ "$counter" -eq 3 ]; then
  echo "⚠️  Heads-up: UI pass due NEXT session (counter=3 → next handoff is #5). (§11.2)"
  exit 0
else
  echo "✅ UI pass not yet due (counter=$counter; mandatory when it reaches 4). (§11.2)"
  exit 0
fi
