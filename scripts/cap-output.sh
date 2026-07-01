#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# cap-output.sh — "Output-size cap" hard gate (design doc §15): runs a command,
# and if its stdout exceeds N lines, truncates it and aborts non-zero — forcing
# escalation (e.g. to a T1/T2 tool or a subagent) instead of a huge read
# silently entering context.
#
# Usage: scripts/cap-output.sh <max-lines> -- <command> [args...]
# Exit:  0 command ran and stayed within the cap (its own exit code is passed through)
#        1 output exceeded the cap (command's own exit code is discarded — the
#          volume itself is the failure)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

usage() { echo "Usage: $0 <max-lines> -- <command> [args...]" >&2; exit 1; }

main() {
  [[ $# -ge 3 && "$2" == "--" ]] || usage
  local max="$1"
  [[ "$max" =~ ^[0-9]+$ ]] || usage
  shift 2

  local out lines rc
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  lines="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"

  if [[ "$lines" -gt "$max" ]]; then
    printf '%s\n' "$out" | head -n "$max"
    echo "..."
    echo "FAIL: output truncated at $max lines (had $lines) — escalate to a bounded tool/subagent instead" >&2
    exit 1
  fi

  printf '%s\n' "$out"
  exit "$rc"
}

self_test() {
  local fail=0
  bash "$0" 3 -- seq 1 3 > /dev/null 2>&1 || { echo "FAIL: output at the cap should pass"; fail=1; }
  bash "$0" 3 -- seq 1 10 > /dev/null 2>&1 && { echo "FAIL: output over the cap should fail"; fail=1; } || true
  bash "$0" 3 -- false > /dev/null 2>&1 && { echo "FAIL: underlying command's non-zero exit should pass through as non-zero"; fail=1; } || true
  if [[ $fail -eq 0 ]]; then echo "self-test: PASS"; exit 0; else echo "self-test: FAIL"; exit 1; fi
}

if [[ "${1:-}" == "--self-test" ]]; then self_test; else main "$@"; fi
