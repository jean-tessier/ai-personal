#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# test-install.sh — Behavioral tests for install.sh.
#
# Each test runs install.sh against a throwaway sandbox (isolated CWD + HOME)
# built under mktemp -d, so nothing touches the real repo or the real home
# directory — every sandbox is deleted on exit, pass or fail. Uses install.sh's
# undocumented test seams (--local, INSTALL_FORCE_INTERACTIVE); see
# docs/memory/vendor-agnostic-installer.md. Does not exercise the real
# curl/tar network fetch — see that doc for the manual recipe for that.
#
# For full container isolation instead of local mktemp sandboxes, use
# scripts/test-install-docker.sh.
#
# Usage:  bash scripts/test-install.sh
# Exit:   0 all tests pass · 1 one or more tests failed
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$REPO/install.sh"

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; BLD='\033[1m'; NC='\033[0m'
PASS=0; FAIL=0; SKIP=0
_ok()   { printf "${GRN}    ok${NC}  %s\n" "$1"; ((PASS++)) || true; }
_fail() { printf "${RED}  FAIL${NC}  %s\n" "$1"; ((FAIL++)) || true; }
_skip() { printf "${YLW}  skip${NC}  %s\n" "$1"; ((SKIP++)) || true; }
_head() { printf "\n${BLD}── %s ──${NC}\n" "$1"; }

# Resolved once, outside any sandbox. Tests below override $HOME to isolate
# the "user" scope target, which breaks version-manager shims (asdf/mise/
# pyenv) that resolve their real interpreter via $HOME/.tool-versions.
# Symlinking the real interpreter into each sandbox's own bin/ sidesteps that.
REAL_PYTHON3="$(python3 -c 'import sys; print(sys.executable)' 2>/dev/null)"
[[ -z "$REAL_PYTHON3" ]] && REAL_PYTHON3="$(command -v python3)"

SANDBOXES=()
cleanup() {
  local d
  if [[ ${#SANDBOXES[@]} -gt 0 ]]; then
    for d in "${SANDBOXES[@]}"; do rm -rf "$d"; done
  fi
}
trap cleanup EXIT

new_sandbox() {
  local d
  d="$(mktemp -d)"
  mkdir -p "$d/cwd" "$d/home" "$d/bin"
  ln -s "$REAL_PYTHON3" "$d/bin/python3"
  SANDBOXES+=("$d")
  printf '%s' "$d"
}

# Runs install.sh against this checkout (--local, never the real network)
# with an isolated PWD/HOME so the real repo and real $HOME are never touched.
run_install() {
  local sandbox="$1"; shift
  ( cd "$sandbox/cwd" && HOME="$sandbox/home" PATH="$sandbox/bin:$PATH" \
      bash "$INSTALL" --local "$REPO" "$@" )
}

assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  [[ "$actual" == "$expected" ]] && _ok "$desc" || _fail "$desc (expected exit $expected, got $actual)"
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  [[ "$haystack" == *"$needle"* ]] && _ok "$desc" || _fail "$desc (missing: $needle)"
}

assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  [[ "$haystack" != *"$needle"* ]] && _ok "$desc" || _fail "$desc (unexpectedly found: $needle)"
}

assert_exists() {
  local desc="$1" path="$2"
  [[ -e "$path" ]] && _ok "$desc" || _fail "$desc (missing: $path)"
}

assert_missing() {
  local desc="$1" path="$2"
  [[ ! -e "$path" ]] && _ok "$desc" || _fail "$desc (should not exist: $path)"
}

# ── scenarios ─────────────────────────────────────────────────────────────────

test_dry_run_writes_nothing() {
  _head "dry-run writes nothing"
  local sb out code
  sb="$(new_sandbox)"
  out="$(run_install "$sb" --harness claude-code --scope project --assets skills --dry-run 2>&1)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "output mentions dry run" "$out" "dry run"
  assert_missing "no .claude dir created" "$sb/cwd/.claude"
}

test_install_project_scope() {
  _head "install into project scope (cwd)"
  local sb code
  sb="$(new_sandbox)"
  run_install "$sb" --harness claude-code --scope project --assets skills >/dev/null 2>&1; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_exists "skill copied under .claude/skills" "$sb/cwd/.claude/skills/atomic-commits/SKILL.md"
}

test_install_user_scope() {
  _head "install into user scope (\$HOME)"
  local sb code
  sb="$(new_sandbox)"
  run_install "$sb" --harness claude-code --scope user --assets skills >/dev/null 2>&1; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_exists "skill copied under \$HOME/.claude/skills" "$sb/home/.claude/skills/atomic-commits/SKILL.md"
  assert_missing "cwd untouched" "$sb/cwd/.claude"
}

test_force_flag() {
  _head "--force controls overwrite of an existing destination"
  local sb after
  sb="$(new_sandbox)"
  mkdir -p "$sb/cwd/.claude/skills/atomic-commits"
  printf 'SENTINEL\n' > "$sb/cwd/.claude/skills/atomic-commits/SKILL.md"

  run_install "$sb" --harness claude-code --scope project --assets skills >/dev/null 2>&1
  assert_contains "without --force, existing file is untouched" \
    "$(cat "$sb/cwd/.claude/skills/atomic-commits/SKILL.md")" "SENTINEL"

  run_install "$sb" --harness claude-code --scope project --assets skills --force >/dev/null 2>&1
  after="$(cat "$sb/cwd/.claude/skills/atomic-commits/SKILL.md")"
  [[ "$after" != "SENTINEL" ]] && _ok "--force overwrites the existing destination" \
    || _fail "--force overwrites the existing destination (still SENTINEL)"
}

test_unknown_harness() {
  _head "unknown harness fails cleanly"
  local sb out code
  sb="$(new_sandbox)"
  out="$(run_install "$sb" --harness nope --scope project 2>&1)"; code=$?
  assert_exit "exits 1" 1 "$code"
  assert_contains "reports unknown harness" "$out" "unknown harness"
}

test_unknown_scope() {
  _head "unknown scope fails cleanly"
  local sb out code
  sb="$(new_sandbox)"
  out="$(run_install "$sb" --harness claude-code --scope nope 2>&1)"; code=$?
  assert_exit "exits 1" 1 "$code"
  assert_contains "reports missing scope" "$out" "no scope"
}

test_copilot_user_scope_unsupported() {
  _head "copilot has no user scope (documented gap)"
  local sb code
  sb="$(new_sandbox)"
  run_install "$sb" --harness copilot --scope user >/dev/null 2>&1; code=$?
  assert_exit "exits 1" 1 "$code"
}

test_unknown_asset_category() {
  _head "unknown asset category fails cleanly"
  local sb out code
  sb="$(new_sandbox)"
  out="$(run_install "$sb" --harness claude-code --scope project --assets bogus 2>&1)"; code=$?
  assert_exit "exits 1" 1 "$code"
  assert_contains "reports unknown category" "$out" "unknown asset category"
}

test_category_without_mapping_skips() {
  _head "category with no mapping for harness warns, does not fail"
  # copilot now has a mapping for both real categories (skills, suites), so
  # this repo's own harnesses.json no longer has a live example of the gap
  # this test covers (ADR-0003's compatibility-by-omission path). Exercise it
  # against a synthetic harness instead, reusing this repo's real skills/
  # suites content via --local so catalog.sh still has real items to select.
  local sb src out code
  sb="$(new_sandbox)"
  src="$sb/fake_src"
  mkdir -p "$src/scripts"
  cp "$REPO/scripts/catalog.sh" "$src/scripts/catalog.sh"
  cp -R "$REPO/skills" "$src/skills"
  cp -R "$REPO/suites" "$src/suites"
  cat > "$src/scripts/harnesses.json" <<'JSON'
{
  "partial-harness": {
    "label": "Partial Harness",
    "scopes": { "project": ".partial" },
    "mapping": { "skills": "skills/{name}" }
  }
}
JSON

  out="$( ( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
      bash "$INSTALL" --local "$src" --harness partial-harness --scope project --assets suites ) 2>&1 )"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "warns no mapping" "$out" "no mapping"
  assert_missing "nothing installed" "$sb/cwd/.partial"
}

test_missing_required_flags() {
  _head "required flags enforced"
  local sb out code
  sb="$(new_sandbox)"
  out="$(run_install "$sb" 2>&1)"; code=$?
  assert_exit "no flags: exits 1" 1 "$code"
  assert_contains "no flags: reports missing harness" "$out" "--harness is required"

  out="$(run_install "$sb" --harness claude-code 2>&1)"; code=$?
  assert_exit "harness only: exits 1" 1 "$code"
  assert_contains "harness only: reports missing scope" "$out" "--scope is required"
}

test_help_flag() {
  _head "-h/--help shows usage without requiring other flags"
  local sb out code
  sb="$(new_sandbox)"
  out="$(run_install "$sb" -h 2>&1)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "shows usage" "$out" "Usage: install.sh"
}

test_missing_harnesses_json() {
  _head "fetched tree missing scripts/harnesses.json fails cleanly (regression)"
  local sb src out code
  sb="$(new_sandbox)"
  src="$sb/fake_src"
  mkdir -p "$src/scripts"
  cp "$REPO/scripts/catalog.sh" "$src/scripts/catalog.sh"
  # deliberately no harnesses.json in $src

  out="$( ( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
      bash "$INSTALL" --local "$src" --harness claude-code --scope project ) 2>&1 )"; code=$?
  assert_exit "exits 1" 1 "$code"
  assert_contains "reports missing harnesses.json cleanly" "$out" "missing scripts/harnesses.json"
  assert_not_contains "no raw python traceback" "$out" "Traceback"
}

test_interactive_picker_fallback() {
  _head "interactive numbered picker (no fzf/gum on PATH)"
  if command -v fzf &>/dev/null || command -v gum &>/dev/null; then
    _skip "fzf/gum present on PATH — numbered fallback not exercised here"
    return
  fi
  local sb out code
  sb="$(new_sandbox)"
  # Answer "a" (all) to every per-category prompt; extra lines are harmless
  # if there end up being fewer prompts than lines.
  out="$(printf 'a\na\na\na\na\na\n' | \
    ( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" INSTALL_FORCE_INTERACTIVE=1 \
        bash "$INSTALL" --local "$REPO" --harness claude-code --scope project ) 2>&1)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_exists "picker installed at least one skill" "$sb/cwd/.claude/skills/atomic-commits/SKILL.md"
}

test_suite_dependency_autoincluded() {
  _head "installing a suite auto-includes its declared skill dependencies"
  local sb code
  sb="$(new_sandbox)"
  run_install "$sb" --harness claude-code --scope project --assets suites >/dev/null 2>&1; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_exists "handoff-workflow's declared dep 'create-adr' installed" \
    "$sb/cwd/.claude/skills/create-adr/SKILL.md"
  assert_exists "handoff-workflow's declared dep 'yaml-frontmatter' installed" \
    "$sb/cwd/.claude/skills/yaml-frontmatter/SKILL.md"
}

test_no_deps_flag_skips_dependencies() {
  _head "--no-deps installs a suite without its declared dependencies"
  local sb code
  sb="$(new_sandbox)"
  run_install "$sb" --harness claude-code --scope project --assets suites --no-deps >/dev/null 2>&1; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_exists "handoff-workflow itself still installed" \
    "$sb/cwd/.claude/suites/handoff-workflow/README.md"
  assert_missing "no skills/ dir created — no dependency pulled in" \
    "$sb/cwd/.claude/skills"
}

test_dependency_not_duplicated_when_already_selected() {
  _head "a dependency already covered by the selection isn't re-announced"
  local sb out code
  sb="$(new_sandbox)"
  # Selecting both categories means create-adr/yaml-frontmatter are already
  # part of the "skills" selection before suite dependency resolution runs.
  out="$(run_install "$sb" --harness claude-code --scope project --assets skills,suites 2>&1)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_not_contains "no 'including dependency' note for an already-selected skill" \
    "$out" "including dependency skill"
  assert_exists "create-adr still installed exactly once" \
    "$sb/cwd/.claude/skills/create-adr/SKILL.md"
}

test_copilot_suite_translation() {
  _head "copilot harness translates a plugin-shaped suite's agents/ and manifest"
  local sb code
  sb="$(new_sandbox)"
  run_install "$sb" --harness copilot --scope project --assets suites >/dev/null 2>&1; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_exists "agents/*.md renamed to *.agent.md" \
    "$sb/cwd/.github/suites/hub-and-spoke-orchestration/agents/01-orchestrator.agent.md"
  assert_missing "original .md name no longer present" \
    "$sb/cwd/.github/suites/hub-and-spoke-orchestration/agents/01-orchestrator.md"
  assert_exists "plugin.json moved to the plugin root" \
    "$sb/cwd/.github/suites/hub-and-spoke-orchestration/plugin.json"
  assert_missing ".claude-plugin/ not carried into the copilot copy" \
    "$sb/cwd/.github/suites/hub-and-spoke-orchestration/.claude-plugin"
}

test_copilot_skips_non_plugin_shaped_suite() {
  _head "copilot harness skips a suite with no Copilot-native form"
  local sb out code
  sb="$(new_sandbox)"
  out="$(run_install "$sb" --harness copilot --scope project --assets suites 2>&1)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "warns it's not plugin-shaped" "$out" "not plugin-shaped"
  assert_missing "tiered-escalation-suite (drop-in payload) not copied by install.sh" \
    "$sb/cwd/.github/suites/tiered-escalation-suite"
}

test_dry_run_writes_nothing
test_install_project_scope
test_install_user_scope
test_force_flag
test_unknown_harness
test_unknown_scope
test_copilot_user_scope_unsupported
test_unknown_asset_category
test_category_without_mapping_skips
test_missing_required_flags
test_help_flag
test_missing_harnesses_json
test_interactive_picker_fallback
test_suite_dependency_autoincluded
test_no_deps_flag_skips_dependencies
test_dependency_not_duplicated_when_already_selected
test_copilot_suite_translation
test_copilot_skips_non_plugin_shaped_suite

printf "\n"
if [[ $FAIL -eq 0 ]]; then
  printf "${GRN}${BLD}%d passed, %d skipped.${NC}\n\n" "$PASS" "$SKIP"
  exit 0
else
  printf "${RED}${BLD}%d passed, %d failed, %d skipped.${NC}\n\n" "$PASS" "$FAIL" "$SKIP"
  exit 1
fi
