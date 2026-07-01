#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# validate-handoff.sh — "Handoff schema" hard gate (design doc §15): validates
# every ./scratch/handoff/*.json file with `jq -e` (ajv-cli is listed as core in
# the design's prerequisites table, but isn't installed on this dev machine —
# jq is, and is sufficient for this minimal, originally-authored schema; the
# design gives no literal handoff-JSON schema to match, unlike the two hook
# templates. Swap to ajv-cli + a JSON-Schema file if a stricter contract is
# needed once Stage 5 defines what a handoff record actually carries).
#
# Minimal schema enforced: each file must be valid JSON and have non-empty
# string fields "task_id" and "status".
#
# Usage: scripts/validate-handoff.sh [dir]   (default: ./scratch/handoff)
# Exit:  0 all files valid (including zero files found) · 1 any file invalid
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

main() {
  local dir="${1:-./scratch/handoff}"
  local errors=0
  local file

  [[ -d "$dir" ]] || { echo "ok: $dir does not exist yet, nothing to validate"; exit 0; }

  shopt -s nullglob
  local files=("$dir"/*.json)
  shopt -u nullglob

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "ok: no handoff *.json files in $dir"
    exit 0
  fi

  for file in "${files[@]}"; do
    if ! jq -e '(.task_id | type == "string" and length > 0) and (.status | type == "string" and length > 0)' "$file" > /dev/null 2>&1; then
      echo "FAIL: $file — missing/invalid task_id or status" >&2
      errors=$((errors + 1))
    else
      echo "ok: $file"
    fi
  done

  [[ $errors -eq 0 ]] && exit 0 || exit 1
}

self_test() {
  local tmp fail
  tmp="$(mktemp -d)"
  fail=0

  bash "$0" "$tmp/does-not-exist" > /dev/null 2>&1 || { echo "FAIL: missing dir should exit 0"; fail=1; }

  bash "$0" "$tmp" > /dev/null 2>&1 || { echo "FAIL: empty dir should exit 0"; fail=1; }

  echo '{"task_id":"abc","status":"pending"}' > "$tmp/good.json"
  bash "$0" "$tmp" > /dev/null 2>&1 || { echo "FAIL: valid handoff file should exit 0"; fail=1; }

  echo '{"task_id":"abc"}' > "$tmp/bad.json"
  bash "$0" "$tmp" > /dev/null 2>&1 && { echo "FAIL: file missing 'status' should exit non-zero"; fail=1; } || true

  rm -rf "$tmp"
  if [[ $fail -eq 0 ]]; then echo "self-test: PASS"; exit 0; else echo "self-test: FAIL"; exit 1; fi
}

if [[ "${1:-}" == "--self-test" ]]; then self_test; else main "$@"; fi
