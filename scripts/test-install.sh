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
  local sb out code
  sb="$(new_sandbox)"
  out="$(run_install "$sb" --harness copilot --scope project --assets suites 2>&1)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "warns no mapping" "$out" "no mapping"
  assert_missing "nothing installed" "$sb/cwd/.github"
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

test_deps_auto_added_with_yes_deps() {
  _head "--yes-deps auto-adds a suite's dependencies"
  local sb out code
  sb="$(new_sandbox)"
  out="$(run_install "$sb" --harness claude-code --scope project --assets suites --dry-run --yes-deps 2>&1)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "dry-run lists skills/create-adr" "$out" "skills/create-adr"
  assert_contains "dry-run lists skills/yaml-frontmatter" "$out" "skills/yaml-frontmatter"
}

test_deps_missing_noninteractive_fails() {
  _head "missing deps, no flags, no TTY: fails and names the paths (same under --dry-run)"
  local sb out code
  sb="$(new_sandbox)"
  out="$(run_install "$sb" --harness claude-code --scope project --assets suites 2>&1)"; code=$?
  assert_exit "exits 1" 1 "$code"
  assert_contains "names skills/create-adr" "$out" "skills/create-adr"
  assert_contains "names skills/yaml-frontmatter" "$out" "skills/yaml-frontmatter"

  out="$(run_install "$sb" --harness claude-code --scope project --assets suites --dry-run 2>&1)"; code=$?
  assert_exit "exits 1 under --dry-run too" 1 "$code"
  assert_contains "names skills/create-adr under --dry-run" "$out" "skills/create-adr"
  assert_contains "names skills/yaml-frontmatter under --dry-run" "$out" "skills/yaml-frontmatter"
}

test_deps_no_deps_flag_skips() {
  _head "--no-deps opts out, does not silently add the dependency"
  local sb out code
  sb="$(new_sandbox)"
  out="$(run_install "$sb" --harness claude-code --scope project --assets suites --dry-run --no-deps 2>&1)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "warns it is skipping dependencies" "$out" "skipping dependencies"
  assert_not_contains "does not add skills/create-adr as a dry-run entry" "$out" "skills/create-adr ->"
}

test_deps_already_selected_no_duplicate() {
  _head "a dependency already selected directly is not duplicated"
  local sb out code
  sb="$(new_sandbox)"
  out="$(run_install "$sb" --harness claude-code --scope project --assets skills,suites --dry-run --yes-deps 2>&1)"; code=$?
  assert_exit "exits 0" 0 "$code"
  [[ "$(grep -c "skills/create-adr" <<< "$out")" == "1" ]] \
    && _ok "skills/create-adr appears exactly once" \
    || _fail "skills/create-adr appears exactly once (got $(grep -c "skills/create-adr" <<< "$out"))"
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
test_deps_auto_added_with_yes_deps
test_deps_missing_noninteractive_fails
test_deps_no_deps_flag_skips
test_deps_already_selected_no_duplicate
test_interactive_picker_fallback

printf "\n"
if [[ $FAIL -eq 0 ]]; then
  printf "${GRN}${BLD}%d passed, %d skipped.${NC}\n\n" "$PASS" "$SKIP"
  exit 0
else
  printf "${RED}${BLD}%d passed, %d failed, %d skipped.${NC}\n\n" "$PASS" "$FAIL" "$SKIP"
  exit 1
fi
