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

# A suite is "plugin-shaped" when it carries a .claude-plugin/plugin.json at its own
# root (not in a harness-variant subdir — see suites/tier-layered-teams's claude-code/
# and copilot/ split, which is out of scope for this flag). Emits its declared
# `dependencies` array (plugin/skill names this suite requires), or [] if none/absent.
# python3 is optional here (unlike install.sh, where it's required) — degrade to an
# empty array rather than fail, so catalog.sh keeps its no-hard-dependency posture.
plugin_manifest() { printf '%s' "$1/.claude-plugin/plugin.json"; }

is_plugin_shaped() { has_file "$(plugin_manifest "$1")"; }

# ponytail: this function's result is spliced into a printf argument by its
# caller, not assigned standalone — a failure inside a nested command
# substitution used as another command's argument does NOT trip the caller's
# `set -e` (only the outer printf's own exit status would, and printf always
# succeeds regardless of what its string arguments contain). So this function
# must guarantee valid-JSON output *itself*, on every path, rather than
# relying on the caller to catch a failure it structurally can't see.
plugin_deps_json() {
  local manifest out
  manifest="$(plugin_manifest "$1")"
  if [[ ! -f "$manifest" ]] || ! command -v python3 &>/dev/null; then
    printf '[]'
    return
  fi
  if ! out="$(python3 - "$manifest" 2>/dev/null <<'PY' | tr -d '\r'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
deps = data.get("dependencies", [])
names = [d if isinstance(d, str) else d.get("name") for d in deps]
print(json.dumps([n for n in names if n]))
PY
)"; then
    printf '[]'
    return
  fi
  printf '%s' "${out:-[]}"
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
    "$(is_plugin_shaped "$dir")" "$(plugin_deps_json "$dir")")"
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
