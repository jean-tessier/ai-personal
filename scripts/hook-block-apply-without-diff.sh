#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# hook-block-apply-without-diff.sh — PreToolUse implementation for
# .github/hooks/block-apply-without-diff.json (design doc §11/§15: "Diff before apply").
#
# VS Code's real hooks schema ignores the JSON "matcher" field — PreToolUse fires on
# EVERY tool call regardless (code.visualstudio.com/docs/agent-customization/hooks,
# checked 2026-06-30). So this script does its own filtering: only a terminal command
# matching the apply-style pattern is gated; everything else is a silent allow.
#
# stdin:  hook input JSON, e.g. {"tool_input":{"command":"sg ... --update-all"}}
# stdout: {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"|"deny",...}}
# exit:   0 allow · 2 deny (PreToolUse convention: non-zero-other-than-2 fails closed too,
#         so 2 is used deliberately to match the documented "deny" exit code)
#
# ponytail: schema nesting (hookSpecificOutput.*) matches VS Code's own docs + the
# vscode-copilot-chat extension repo; a second official doc (github.com Copilot hooks
# reference) shows permissionDecision un-nested. Preview feature, docs disagree — see
# handoff Open Items. Adjust here if live testing shows otherwise.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

APPLY_PATTERN='(--update-all|--apply|comby -i)'
HANDOFF_DIR="${SCRATCH_HANDOFF_DIR:-./scratch/handoff}"

decide() {
  local command="$1"

  if [[ ! "$command" =~ $APPLY_PATTERN ]]; then
    printf '{}'
    return 0
  fi

  shopt -s nullglob
  local diffs=("$HANDOFF_DIR"/*.diff)
  shopt -u nullglob

  if [[ ${#diffs[@]} -gt 0 ]]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    return 0
  fi

  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"apply-style command with no diff artifact at %s/*.diff"}}' "$HANDOFF_DIR"
  return 2
}

main() {
  local input command
  input="$(cat)"
  command="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  decide "$command"
}

self_test() {
  local tmp fail out rc
  tmp="$(mktemp -d)"
  fail=0

  out="$(printf '{"tool_input":{"command":"rg foo"}}' | SCRATCH_HANDOFF_DIR="$tmp" bash "$0")"
  rc=$?
  if [[ $rc -ne 0 || "$out" != "{}" ]]; then
    echo "FAIL: non-apply command should allow silently (rc=$rc out=$out)"; fail=1
  fi

  set +e
  out="$(printf '{"tool_input":{"command":"sg -r foo --update-all"}}' | SCRATCH_HANDOFF_DIR="$tmp" bash "$0")"
  rc=$?
  set -e
  if [[ $rc -ne 2 ]] || [[ "$out" != *'"deny"'* ]]; then
    echo "FAIL: apply command with no diff present should deny, exit 2 (rc=$rc out=$out)"; fail=1
  fi

  mkdir -p "$tmp"
  : > "$tmp/rename.diff"
  out="$(printf '{"tool_input":{"command":"sg -r foo --update-all"}}' | SCRATCH_HANDOFF_DIR="$tmp" bash "$0")"
  rc=$?
  if [[ $rc -ne 0 ]] || [[ "$out" != *'"allow"'* ]]; then
    echo "FAIL: apply command with diff present should allow, exit 0 (rc=$rc out=$out)"; fail=1
  fi

  rm -rf "$tmp"
  if [[ $fail -eq 0 ]]; then echo "self-test: PASS"; exit 0; else echo "self-test: FAIL"; exit 1; fi
}

if [[ "${1:-}" == "--self-test" ]]; then self_test; else main; fi
