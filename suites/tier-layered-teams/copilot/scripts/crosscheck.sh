#!/usr/bin/env bash
# Cross-check-two-ways HARD gate: two independent counts must match.
# Usage: crosscheck.sh <a> <b> [label]
# Exit 0 if equal, non-zero on mismatch — wire into a hook or CI.
set -euo pipefail
a=${1:?first value required}
b=${2:?second value required}
label=${3:-crosscheck}
if [ "$a" = "$b" ]; then
  echo "$label: OK ($a == $b)"
  exit 0
fi
echo "$label: MISMATCH ($a != $b) — do not trust this aggregate; investigate." >&2
exit 1
