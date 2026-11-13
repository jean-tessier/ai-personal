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

# Check an item's optional dependencies.json: valid JSON, flat string array,
# every path resolves to a real skill/suite. Absent file is not an error.
check_dependencies_json() {
  local label="$1" dir="$2"
  local file="$dir/dependencies.json"
  [[ -f "$file" ]] || return 0

  if ! validate_json "$file"; then
    _fail "$label/dependencies.json — invalid JSON"
    return
  fi

  if ! command -v python3 &>/dev/null; then
    _warn "python3 not found; skipping dependencies.json shape/path checks: $label"
    return
  fi

  while IFS=$'\t' read -r shape_ok dep; do
    if [[ "$shape_ok" != "1" ]]; then
      _fail "$label/dependencies.json — must be a flat array of strings"
      return
    fi
    if [[ "$dep" == skills/* ]]; then
      if [[ -f "$REPO/$dep/SKILL.md" ]]; then _ok "$label/dependencies.json -> $dep"
      else _fail "$label/dependencies.json -> $dep — path does not resolve (missing SKILL.md)"; fi
    elif [[ "$dep" == suites/* ]]; then
      if [[ -f "$REPO/$dep/README.md" ]]; then _ok "$label/dependencies.json -> $dep"
      else _fail "$label/dependencies.json -> $dep — path does not resolve (missing README.md)"; fi
    else
      _fail "$label/dependencies.json -> $dep — unrecognized category (expected skills/ or suites/ prefix)"
    fi
  done < <(python3 - "$file" <<'PY'
import json, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

if isinstance(data, list) and all(isinstance(x, str) for x in data):
    for dep in data:
        print(f"1\t{dep}")
else:
    print("0\t")
PY
)
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

  check_dependencies_json "skills/$name" "$dir"
done < <(find "$REPO/skills" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
[[ $skill_count -eq 0 ]] && printf "  (no skills yet)\n"

# Validates a .claude-plugin/plugin.json at $1 (a plugin root — a suite root, or a
# suite's harness-variant subdirectory per ADR-0006), reporting under label $2.
# No-op if the manifest doesn't exist there — a plugin.json is optional per suite.
validate_plugin_manifest() {
  local plugin_dir="$1" label="$2"
  local manifest="$plugin_dir/.claude-plugin/plugin.json"
  [[ -f "$manifest" ]] || return 0
  if ! validate_json "$manifest"; then
    _fail "$label/.claude-plugin/plugin.json — invalid JSON"
    return
  fi
  if ! command -v python3 &>/dev/null; then
    _warn "python3 not found; skipping $label/.claude-plugin/plugin.json's 'name' field check"
    return
  fi
  if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
sys.exit(0 if isinstance(data.get('name'), str) and data['name'].strip() else 1)
" "$manifest" 2>/dev/null; then
    _ok "$label/.claude-plugin/plugin.json"
  else
    _fail "$label/.claude-plugin/plugin.json — missing or empty 'name' field"
  fi
}

# ── Suites ────────────────────────────────────────────────────────────────────
_head "suites"
suite_count=0
while IFS= read -r -d '' dir; do
  name="$(basename "$dir")"
  [[ "$name" == _* ]] && continue
  ((suite_count++)) || true
  if [[ -f "$dir/README.md" ]]; then _ok "suites/$name/README.md"
  else _fail "suites/$name/README.md — required file missing"; fi

  n=0
  while IFS= read -r -d '' f; do ((n++)) || true; done \
    < <(find "$dir" -mindepth 2 -name "*.md" -print0 2>/dev/null)
  if [[ $n -gt 0 ]]; then _ok "suites/$name/ ($n grouped prompt file(s))"
  else _fail "suites/$name/ — no grouped prompt files found in a component subdirectory"; fi

  check_dependencies_json "suites/$name" "$dir"

  validate_plugin_manifest "$dir" "suites/$name"
  # Multi-harness suites (ADR-0006) carry their plugin.json inside a harness-variant
  # subdirectory instead of the suite root — check those too, when present.
  for variant in claude-code copilot; do
    [[ -d "$dir/$variant" ]] && validate_plugin_manifest "$dir/$variant" "suites/$name/$variant"
  done
done < <(find "$REPO/suites" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
[[ $suite_count -eq 0 ]] && printf "  (no suites yet)\n"

# ── Marketplace ───────────────────────────────────────────────────────────────
_head "marketplace"
marketplace_file="$REPO/.claude-plugin/marketplace.json"
if [[ -f "$marketplace_file" ]]; then
  if validate_json "$marketplace_file"; then
    _ok ".claude-plugin/marketplace.json"
    if command -v python3 &>/dev/null; then
      # One pass over marketplace.json: a SUMMARY record (name/owner/plugins
      # presence) followed by one PLUGIN record per entry's source path —
      # avoids parsing the same small file twice for two unrelated checks.
      while IFS=$'\t' read -r kind a b; do
        case "$kind" in
          SUMMARY)
            IFS='|' read -r name_ok owner_ok plugins_ok <<< "$a"
            [[ "$name_ok" == "1" ]] && _ok "marketplace.name" || _fail "marketplace.name — missing or empty"
            [[ "$owner_ok" == "1" ]] && _ok "marketplace.owner" || _fail "marketplace.owner.name — missing or empty"
            [[ "$plugins_ok" == "1" ]] && _ok "marketplace.plugins (non-empty)" || _fail "marketplace.plugins — missing or empty array"
            ;;
          PLUGIN)
            if [[ -e "$REPO/${b#./}" ]]; then
              _ok "marketplace plugin '$a' source resolves ($b)"
            else
              _fail "marketplace plugin '$a' source does not exist: $b"
            fi
            ;;
        esac
      done < <(python3 - "$marketplace_file" <<'PY' | tr -d '\r'
import json, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

name_ok = 1 if isinstance(data.get("name"), str) and data["name"].strip() else 0
owner_ok = 1 if isinstance(data.get("owner"), dict) and data["owner"].get("name") else 0
plugins = data.get("plugins")
plugins_ok = 1 if isinstance(plugins, list) and plugins else 0
print(f"SUMMARY\t{name_ok}|{owner_ok}|{plugins_ok}\t-")

for p in plugins or []:
    src = p.get("source")
    if isinstance(src, str):
        print(f"PLUGIN\t{p.get('name', '?')}\t{src}")
PY
)
    else
      _warn "python3 not found; skipping marketplace structural checks"
    fi
  else
    _fail ".claude-plugin/marketplace.json — invalid JSON"
  fi
else
  _fail ".claude-plugin/marketplace.json — required file missing"
fi

# ── Harnesses ─────────────────────────────────────────────────────────────────
_head "harnesses"
harnesses_count=0
harnesses_file="$REPO/scripts/harnesses.json"
if [[ -f "$harnesses_file" ]]; then
  if validate_json "$harnesses_file"; then
    _ok "scripts/harnesses.json"
    if command -v python3 &>/dev/null; then
      while IFS=$'\t' read -r name label_ok scopes_n mapping_n; do
        ((harnesses_count++)) || true
        if [[ "$label_ok" == "1" ]]; then _ok "harnesses.$name.label"
        else _fail "harnesses.$name.label — missing or empty string"; fi

        if [[ "$scopes_n" -gt 0 ]]; then _ok "harnesses.$name.scopes ($scopes_n)"
        else _fail "harnesses.$name.scopes — missing or empty object"; fi

        if [[ "$mapping_n" -gt 0 ]]; then _ok "harnesses.$name.mapping ($mapping_n)"
        else _fail "harnesses.$name.mapping — missing or empty object"; fi
      done < <(python3 - "$harnesses_file" <<'PY' | tr -d '\r'
import json, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

for name, h in sorted(data.items()):
    label = h.get("label")
    label_ok = 1 if isinstance(label, str) and label.strip() else 0
    scopes = h.get("scopes")
    mapping = h.get("mapping")
    scopes_n = len(scopes) if isinstance(scopes, dict) else 0
    mapping_n = len(mapping) if isinstance(mapping, dict) else 0
    print(f"{name}\t{label_ok}\t{scopes_n}\t{mapping_n}")
PY
)
    else
      _warn "python3 not found; skipping per-harness structural checks"
    fi
  else
    _fail "scripts/harnesses.json — invalid JSON"
  fi
else
  _fail "scripts/harnesses.json — required file missing"
fi
[[ $harnesses_count -eq 0 ]] && printf "  (no harnesses yet)\n"

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n"
if [[ $ERRORS -eq 0 ]]; then
  printf "${GRN}${BLD}All checks passed.${NC}\n\n"
  exit 0
else
  printf "${RED}${BLD}%d check(s) failed.${NC}\n\n" "$ERRORS"
  exit 1
fi
