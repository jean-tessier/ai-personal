#!/usr/bin/env bash
# Produce the preview diff that the PreToolUse "no-apply-without-diff" hook requires.
# Usage: preview-rewrite.sh '<pattern>' '<rewrite>' <lang> [path]
# Writes ./scratch/handoff/pending.diff (single canonical file) and prints it.
set -euo pipefail

pattern=${1:?pattern required}
rewrite=${2:?rewrite required}
lang=${3:?lang required}
path=${4:-.}

handoff=./scratch/handoff
mkdir -p "$handoff"
rm -f "$handoff"/*.diff   # clear stale diffs so the gate can never pass on an old one

bin=ast-grep
command -v ast-grep >/dev/null 2>&1 || bin=sg   # fall back only if `sg` is aliased to ast-grep

# Without --update-all, ast-grep prints the change as a preview instead of applying it.
"$bin" -p "$pattern" -r "$rewrite" --lang "$lang" --color never "$path" > "$handoff/pending.diff" || true

if [ ! -s "$handoff/pending.diff" ]; then
  echo "preview-rewrite: no matches — nothing to apply." >&2
  rm -f "$handoff/pending.diff"
  exit 2
fi

echo "Preview written to $handoff/pending.diff:"
cat "$handoff/pending.diff"
