#!/usr/bin/env bash
# Output-size cap HARD gate. Runs a command; if stdout exceeds the line budget it
# prints the head + a directive to escalate to Tier 2 and exits non-zero, so a raw
# dump can never silently flood context.
# Usage: size-cap.sh <max_lines> -- <command> [args...]
set -uo pipefail
max=${1:?max_lines required}; shift
[ "${1:-}" = "--" ] && shift
out=$("$@"); rc=$?
if [ "$rc" -ne 0 ]; then
  printf '%s\n' "$out" >&2
  exit "$rc"
fi
n=$(printf '%s\n' "$out" | wc -l)
if [ "$n" -le "$max" ]; then
  printf '%s\n' "$out"
  exit 0
fi
printf '%s\n' "$out" | head -n "$max"
echo "--- OUTPUT CAPPED at $max lines ($n total) ---" >&2
echo "Escalate to Tier 2 (scratch-script): aggregate this instead of reading it raw." >&2
exit 1
