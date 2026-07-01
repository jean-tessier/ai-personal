#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# preview.sh — astgrep-rewrite SKILL.md step 1 (design doc §14): runs ast-grep's
# preview for a pattern→rewrite and writes the diff to
# ./scratch/handoff/<name>.diff, satisfying the PreToolUse hook's diff-artifact
# precondition (scripts/hook-block-apply-without-diff.sh, Stage 2) before any
# --update-all apply. Does not itself apply anything — step 2 ("Apply:
# sg ... --update-all") is a plain terminal command the hook already gates.
#
# Usage: scripts/preview.sh <pattern> <rewrite> <lang> <diff-name> [path...]
#   e.g.  scripts/preview.sh 'fetchUser($$$A)' 'getUser($$$A)' ts rename src
# Writes: ./scratch/handoff/<diff-name>.diff (or $SCRATCH_HANDOFF_DIR/<name>.diff)
# Exit:   0 preview written (even with zero matches — an empty preview is valid) ·
#         1 usage error or no ast-grep/sg binary found (fails closed — no
#           partial diff file is left behind)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

usage() { echo "Usage: $0 <pattern> <rewrite> <lang> <diff-name> [path...]" >&2; exit 1; }

sg_bin() {
  # ponytail: prefer the ast-grep binary name — util-linux's sg (set-group) can
  # shadow `sg` on Linux (design doc §6 warning).
  if command -v ast-grep >/dev/null 2>&1; then echo ast-grep; return 0; fi
  if command -v sg >/dev/null 2>&1 && sg --version 2>/dev/null | grep -qi ast-grep; then echo sg; return 0; fi
  return 1
}

main() {
  [[ $# -ge 4 ]] || usage
  local pattern="$1" rewrite="$2" lang="$3" name="$4"
  shift 4
  local bin
  bin="$(sg_bin)" || { echo "FAIL: no ast-grep binary found (checked 'ast-grep' and 'sg --version')" >&2; exit 1; }

  local dir="${SCRATCH_HANDOFF_DIR:-./scratch/handoff}"
  mkdir -p "$dir"
  "$bin" run --pattern "$pattern" --rewrite "$rewrite" --lang "$lang" "$@" > "$dir/$name.diff"
  echo "ok: preview written to $dir/$name.diff"
}

self_test() {
  local tmp stub fail
  tmp="$(mktemp -d)"
  fail=0

  # Stub ast-grep on PATH so this doesn't depend on real pattern matches.
  stub="$tmp/bin"
  mkdir -p "$stub"
  cat > "$stub/ast-grep" <<'STUB'
#!/usr/bin/env bash
echo "stub diff content"
STUB
  chmod +x "$stub/ast-grep"

  PATH="$stub:$PATH" SCRATCH_HANDOFF_DIR="$tmp/handoff" bash "$0" 'a' 'b' ts x
  if [[ ! -f "$tmp/handoff/x.diff" ]] || ! grep -q "stub diff content" "$tmp/handoff/x.diff"; then
    echo "FAIL: diff artifact should be written with the tool's output"; fail=1
  fi
  rm -rf "$tmp/handoff"

  # No ast-grep/sg anywhere on PATH → must fail closed, no diff file written.
  set +e
  PATH="/usr/bin:/bin" SCRATCH_HANDOFF_DIR="$tmp/handoff" bash "$0" 'a' 'b' ts x >/dev/null 2>&1
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    echo "FAIL: missing ast-grep/sg binary should exit non-zero"; fail=1
  fi
  if [[ -f "$tmp/handoff/x.diff" ]]; then
    echo "FAIL: no diff file should be written when the binary is missing"; fail=1
  fi

  rm -rf "$tmp"
  if [[ $fail -eq 0 ]]; then echo "self-test: PASS"; exit 0; else echo "self-test: FAIL"; exit 1; fi
}

if [[ "${1:-}" == "--self-test" ]]; then self_test; else main "$@"; fi
