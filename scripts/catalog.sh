#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# catalog.sh — Emit a JSON index of all named assets to stdout.
# Usage:  bash scripts/catalog.sh
#         bash scripts/catalog.sh > catalog.json
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# ── Helpers ───────────────────────────────────────────────────────────────────
has_file() { [[ -f "$1" ]] && echo "true" || echo "false"; }
has_dir()  { [[ -d "$1" ]] && echo "true" || echo "false"; }
quote()    { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Extract first non-empty value of a YAML frontmatter key
yaml_val() {
  local file="$1" key="$2"
  sed -n "/^---/,/^---/p" "$file" 2>/dev/null \
    | grep "^${key}:" \
    | head -1 \
    | sed "s/^${key}:[[:space:]]*//" \
    | sed "s/['\"]//g"
}

# ── Skills ────────────────────────────────────────────────────────────────────
skills_json=""
while IFS= read -r -d '' dir; do
  name="$(basename "$dir")"
  [[ "$name" == _* ]] && continue
  desc=""
  [[ -f "$dir/SKILL.md" ]] && desc="$(yaml_val "$dir/SKILL.md" description)"
  entry="$(printf '{"name":"%s","path":"skills/%s","description":"%s","hasChangelog":%s,"hasExamples":%s}' \
    "$(quote "$name")" "$(quote "$name")" "$(quote "$desc")" \
    "$(has_file "$dir/CHANGELOG.md")" "$(has_dir "$dir/examples")")"
  skills_json="${skills_json:+$skills_json,}$entry"
done < <(find "$REPO/skills" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

# ── Agents ────────────────────────────────────────────────────────────────────
agents_json=""
while IFS= read -r -d '' dir; do
  name="$(basename "$dir")"
  [[ "$name" == _* || "$name" == "README.md" ]] && continue
  entry="$(printf '{"name":"%s","path":"prompts/agents/%s","hasSystem":%s,"hasChangelog":%s,"hasExamples":%s}' \
    "$(quote "$name")" "$(quote "$name")" \
    "$(has_file "$dir/system.md")" "$(has_file "$dir/CHANGELOG.md")" "$(has_dir "$dir/examples")")"
  agents_json="${agents_json:+$agents_json,}$entry"
done < <(find "$REPO/prompts/agents" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

# ── Workflows ─────────────────────────────────────────────────────────────────
workflows_json=""
while IFS= read -r -d '' dir; do
  name="$(basename "$dir")"
  [[ "$name" == _* ]] && continue
  files_json=""
  while IFS= read -r -d '' f; do
    rel="${f#"$dir"/}"
    files_json="${files_json:+$files_json,}\"$(quote "$rel")\""
  done < <(find "$dir" -mindepth 2 -name "*.md" -print0 2>/dev/null | sort -z)
  entry="$(printf '{"name":"%s","path":"workflows/%s","hasReadme":%s,"files":[%s]}' \
    "$(quote "$name")" "$(quote "$name")" "$(has_file "$dir/README.md")" "$files_json")"
  workflows_json="${workflows_json:+$workflows_json,}$entry"
done < <(find "$REPO/workflows" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

# ── Tasks ─────────────────────────────────────────────────────────────────────
tasks_json=""
while IFS= read -r -d '' file; do
  name="$(basename "$file")"
  [[ "$name" == "README.md" ]] && continue
  desc="$(yaml_val "$file" description)"
  entry="$(printf '{"name":"%s","path":"prompts/tasks/%s","description":"%s"}' \
    "$(quote "$name")" "$(quote "$name")" "$(quote "$desc")")"
  tasks_json="${tasks_json:+$tasks_json,}$entry"
done < <(find "$REPO/prompts/tasks" -mindepth 1 -maxdepth 1 -name "*.md" ! -name "README.md" -print0 2>/dev/null | sort -z)

# ── MCP servers ───────────────────────────────────────────────────────────────
mcp_json=""
while IFS= read -r -d '' dir; do
  name="$(basename "$dir")"
  entry="$(printf '{"name":"%s","path":"tools/mcp/%s","hasManifest":%s}' \
    "$(quote "$name")" "$(quote "$name")" "$(has_file "$dir/manifest.json")")"
  mcp_json="${mcp_json:+$mcp_json,}$entry"
done < <(find "$REPO/tools/mcp" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

# ── Emit ──────────────────────────────────────────────────────────────────────
cat <<JSON
{
  "generated": "$timestamp",
  "assets": {
    "skills": [$skills_json],
    "agents": [$agents_json],
    "workflows": [$workflows_json],
    "tasks":  [$tasks_json],
    "tools": {
      "mcp": [$mcp_json]
    }
  }
}
JSON
