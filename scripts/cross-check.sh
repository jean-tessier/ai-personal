#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# cross-check.sh — "cross-check-two-ways" hard gate (design doc §15): asserts two
# independently-computed counts agree; exits non-zero on mismatch so a Surveyor
# aggregate/count is never reported without a second, independent computation.
# Usage: scripts/cross-check.sh <count_a> <count_b>
# Exit:  0 counts match · 1 counts differ or an input isn't an integer
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

usage() { echo "Usage: $0 <count_a> <count_b>" >&2; exit 1; }

main() {
  [[ $# -eq 2 ]] || usage
  local a="$1" b="$2"
  [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ ]] || { echo "FAIL: both arguments must be non-negative integers (got '$a' '$b')" >&2; exit 1; }
  if [[ "$a" -eq "$b" ]]; then
    echo "ok: counts agree ($a)"
    exit 0
  else
    echo "FAIL: counts disagree ($a != $b)" >&2
    exit 1
  fi
}

self_test() {
  local fail=0
  bash "$0" 5 5 >/dev/null 2>&1 || { echo "FAIL: equal counts should exit 0"; fail=1; }
  bash "$0" 5 6 >/dev/null 2>&1 && { echo "FAIL: unequal counts should exit non-zero"; fail=1; } || true
  bash "$0" foo 5 >/dev/null 2>&1 && { echo "FAIL: non-integer input should exit non-zero"; fail=1; } || true
  if [[ $fail -eq 0 ]]; then echo "self-test: PASS"; exit 0; else echo "self-test: FAIL"; exit 1; fi
}

if [[ "${1:-}" == "--self-test" ]]; then self_test; else main "$@"; fi
