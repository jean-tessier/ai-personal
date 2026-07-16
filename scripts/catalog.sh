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

# Splice an item's optional dependencies.json verbatim, else "[]".
read_dependencies_json() {
  local dir="$1"
  [[ -s "$dir/dependencies.json" ]] && cat "$dir/dependencies.json" || printf '[]'
}

# Extract first non-empty value of a YAML frontmatter key
yaml_val() {
  local file="$1" key="$2"
  sed -n "/^---/,/^---/p" "$file" 2>/dev/null \
    | grep "^${key}:" \
    | head -1 \
    | sed "s/^${key}:[[:space:]]*//" \
    | sed "s/['\"]//g"
}

# A suite is "plugin-shaped" when it carries a .claude-plugin/plugin.json at its own
# root (not in a harness-variant subdir — see suites/tier-layered-teams's claude-code/
# and copilot/ split, which is out of scope for this flag). Drives install.sh's
# Copilot-translation eligibility; dependencies are read from the colocated
# dependencies.json instead (see read_dependencies_json / ADR-0009).
plugin_manifest() { printf '%s' "$1/.claude-plugin/plugin.json"; }

is_plugin_shaped() { has_file "$(plugin_manifest "$1")"; }

# ── Skills ────────────────────────────────────────────────────────────────────
skills_json=""
while IFS= read -r -d '' dir; do
  name="$(basename "$dir")"
  [[ "$name" == _* ]] && continue
  desc=""
  [[ -f "$dir/SKILL.md" ]] && desc="$(yaml_val "$dir/SKILL.md" description)"
  entry="$(printf '{"name":"%s","path":"skills/%s","description":"%s","hasChangelog":%s,"hasExamples":%s,"dependencies":%s}' \
    "$(quote "$name")" "$(quote "$name")" "$(quote "$desc")" \
    "$(has_file "$dir/CHANGELOG.md")" "$(has_dir "$dir/examples")" \
    "$(read_dependencies_json "$dir")")"
  skills_json="${skills_json:+$skills_json,}$entry"
done < <(find "$REPO/skills" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

# ── Suites ────────────────────────────────────────────────────────────────────
suites_json=""
while IFS= read -r -d '' dir; do
  name="$(basename "$dir")"
  [[ "$name" == _* ]] && continue
  files_json=""
  while IFS= read -r -d '' f; do
    rel="${f#"$dir"/}"
    files_json="${files_json:+$files_json,}\"$(quote "$rel")\""
  done < <(find "$dir" -mindepth 2 -name "*.md" -print0 2>/dev/null | sort -z)
  entry="$(printf '{"name":"%s","path":"suites/%s","hasReadme":%s,"files":[%s],"pluginShaped":%s,"dependencies":%s}' \
    "$(quote "$name")" "$(quote "$name")" "$(has_file "$dir/README.md")" "$files_json" \
    "$(is_plugin_shaped "$dir")" "$(read_dependencies_json "$dir")")"
  suites_json="${suites_json:+$suites_json,}$entry"
done < <(find "$REPO/suites" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

# ── Emit ──────────────────────────────────────────────────────────────────────
cat <<JSON
{
  "generated": "$timestamp",
  "assets": {
    "skills": [$skills_json],
    "suites": [$suites_json]
  }
}
JSON
