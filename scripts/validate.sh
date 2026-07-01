#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# validate.sh — Structural linter for ai-personal.
# Checks required files exist and JSON files are valid.
# Usage:  bash scripts/validate.sh
# Exit:   0 all checks pass · 1 one or more checks failed
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ERRORS=0

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; BLD='\033[1m'; NC='\033[0m'
_ok()   { printf "${GRN}    ok${NC}  %s\n" "$1"; }
_fail() { printf "${RED}  FAIL${NC}  %s\n" "$1"; ((ERRORS++)) || true; }
_warn() { printf "${YLW}  warn${NC}  %s\n" "$1"; }
_head() { printf "\n${BLD}── %s ──${NC}\n" "$1"; }

validate_json() {
  local file="$1"
  if command -v python3 &>/dev/null; then
    python3 -m json.tool "$file" > /dev/null 2>&1 && return 0 || return 1
  elif command -v jq &>/dev/null; then
    jq . "$file" > /dev/null 2>&1 && return 0 || return 1
  else
    _warn "No JSON validator found (install python3 or jq); skipping: $1"
    return 0
  fi
}

# ── Skills ────────────────────────────────────────────────────────────────────
_head "skills"
skill_count=0
while IFS= read -r -d '' dir; do
  name="$(basename "$dir")"
  [[ "$name" == _* ]] && continue
  ((skill_count++)) || true
  if [[ -f "$dir/SKILL.md" ]]; then _ok "skills/$name/SKILL.md"
  else _fail "skills/$name/SKILL.md — required file missing"; fi

  if [[ -f "$dir/CHANGELOG.md" ]]; then _ok "skills/$name/CHANGELOG.md"
  else _warn "skills/$name/CHANGELOG.md — no version log yet"; fi
done < <(find "$REPO/skills" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
[[ $skill_count -eq 0 ]] && printf "  (no skills yet)\n"

# ── Agents ────────────────────────────────────────────────────────────────────
_head "prompts/agents"
agent_count=0
while IFS= read -r -d '' dir; do
  name="$(basename "$dir")"
  [[ "$name" == _* ]] && continue
  ((agent_count++)) || true
  if [[ -f "$dir/system.md" ]]; then _ok "prompts/agents/$name/system.md"
  else _fail "prompts/agents/$name/system.md — required file missing"; fi

  if [[ -f "$dir/CHANGELOG.md" ]]; then _ok "prompts/agents/$name/CHANGELOG.md"
  else _warn "prompts/agents/$name/CHANGELOG.md — no version log yet"; fi
done < <(find "$REPO/prompts/agents" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
[[ $agent_count -eq 0 ]] && printf "  (no agents yet)\n"

# ── Workflows ─────────────────────────────────────────────────────────────────
_head "workflows"
workflow_count=0
while IFS= read -r -d '' dir; do
  name="$(basename "$dir")"
  [[ "$name" == _* ]] && continue
  ((workflow_count++)) || true
  if [[ -f "$dir/README.md" ]]; then _ok "workflows/$name/README.md"
  else _fail "workflows/$name/README.md — required file missing"; fi

  n=0
  while IFS= read -r -d '' f; do ((n++)) || true; done \
    < <(find "$dir" -mindepth 2 -name "*.md" -print0 2>/dev/null)
  if [[ $n -gt 0 ]]; then _ok "workflows/$name/ ($n grouped prompt file(s))"
  else _fail "workflows/$name/ — no grouped prompt files found in a component subdirectory"; fi
done < <(find "$REPO/workflows" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
[[ $workflow_count -eq 0 ]] && printf "  (no workflows yet)\n"

# ── MCP manifests ─────────────────────────────────────────────────────────────
_head "tools/mcp"
mcp_count=0
while IFS= read -r -d '' dir; do
  name="$(basename "$dir")"
  ((mcp_count++)) || true
  if [[ -f "$dir/manifest.json" ]]; then
    if validate_json "$dir/manifest.json"; then _ok "tools/mcp/$name/manifest.json"
    else _fail "tools/mcp/$name/manifest.json — invalid JSON"; fi
  else
    _fail "tools/mcp/$name/manifest.json — required file missing"
  fi
done < <(find "$REPO/tools/mcp" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
[[ $mcp_count -eq 0 ]] && printf "  (no MCP servers yet)\n"

# ── Function schemas ──────────────────────────────────────────────────────────
_head "tools/functions"
fn_count=0
while IFS= read -r -d '' file; do
  rel="${file#"$REPO"/}"
  ((fn_count++)) || true
  if validate_json "$file"; then _ok "$rel"
  else _fail "$rel — invalid JSON"; fi
done < <(find "$REPO/tools/functions" -name "*.json" -print0 2>/dev/null | sort -z)
[[ $fn_count -eq 0 ]] && printf "  (no function schemas yet)\n"

# ── Eval / prompt alignment ───────────────────────────────────────────────────
_head "evals alignment"
while IFS= read -r -d '' dir; do
  name="$(basename "$dir")"
  [[ "$name" == _* ]] && continue
  eval_dir="$REPO/evals/agents/$name"
  if [[ -d "$eval_dir" ]]; then _ok "evals/agents/$name/ exists"
  else _warn "prompts/agents/$name has no eval suite at evals/agents/$name/"; fi
done < <(find "$REPO/prompts/agents" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

while IFS= read -r -d '' dir; do
  name="$(basename "$dir")"
  [[ "$name" == _* ]] && continue
  eval_dir="$REPO/evals/skills/$name"
  if [[ -d "$eval_dir" ]]; then _ok "evals/skills/$name/ exists"
  else _warn "skills/$name has no eval suite at evals/skills/$name/"; fi
done < <(find "$REPO/skills" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n"
if [[ $ERRORS -eq 0 ]]; then
  printf "${GRN}${BLD}All checks passed.${NC}\n\n"
  exit 0
else
  printf "${RED}${BLD}%d check(s) failed.${NC}\n\n" "$ERRORS"
  exit 1
fi
