#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# test-install.sh — Behavioral tests for install.sh.
#
# Each test runs install.sh against a throwaway sandbox (isolated CWD + HOME)
# built under mktemp -d, so nothing touches the real repo or the real home
# directory — every sandbox is deleted on exit, pass or fail. Uses install.sh's
# undocumented test seams (--local, INSTALL_FORCE_INTERACTIVE); see
# docs/memory/vendor-agnostic-installer.md. The fetch path is covered with a
# stubbed curl (stub_curl); the real network fetch is never exercised.
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

# copy_tree_for_validate <dest>: a scratch tree validate.sh can run in and pass clean
# (it lints install.sh too, so install.sh must come along).
copy_tree_for_validate() {
  cp -R "$REPO/scripts" "$REPO/skills" "$REPO/suites" "$REPO/.claude-plugin" "$REPO/install.sh" "$1/"
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

test_malformed_dependencies_json_fails_cleanly() {
  _head "malformed dependencies.json fails the catalog build cleanly (regression)"
  local sb src out code
  sb="$(new_sandbox)"
  src="$sb/fake_src"
  mkdir -p "$src/scripts" "$src/skills/fake-skill" "$src/suites"
  cp "$REPO/scripts/catalog.sh" "$src/scripts/catalog.sh"
  cp "$REPO/scripts/harnesses.json" "$src/scripts/harnesses.json"
  printf -- '---\ndescription: test\n---\n' > "$src/skills/fake-skill/SKILL.md"
  printf 'not json' > "$src/skills/fake-skill/dependencies.json"

  out="$( ( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
      bash "$INSTALL" --local "$src" --harness claude-code --scope project --assets skills --dry-run ) 2>&1 )"; code=$?
  assert_exit "exits 1" 1 "$code"
  assert_contains "reports invalid JSON, names the file" "$out" "invalid JSON"
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

test_deps_unsupported_category_warns() {
  _head "deps in a category the harness has no mapping for warn and are skipped"
  local sb src out code
  sb="$(new_sandbox)"
  src="$sb/fake_src"
  mkdir -p "$src/scripts" "$src/skills" "$src/suites/fixture-suite"
  cp "$REPO/scripts/catalog.sh" "$src/scripts/catalog.sh"
  # Synthetic harness maps only suites, so a skills/ dep has no mapping.
  printf '{"only-suites":{"label":"Only suites","scopes":{"project":".x"},"mapping":{"suites":"suites/{name}"}}}' \
    > "$src/scripts/harnesses.json"
  printf '# fixture\n' > "$src/suites/fixture-suite/README.md"
  printf '["skills/x","prompts/y"]' > "$src/suites/fixture-suite/dependencies.json"

  out="$( ( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
      bash "$INSTALL" --local "$src" --harness only-suites --scope project --assets suites --yes-deps ) 2>&1 )"; code=$?
  assert_exit "exits 0 — unsupported deps are not fatal" 0 "$code"
  assert_contains "warns skills/x has no mapping" "$out" "dependency 'skills/x' has no mapping for harness 'only-suites'"
  assert_contains "warns prompts/y has an unrecognized category" "$out" "dependency 'prompts/y' has an unrecognized category"
  assert_exists "suite itself still installed" "$sb/cwd/.x/suites/fixture-suite/README.md"
  assert_missing "no skills/ dir created" "$sb/cwd/.x/skills"
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

# Complements test_deps_no_deps_flag_skips (which asserts --no-deps's dry-run
# output): this one runs a real install and asserts the resulting on-disk tree.
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

test_copilot_suite_translation() {
  _head "copilot harness translates a plugin-shaped suite's agents/ and manifest"
  local sb code
  sb="$(new_sandbox)"
  # --no-deps keeps this focused on translation: handoff-workflow declares
  # dependencies, and a flagless non-interactive run now fails closed (ADR-0009)
  # rather than auto-adding them, which has nothing to do with what's asserted here.
  run_install "$sb" --harness copilot --scope project --assets suites --no-deps >/dev/null 2>&1; code=$?
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
  # --no-deps for the same reason as above — see test_copilot_suite_translation.
  out="$(run_install "$sb" --harness copilot --scope project --assets suites --no-deps 2>&1)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "warns it's not plugin-shaped" "$out" "not plugin-shaped"
  assert_missing "tiered-escalation-suite (drop-in payload) not copied by install.sh" \
    "$sb/cwd/.github/suites/tiered-escalation-suite"
}

test_copilot_dep_on_non_plugin_shaped_suite_skipped() {
  _head "copilot harness skips a non-plugin-shaped suite pulled in as a dependency"
  local sb src out code
  sb="$(new_sandbox)"
  src="$sb/fake_src"
  mkdir -p "$src/scripts" "$src/skills/fake-skill" "$src/suites/dropin-suite"
  cp "$REPO/scripts/catalog.sh" "$src/scripts/catalog.sh"
  cp "$REPO/scripts/harnesses.json" "$src/scripts/harnesses.json"
  printf -- '---\ndescription: test\n---\n' > "$src/skills/fake-skill/SKILL.md"
  printf '["suites/dropin-suite"]' > "$src/skills/fake-skill/dependencies.json"
  printf 'drop-in\n' > "$src/suites/dropin-suite/README.md"

  out="$( ( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
      bash "$INSTALL" --local "$src" --harness copilot --scope project --assets skills --yes-deps ) 2>&1 )"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "warns the dependency is not plugin-shaped" "$out" "dependency 'suites/dropin-suite' is not plugin-shaped"
  assert_missing "drop-in suite dependency not copied into .github" \
    "$sb/cwd/.github/suites/dropin-suite"
  assert_exists "dependent skill still installed" "$sb/cwd/.github/skills/fake-skill"
}

# ── fetch path via a stubbed curl (no network) ───────────────────────────────
# stub_curl <sandbox>: puts a fake `curl` on <sandbox>/bin. It appends its args
# to <sandbox>/curl.args and writes, to the -o target, a codeload-shaped tarball
# (top dir <top>, default ai-personal-main/) of a minimal repo. Portable tar only: no bsdtar -s.
stub_curl() {
  local sb="$1" name="${2:-ai-personal-main}" top="$1/fake/${2:-ai-personal-main}"
  mkdir -p "$top/scripts" "$top/skills/demo"
  cp "$REPO/scripts/catalog.sh" "$REPO/scripts/harnesses.json" "$top/scripts/"
  printf -- '---\nname: demo\ndescription: stub\n---\n' > "$top/skills/demo/SKILL.md"
  cat > "$sb/bin/curl" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$sb/curl.args"
while [[ \$# -gt 0 ]]; do [[ "\$1" == -o ]] && out="\$2"; shift; done
tar -czf "\$out" -C "$sb/fake" $name
STUB
  chmod +x "$sb/bin/curl"
}

test_fetch_via_stubbed_curl() {
  _head "real fetch path (stubbed curl, no --local)"
  local sb out code
  sb="$(new_sandbox)"
  stub_curl "$sb"
  out="$( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
    bash "$INSTALL" --harness claude-code --scope project --assets skills 2>&1 )"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "requested the codeload tarball URL" "$(cat "$sb/curl.args" 2>&1)" \
    "https://codeload.github.com/jean-tessier/ai-personal/tar.gz/main"
  assert_exists "skill from the extracted tarball installed" "$sb/cwd/.claude/skills/demo/SKILL.md"
}

test_manifest_lint_rejects_bad_manifest() {
  _head "validate.sh rejects a bad suite manifest and a typo'd mapping key (ADR-0008 lint)"
  local sb src out code
  sb="$(new_sandbox)"
  src="$sb/fake_src"
  mkdir -p "$src"
  copy_tree_for_validate "$src"
  bash "$src/scripts/validate.sh" </dev/null >/dev/null 2>&1; assert_exit "unmodified scratch tree validates clean" 0 "$?"
  printf '%s' '{"bogus":[],"claude-code":[{"kind":"agents","src":"../x","mode":"copy"},{"kind":["agents"],"src":"claude-code/agents","mode":"copy"}]}' \
    > "$src/suites/tier-layered-teams/manifest.json"
  out="$(bash "$src/scripts/validate.sh" </dev/null 2>&1)"; code=$?
  assert_exit "bad manifest: exits 1" 1 "$code"
  assert_contains "flags unknown harness key" "$out" "unknown harness key 'bogus'"
  assert_contains "flags non-relative src" "$out" "src must be relative"
  assert_contains "a lint crash is a FAIL, not a silent ok" "$out" "check crashed"
  cp "$REPO/suites/tier-layered-teams/manifest.json" "$src/suites/tier-layered-teams/manifest.json"
  python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); m=d["copilot"]["mapping"]; m["suite"]=m.pop("suites"); json.dump(d,open(p,"w"))' "$src/scripts/harnesses.json"
  out="$(bash "$src/scripts/validate.sh" </dev/null 2>&1)"; code=$?
  assert_exit "typo'd mapping key: exits 1" 1 "$code"
  assert_contains "flags the typo'd category" "$out" "unknown category 'suite'"
}

test_translate_lint_rejects_bad_key() {
  _head "validate.sh rejects a bad translate key (ADR-0011 lint)"
  local sb src out code
  sb="$(new_sandbox)"
  src="$sb/fake_src"
  mkdir -p "$src"
  copy_tree_for_validate "$src"
  python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["copilot"]["translate"]={"suites":"bogus-transform","prompts":"copilot-plugin","skills":"copilot-plugin"}; json.dump(d,open(p,"w"))' "$src/scripts/harnesses.json"
  out="$(bash "$src/scripts/validate.sh" </dev/null 2>&1)"; code=$?
  assert_exit "bad translate: exits 1" 1 "$code"
  assert_contains "flags the unknown transform" "$out" "unknown transform 'bogus-transform'"
  assert_contains "flags a category not in mapping" "$out" "category 'prompts' not in mapping"
  assert_contains "flags a transform on the wrong category" "$out" "does not apply to category 'skills'"
}

test_translate_unknown_or_invalid_skips() {
  _head "an unknown or malformed translate value skips the item (fails closed)"
  local sb src out code bad
  for bad in None '"bogus"'; do
    sb="$(new_sandbox)"
    src="$sb/fake_src"
    mkdir -p "$src"
    cp -R "$REPO/scripts" "$REPO/skills" "$REPO/suites" "$REPO/.claude-plugin" "$src/"
    python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["copilot"]["translate"]={"suites":eval(sys.argv[2])}; json.dump(d,open(p,"w"))' "$src/scripts/harnesses.json" "$bad"
    out="$( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" bash "$INSTALL" --local "$src" --harness copilot --scope project --assets suites --no-deps </dev/null 2>&1 )"; code=$?
    assert_exit "translate=$bad: exits 0" 0 "$code"
    assert_contains "translate=$bad: warns about the transform" "$out" "unknown translate transform"
    assert_missing "translate=$bad: nothing translated under .github/suites" "$sb/cwd/.github/suites"
  done
}

test_fetch_curl_failure_exits_1() {
  _head "failed curl fetch exits 1 with a message (not curl's own code)"
  local sb out code
  sb="$(new_sandbox)"
  printf '#!/usr/bin/env bash\nexit 22\n' > "$sb/bin/curl"; chmod +x "$sb/bin/curl"
  out="$( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
    bash "$INSTALL" --harness claude-code --scope project --assets skills 2>&1 )"; code=$?
  assert_exit "exits 1, not curl's 22" 1 "$code"
  assert_contains "prints the fetch failure" "$out" "fetch failed"
}

test_fetch_bad_tarball_exits_1() {
  _head "failed tar extraction exits 1 with a message"
  local sb out code
  sb="$(new_sandbox)"
  printf '#!/usr/bin/env bash\nwhile [[ $# -gt 0 ]]; do [[ "$1" == -o ]] && echo junk > "$2"; shift; done\n' > "$sb/bin/curl"
  chmod +x "$sb/bin/curl"
  out="$( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
    bash "$INSTALL" --harness claude-code --scope project --assets skills 2>&1 )"; code=$?
  assert_exit "exits 1" 1 "$code"
  assert_contains "prints the extraction failure" "$out" "extract failed"
}

# --ref pins the fetched tree. codeload names the top dir {repo}-{ref} (slashes
# become dashes, a leading v is dropped from tags), so the stub uses ai-personal-9.
test_ref_pins_fetched_tree() {
  _head "--ref (stubbed curl)"
  local sb out code
  sb="$(new_sandbox)"
  stub_curl "$sb" ai-personal-9
  out="$( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
    bash "$INSTALL" --harness claude-code --scope project --assets skills --ref v9 2>&1 )"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "URL carries the ref" "$(cat "$sb/curl.args" 2>&1)" \
    "https://codeload.github.com/jean-tessier/ai-personal/tar.gz/v9"
  assert_exists "skill from a non-main top dir installed" "$sb/cwd/.claude/skills/demo/SKILL.md"
}

test_ref_rejects_bad_values() {
  _head "--ref validation"
  local sb out code ref
  for ref in 'a b' 'v1;rm' '../x' 'a..b' '$(id)' ''; do
    sb="$(new_sandbox)"
    stub_curl "$sb"
    out="$( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
      bash "$INSTALL" --harness claude-code --scope project --ref "$ref" 2>&1 )"; code=$?
    assert_exit "bad ref '$ref' exits 1" 1 "$code"
    assert_contains "bad ref '$ref' names --ref" "$out" "--ref"
    assert_missing "bad ref '$ref' never calls curl" "$sb/curl.args"
  done
  # a value flag with no value must fail, not exit 0 (bash 3.2 reports the EXIT trap's status)
  local args
  for args in '--ref' '--ref --dry-run'; do
    sb="$(new_sandbox)"
    stub_curl "$sb"
    # shellcheck disable=SC2086
    out="$( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
      bash "$INSTALL" --harness claude-code --scope project $args 2>&1 )"; code=$?
    assert_exit "'$args' exits 1" 1 "$code"
    assert_contains "'$args' says --ref needs a value" "$out" "--ref needs a value"
    assert_missing "'$args' never calls curl" "$sb/curl.args"
  done
  sb="$(new_sandbox)"
  out="$( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" bash "$INSTALL" --scope project --harness 2>&1 )"; code=$?
  assert_exit "--harness with no value exits 1" 1 "$code"
  assert_contains "--harness says it needs a value" "$out" "--harness needs a value"
}

test_ref_with_local_fails() {
  _head "--ref with --local"
  local sb out code
  sb="$(new_sandbox)"
  out="$(run_install "$sb" --harness claude-code --scope project --ref v9 2>&1)"; code=$?
  assert_exit "exits 1" 1 "$code"
  assert_contains "explains the conflict" "$out" "--ref cannot be combined with --local"
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
test_malformed_dependencies_json_fails_cleanly
test_deps_auto_added_with_yes_deps
test_deps_missing_noninteractive_fails
test_deps_no_deps_flag_skips
test_deps_already_selected_no_duplicate
test_deps_unsupported_category_warns
test_interactive_picker_fallback
test_no_deps_flag_skips_dependencies
test_copilot_suite_translation
test_copilot_skips_non_plugin_shaped_suite
test_copilot_dep_on_non_plugin_shaped_suite_skipped
test_fetch_via_stubbed_curl
test_manifest_lint_rejects_bad_manifest
test_translate_lint_rejects_bad_key
test_translate_unknown_or_invalid_skips
test_fetch_curl_failure_exits_1
test_fetch_bad_tarball_exits_1
test_ref_pins_fetched_tree
test_ref_rejects_bad_values
test_ref_with_local_fails

# A dependency that can't be placed is noted once, even though a later
# resolve_dependencies() round still sees it declared by an already-selected suite.
test_dep_skip_note_printed_once() {
  _head "a skipped dependency's note is printed once across rounds"
  local sb src out code note="dependency 'prompts/y' has an unrecognized category"
  sb="$(new_sandbox)"
  src="$sb/fake_src"
  mkdir -p "$src/scripts" "$src/skills/s1" "$src/suites/fixture-suite"
  cp "$REPO/scripts/catalog.sh" "$src/scripts/catalog.sh"
  printf '{"h":{"label":"H","scopes":{"project":".x"},"mapping":{"skills":"skills/{name}","suites":"suites/{name}"}}}' \
    > "$src/scripts/harnesses.json"
  printf -- '---\nname: s1\ndescription: d\n---\n' > "$src/skills/s1/SKILL.md"
  printf '# fixture\n' > "$src/suites/fixture-suite/README.md"
  # prompts/y is skipped in round 1; skills/s1 is added, forcing a round 2 that
  # still sees prompts/y declared by the already-selected suite.
  printf '["prompts/y","skills/s1"]' > "$src/suites/fixture-suite/dependencies.json"

  out="$( ( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
      bash "$INSTALL" --local "$src" --harness h --scope project --assets suites --yes-deps ) 2>&1 )"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_exists "dependency skill installed (so a second round ran)" "$sb/cwd/.x/skills/s1/SKILL.md"
  [[ "$(grep -c "$note" <<< "$out")" -eq 1 ]] \
    && _ok "prompts/y's skip note appears exactly once" \
    || _fail "prompts/y's skip note appears exactly once (got $(grep -c "$note" <<< "$out"))"
}
test_dep_skip_note_printed_once

# A scope root of "" must anchor at $PWD like any other relative root, never at "/".
test_empty_scope_root_anchors_at_pwd() {
  _head "an empty scope root anchors at the project root, not /"
  local sb src out code
  sb="$(new_sandbox)"
  src="$sb/fake_src"
  mkdir -p "$src/scripts" "$src/skills/s1"
  cp "$REPO/scripts/catalog.sh" "$src/scripts/catalog.sh"
  printf '{"h":{"label":"H","scopes":{"project":""},"mapping":{"skills":"skills/{name}"}}}' \
    > "$src/scripts/harnesses.json"
  printf -- '---\nname: s1\ndescription: d\n---\n' > "$src/skills/s1/SKILL.md"

  out="$( ( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
      bash "$INSTALL" --local "$src" --harness h --scope project --assets skills --dry-run ) 2>&1 )"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "destination is under the project root" "$out" "$sb/cwd/skills/s1"
  assert_not_contains "destination is not rooted at /" "$out" " -> /skills/"
}
test_empty_scope_root_anchors_at_pwd

# Install record (ADR-0012): <scope root>/.ai-personal-install.json lists every placed file + sha256.
# record_check <record> <cwd> <home> prints "<files recorded> <missing or mismatched>".
record_check() {
  local py
  read -r -d '' py <<'PY' || true
import json, sys, os, hashlib
rec, cwd, home = sys.argv[1:4]
n = bad = 0
for a in json.load(open(rec))["assets"].values():
    for k, h in a["files"].items():
        p = os.path.join(home, k[2:]) if k.startswith("~/") else os.path.join(cwd, k)
        n += 1
        if not os.path.isfile(p) or h != "sha256:" + hashlib.sha256(open(p, "rb").read()).hexdigest():
            bad += 1
print(n, bad)
PY
  python3 -c "$py" "$@"
}

# assert_record <desc> <record> <cwd> <home> <expected mismatches> [expected file count]:
# the record parses, has the expected mismatches, and lists at least one file (or exactly N).
assert_record() {
  local desc="$1" got n bad
  got="$(record_check "$2" "$3" "$4" 2>&1)"; n="${got% *}"; bad="${got#* }"
  [[ "$bad" == "$5" && "$n" -gt 0 && "$n" == "${6:-$n}" ]] && _ok "$desc" || _fail "$desc (files/mismatches: $got)"
}

# record_json <record> <python expr on d>: prints the expression's value.
record_json() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$@"; }

# record_mode <args...>: runs install.sh's own python `record` mode directly.
record_mode() {
  local py
  py="$(awk '/python3 -I - "\$@" <<.PY.$/{f=1;next} /^PY$/{f=0} f' "$INSTALL")"
  python3 -c "$py" record "$@"
}

test_record_lists_every_copied_file() {
  _head "install record lists every copied file with its sha256"
  local sb rec on_disk
  sb="$(new_sandbox)"; rec="$sb/cwd/.claude/.ai-personal-install.json"
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  assert_exists "record written under the scope root" "$rec"
  assert_missing "no temp file left behind" "$rec.tmp"
  on_disk="$(cd "$sb/cwd" && find .claude -type f ! -name .ai-personal-install.json | wc -l | tr -d ' ')"
  assert_record "valid JSON, all hashes match, every file on disk recorded" "$rec" "$sb/cwd" "$sb/home" 0 "$on_disk"
  assert_contains "paths are root-anchored" "$(record_json "$rec" 'sorted(d["assets"]["skills/atomic-commits"]["files"])[0]')" ".claude/skills/atomic-commits/"
  assert_contains "records harness and scope" "$(record_json "$rec" 'd["harness"], d["scope"], d["version"]')" "('claude-code', 'project', 1)"
}

test_record_covers_copilot_translation_and_dependencies() {
  _head "install record covers translated suites and dependency copies"
  local sb rec
  sb="$(new_sandbox)"; rec="$sb/cwd/.github/.ai-personal-install.json"
  run_install "$sb" --harness copilot --scope project --assets suites --yes-deps </dev/null >/dev/null 2>&1
  assert_record "translated files hash as placed, every file on disk recorded" "$rec" "$sb/cwd" "$sb/home" 0 \
    "$(cd "$sb/cwd" && find . -type f ! -name .ai-personal-install.json | wc -l | tr -d ' ')"
  assert_contains "a translated plugin.json is recorded" "$(record_json "$rec" '[k for a in d["assets"].values() for k in a["files"] if k.endswith("/plugin.json")]')" "/plugin.json"
  assert_contains "a dependency is recorded as its own asset" "$(record_json "$rec" 'sorted(d["assets"])')" "'skills/"
}

test_record_merges_on_reinstall() {
  _head "re-install merges into the record instead of clobbering it"
  local sb rec
  sb="$(new_sandbox)"; rec="$sb/cwd/.claude/.ai-personal-install.json"
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); a=d["assets"]; a["skills/earlier"]={"installedAt":"x","files":{".claude/skills/earlier/SKILL.md":"sha256:0"}}; a["skills/atomic-commits"]["installedAt"]="x"; a["skills/atomic-commits"]["files"][".claude/skills/atomic-commits/GONE.md"]="sha256:0"; json.dump(d,open(p,"w"))' "$rec"
  run_install "$sb" --harness claude-code --scope project --assets skills --force </dev/null >/dev/null 2>&1
  assert_contains "earlier asset survives" "$(record_json "$rec" '"skills/earlier" in d["assets"]')" "True"
  assert_contains "re-installed asset is refreshed" "$(record_json "$rec" 'd["assets"]["skills/atomic-commits"]["installedAt"] != "x"')" "True"
  assert_contains "a file the new version no longer ships is dropped" "$(record_json "$rec" '".claude/skills/atomic-commits/GONE.md" in d["assets"]["skills/atomic-commits"]["files"]')" "False"
  assert_record "only the planted entry of the other asset fails its hash check" "$rec" "$sb/cwd" "$sb/home" 1
}

test_record_skipped_files_not_recorded_and_dry_run_writes_none() {
  _head "skipped destinations are not recorded; --dry-run writes no record"
  local sb
  sb="$(new_sandbox)"
  run_install "$sb" --harness claude-code --scope project --assets skills --dry-run </dev/null >/dev/null 2>&1
  assert_missing "dry run: no record" "$sb/cwd/.claude/.ai-personal-install.json"
  mkdir -p "$sb/cwd/.claude/skills/atomic-commits"; printf 'mine\n' > "$sb/cwd/.claude/skills/atomic-commits/SKILL.md"
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  assert_contains "the user's own skill is never recorded" \
    "$(record_json "$sb/cwd/.claude/.ai-personal-install.json" '"skills/atomic-commits" in d["assets"]')" "False"
}

test_record_source_ref() {
  _head "install record stores --ref as source.ref, null under --local"
  local sb
  sb="$(new_sandbox)"
  stub_curl "$sb" ai-personal-9
  ( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
    bash "$INSTALL" --harness claude-code --scope project --assets skills --ref v9 </dev/null >/dev/null 2>&1 )
  assert_contains "--ref v9 recorded" "$(record_json "$sb/cwd/.claude/.ai-personal-install.json" 'd["source"]')" "'ref': 'v9'"
  sb="$(new_sandbox)"
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  assert_contains "--local records ref null" "$(record_json "$sb/cwd/.claude/.ai-personal-install.json" 'd["source"]')" "'ref': None"
}

test_record_ref_per_asset() {
  _head "install record keeps each asset's own ref across installs"
  local sb rec
  sb="$(new_sandbox)"; rec="$sb/cwd/.claude/.ai-personal-install.json"
  stub_curl "$sb" ai-personal-1
  ( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
    bash "$INSTALL" --harness claude-code --scope project --assets skills --ref v1 </dev/null >/dev/null 2>&1 )
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  assert_contains "the first install's asset keeps ref v1" "$(record_json "$rec" 'd["assets"]["skills/demo"]["ref"]')" "v1"
  assert_contains "the second install's asset has ref null" "$(record_json "$rec" 'd["assets"]["skills/atomic-commits"]["ref"]')" "None"
  assert_contains "top-level source.ref is the last install's" "$(record_json "$rec" 'd["source"]["ref"]')" "None"
}

test_record_user_scope_root() {
  _head "install record for user scope lives under the user root"
  local sb rec
  sb="$(new_sandbox)"; rec="$sb/home/.claude/.ai-personal-install.json"
  run_install "$sb" --harness claude-code --scope user --assets skills </dev/null >/dev/null 2>&1
  assert_exists "record under \$HOME/.claude" "$rec"
  assert_missing "cwd untouched" "$sb/cwd/.claude"
  assert_record "paths are ~-anchored and match on disk, every file recorded" "$rec" "$sb/cwd" "$sb/home" 0 \
    "$(cd "$sb/home" && find .claude -type f ! -name .ai-personal-install.json | wc -l | tr -d ' ')"
  assert_contains "keys start with ~/.claude/" "$(record_json "$rec" 'sorted(d["assets"]["skills/atomic-commits"]["files"])[0]')" "~/.claude/skills/"
}

test_record_bad_record_stops_before_any_copy() {
  _head "an unusable install record stops the install before any file is copied"
  local sb out code bad
  sb="$(new_sandbox)"
  mkdir -p "$sb/cwd/.claude"; printf '{"version":2,"assets":{}}' > "$sb/cwd/.claude/.ai-personal-install.json"
  cp "$sb/cwd/.claude/.ai-personal-install.json" "$sb/before.json"
  out="$(run_install "$sb" --harness claude-code --scope project --assets skills --dry-run </dev/null 2>&1)"; code=$?
  assert_exit "unknown version, --dry-run: exits 1 like the real run" 1 "$code"
  assert_missing "unknown version, --dry-run: no temp file" "$sb/cwd/.claude/.ai-personal-install.json.tmp"
  out="$(run_install "$sb" --harness claude-code --scope project --assets skills </dev/null 2>&1)"; code=$?
  assert_exit "unknown version: exits 1" 1 "$code"
  assert_contains "unknown version: says why" "$out" "install record"
  assert_missing "unknown version: nothing placed" "$sb/cwd/.claude/skills"
  cmp -s "$sb/before.json" "$sb/cwd/.claude/.ai-personal-install.json" \
    && _ok "unknown version: record untouched" || _fail "unknown version: record untouched"
  for bad in '{bad' '[]' '{"version":1,"assets":[]}' '{"version":1,"harness":"claude-code","scope":"project","assets":{"skills/x":{"files":[]}}}'; do
    sb="$(new_sandbox)"
    mkdir -p "$sb/cwd/.claude"; printf '%s' "$bad" > "$sb/cwd/.claude/.ai-personal-install.json"
    out="$(run_install "$sb" --harness claude-code --scope project --assets skills </dev/null 2>&1)"; code=$?
    assert_exit "record '$bad': exits 1" 1 "$code"
    assert_contains "record '$bad': clean message" "$out" "install record"
    assert_not_contains "record '$bad': no traceback" "$out" "Traceback"
    assert_missing "record '$bad': nothing placed" "$sb/cwd/.claude/skills"
  done
  sb="$(new_sandbox)"
  mkdir -p "$sb/cwd/.claude/.ai-personal-install.json"
  out="$(run_install "$sb" --harness claude-code --scope project --assets skills </dev/null 2>&1)"; code=$?
  assert_exit "record is a directory: exits 1" 1 "$code"
  assert_contains "record is a directory: clean message" "$out" "install record"
  assert_not_contains "record is a directory: no traceback" "$out" "Traceback"
  assert_missing "record is a directory: nothing placed" "$sb/cwd/.claude/skills"
}

test_record_tmp_symlink_not_followed() {
  _head "a planted .tmp symlink is not followed when the record is written"
  local sb rec
  sb="$(new_sandbox)"; rec="$sb/cwd/.claude/.ai-personal-install.json"
  mkdir -p "$sb/cwd/.claude"; printf 'PRECIOUS\n' > "$sb/target"
  ln -s "$sb/target" "$rec.tmp"
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  assert_contains "the link's target is unchanged" "$(cat "$sb/target")" "PRECIOUS"
  [[ -f "$rec" && ! -L "$rec" ]] && _ok "the record is a regular file" || _fail "the record is a regular file"
  assert_missing "no temp link left behind" "$rec.tmp"
}

test_record_other_harness_or_scope_refused() {
  _head "a record belonging to another scope is refused, not rewritten"
  local sb out code rec
  sb="$(new_sandbox)"; rec="$sb/home/.claude/.ai-personal-install.json"
  # project scope run from $HOME resolves to the same record file as user scope
  ( cd "$sb/home" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
    bash "$INSTALL" --local "$REPO" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1 )
  rm -rf "$sb/home/.claude/skills/atomic-commits"
  out="$(run_install "$sb" --harness claude-code --scope user --assets skills </dev/null 2>&1)"; code=$?
  assert_exit "exits 1" 1 "$code"
  assert_contains "names both scopes" "$out" "belongs to claude-code/project, not claude-code/user"
  assert_contains "record still says project" "$(record_json "$rec" 'd["scope"]')" "project"
  assert_missing "the second run placed nothing" "$sb/home/.claude/skills/atomic-commits"
}

test_record_survives_midway_failure() {
  _head "a failure part-way through still records the files placed before it"
  local sb rec code
  if [[ "$(id -u)" == 0 ]]; then _skip "running as root: chmod can't block rm"; return; fi
  sb="$(new_sandbox)"; rec="$sb/cwd/.claude/.ai-personal-install.json"
  mkdir -p "$sb/cwd/.claude/skills/plan-dag/sub"; : > "$sb/cwd/.claude/skills/plan-dag/sub/f"
  chmod 555 "$sb/cwd/.claude/skills/plan-dag/sub"
  run_install "$sb" --harness claude-code --scope project --assets skills --force </dev/null >/dev/null 2>&1; code=$?
  chmod -R u+w "$sb/cwd/.claude"
  assert_exit "exits 1" 1 "$code"
  assert_contains "an earlier skill is recorded" "$(record_json "$rec" '"skills/atomic-commits" in d["assets"]')" "True"
  assert_contains "the failed skill is not" "$(record_json "$rec" '"skills/plan-dag" in d["assets"]')" "False"
  assert_record "recorded files match" "$rec" "$sb/cwd" "$sb/home" 0
}

test_record_mode_rejects_missing_placed_path() {
  _head "record mode fails on a placed path that does not exist"
  local sb out code
  sb="$(new_sandbox)"
  printf 'skills/x\t.claude/skills/x\n' > "$sb/rows.tsv"
  out="$(record_mode "$sb/rec.json" claude-code project o/r main "$sb/rows.tsv" "$sb/cwd" "$sb/home" 2>&1)"; code=$?
  assert_exit "exits 1" 1 "$code"
  assert_contains "says which path" "$out" "placed path missing"
  assert_missing "no record written" "$sb/rec.json"
}

test_validate_rejects_symlinks_in_assets() {
  _head "validate.sh rejects a symlink inside skills/ or suites/"
  local sb src out code
  sb="$(new_sandbox)"; src="$sb/fake_src"
  mkdir -p "$src"
  copy_tree_for_validate "$src"
  bash "$src/scripts/validate.sh" </dev/null >/dev/null 2>&1; assert_exit "unmodified scratch tree validates clean" 0 "$?"
  ln -s x "$src/skills/atomic-commits/l"
  out="$(bash "$src/scripts/validate.sh" </dev/null 2>&1)"; code=$?
  assert_exit "exits 1" 1 "$code"
  assert_contains "names the symlink" "$out" "symlink"
}

test_python_ignores_cwd_modules() {
  _head "python runs isolated: a json.py in the cwd is never imported (SEC1)"
  local sb src out code
  sb="$(new_sandbox)"
  printf 'open("%s", "w").close()\n' "$sb/pwned" > "$sb/cwd/json.py"
  run_install "$sb" --harness claude-code --scope project --assets skills --dry-run </dev/null >/dev/null 2>&1
  assert_missing "install.sh did not import cwd json.py" "$sb/pwned"; rm -f "$sb/pwned"
  rm -f "$sb/pwned"
  ( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" bash "$REPO/scripts/catalog.sh" </dev/null >/dev/null 2>&1 )
  assert_missing "catalog.sh did not import cwd json.py" "$sb/pwned"
  src="$sb/fake_src"; mkdir -p "$src"
  copy_tree_for_validate "$src"
  printf '%s\n' 'python3 - <<X' 'X' >> "$src/scripts/catalog.sh"
  out="$(bash "$src/scripts/validate.sh" </dev/null 2>&1)"; code=$?
  assert_exit "validate.sh exits 1 on a non-isolated python3" 1 "$code"
  assert_contains "names the rule" "$out" "python3 without -I"
}

test_record_lists_every_copied_file
test_record_covers_copilot_translation_and_dependencies
test_record_merges_on_reinstall
test_record_skipped_files_not_recorded_and_dry_run_writes_none
test_record_source_ref
test_record_ref_per_asset
test_record_user_scope_root
test_record_bad_record_stops_before_any_copy
test_record_tmp_symlink_not_followed
test_record_other_harness_or_scope_refused
test_record_survives_midway_failure
test_record_mode_rejects_missing_placed_path
test_validate_rejects_symlinks_in_assets
test_python_ignores_cwd_modules

# Suite manifest placements (ADR-0008, copy mode): a fixture suite "fx" with a manifest.json.
# manifest_fixture <sandbox> <manifest json>: builds <sandbox>/fake_src (real harnesses.json) and prints its path.
manifest_fixture() {
  local src="$1/fake_src"
  mkdir -p "$src/scripts" "$src/suites/fx/claude-code/agents" "$src/suites/fx/claude-code/.claude-plugin" \
    "$src/suites/fx/copilot/.github/hooks" "$src/suites/fx/copilot/scripts"
  cp "$REPO/scripts/catalog.sh" "$REPO/scripts/harnesses.json" "$src/scripts/"
  printf '# fx\n' > "$src/suites/fx/README.md"
  printf 'agent a\n' > "$src/suites/fx/claude-code/agents/a.md"
  printf 'agent b\n' > "$src/suites/fx/claude-code/agents/b.md"
  printf '{}\n' > "$src/suites/fx/claude-code/.claude-plugin/plugin.json"
  printf 'hook\n' > "$src/suites/fx/copilot/.github/hooks/h.json"
  printf 'rules\n' > "$src/suites/fx/copilot/.github/copilot-instructions.md"
  printf 'all:\n' > "$src/suites/fx/copilot/Makefile"
  printf 'echo\n' > "$src/suites/fx/copilot/scripts/run.sh"
  printf '%s' "$2" > "$src/suites/fx/manifest.json"
  printf '%s' "$src"
}
FX_CC='{"claude-code":[{"kind":"agents","src":"claude-code/agents","mode":"copy"},{"kind":"config","src":"claude-code/.claude-plugin","mode":"copy"}]}'
fx_install() { # <sandbox> <src> <args...>
  local sb="$1" src="$2"; shift 2
  ( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" bash "$INSTALL" --local "$src" --scope project --assets suites "$@" ) 2>&1 </dev/null
}

test_manifest_places_files_per_template() {
  _head "a manifest suite is placed per file at its resourceKinds destinations, and recorded"
  local sb src out code d rec
  sb="$(new_sandbox)"; src="$(manifest_fixture "$sb" "$FX_CC")"; d="$sb/cwd/.claude/suites/fx"
  rec="$sb/cwd/.claude/.ai-personal-install.json"
  out="$(fx_install "$sb" "$src" --harness claude-code)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_exists "agents placed by basename" "$d/agents/a.md"
  assert_exists "second agent placed" "$d/agents/b.md"
  assert_exists "config placed at its relpath" "$d/.claude-plugin/plugin.json"
  assert_missing "suite-root README is not placed" "$d/README.md"
  assert_missing "sibling-harness variant is not placed" "$d/copilot"
  assert_record "record lists the 3 placed files, hashes match" "$rec" "$sb/cwd" "$sb/home" 0 3
  assert_contains "record keys them under the suite asset" "$(record_json "$rec" 'sorted(d["assets"]["suites/fx"]["files"])[0]')" ".claude/suites/fx/.claude-plugin/plugin.json"
}
test_manifest_places_files_per_template

test_manifest_existing_file_skipped_and_force_never_removes_dir() {
  _head "an existing placed file is skipped; --force overwrites that file only, never the directory"
  local sb src out d
  sb="$(new_sandbox)"; src="$(manifest_fixture "$sb" "$FX_CC")"; d="$sb/cwd/.claude/suites/fx"
  mkdir -p "$d/agents"; printf 'SENTINEL\n' > "$d/agents/a.md"; printf 'MINE\n' > "$d/agents/user.md"
  out="$(fx_install "$sb" "$src" --harness claude-code)"
  assert_contains "existing file untouched" "$(cat "$d/agents/a.md")" "SENTINEL"
  assert_contains "skip is noted" "$out" "skip (exists)"
  assert_exists "the missing sibling is still placed" "$d/agents/b.md"
  out="$(fx_install "$sb" "$src" --harness claude-code --force)"
  assert_contains "--force overwrites the file" "$(cat "$d/agents/a.md")" "agent a"
  assert_contains "a user file in the same directory survives" "$(cat "$d/agents/user.md")" "MINE"
}
test_manifest_existing_file_skipped_and_force_never_removes_dir

test_manifest_harness_omitted_warns_and_skips() {
  _head "a harness the manifest omits is warned and skipped, never copied whole"
  local sb src out code
  sb="$(new_sandbox)"; src="$(manifest_fixture "$sb" "$FX_CC")"
  out="$(fx_install "$sb" "$src" --harness copilot)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "notes the omission" "$out" "no placements for harness 'copilot'"
  assert_missing "nothing placed" "$sb/cwd/.github/suites"
  assert_missing "no hooks placed" "$sb/cwd/.github/hooks"
}
test_manifest_harness_omitted_warns_and_skips

test_manifest_merge_rows_create_missing_files() {
  _head "merge placements create their missing files; copy placements at the project root still land"
  local sb src out
  sb="$(new_sandbox)"
  src="$(manifest_fixture "$sb" '{"copilot":[{"kind":"hooks","src":"copilot/.github/hooks","mode":"copy"},{"kind":"instructions","src":"copilot/.github/copilot-instructions.md","mode":"merge"},{"kind":"config","src":"copilot/Makefile","mode":"copy"},{"kind":"config","src":"copilot/scripts","mode":"merge"}]}')"
  out="$(fx_install "$sb" "$src" --harness copilot)"
  assert_exists "hook placed" "$sb/cwd/.github/hooks/h.json"
  assert_exists "config relpath lands at the project root" "$sb/cwd/Makefile"
  assert_exists "merge instructions created" "$sb/cwd/.github/copilot-instructions.md"
  assert_exists "merge config created" "$sb/cwd/scripts/run.sh"
  assert_not_contains "no merge-unsupported note" "$out" "not yet supported"
}
test_manifest_merge_rows_create_missing_files

test_manifest_refuses_unsafe_src() {
  _head "a manifest src that is absolute, has ./.. segments or escapes the suite is refused"
  local sb src out code bad
  for bad in '../x' '/etc' 'claude-code/../claude-code/agents' './claude-code' 'claude-code//agents' 'out'; do
    sb="$(new_sandbox)"
    src="$(manifest_fixture "$sb" "{\"claude-code\":[{\"kind\":\"agents\",\"src\":\"$bad\",\"mode\":\"copy\"}]}")"
    mkdir -p "$sb/outside"; ln -s "$sb/outside" "$src/suites/fx/out"
    out="$(fx_install "$sb" "$src" --harness claude-code)"; code=$?
    assert_exit "src '$bad': exits 1" 1 "$code"
    assert_contains "src '$bad': names the manifest problem" "$out" "manifest"
    assert_missing "src '$bad': nothing placed" "$sb/cwd/.claude/suites"
  done
}
test_manifest_refuses_unsafe_src

test_manifest_refuses_dest_outside_root() {
  _head "a computed destination that escapes the project root is refused"
  local sb src out code
  sb="$(new_sandbox)"; src="$(manifest_fixture "$sb" "$FX_CC")"
  sed -i.bak 's#\.claude/suites/{suite}/agents/{basename}#../{basename}#' "$src/scripts/harnesses.json"
  out="$(fx_install "$sb" "$src" --harness claude-code)"; code=$?
  assert_exit "exits 1" 1 "$code"
  assert_contains "says why" "$out" "unsafe destination"
  assert_missing "nothing escaped" "$sb/a.md"
}
test_manifest_refuses_dest_outside_root

test_manifest_dry_run_writes_nothing() {
  _head "--dry-run on a manifest suite lists the files and writes nothing"
  local sb src out code
  sb="$(new_sandbox)"; src="$(manifest_fixture "$sb" "$FX_CC")"
  out="$(fx_install "$sb" "$src" --harness claude-code --dry-run)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "lists a planned file" "$out" ".claude/suites/fx/agents/a.md"
  assert_missing "no .claude dir created" "$sb/cwd/.claude"
}
test_manifest_dry_run_writes_nothing

test_manifest_suite_dependencies_resolve() {
  _head "a manifest suite's dependencies.json is still honoured"
  local sb src out code
  sb="$(new_sandbox)"; src="$(manifest_fixture "$sb" "$FX_CC")"
  mkdir -p "$src/skills/s1"; printf -- '---\ndescription: d\n---\n' > "$src/skills/s1/SKILL.md"
  printf '["skills/s1"]' > "$src/suites/fx/dependencies.json"
  out="$(fx_install "$sb" "$src" --harness claude-code --yes-deps)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_exists "dependency skill installed" "$sb/cwd/.claude/skills/s1/SKILL.md"
}
test_manifest_suite_dependencies_resolve

# Review round 1 (R1-*): crash, fail-open, symlink, data-loss and guard-parity cases.
test_manifest_config_outside_scope_root_recorded() {
  _head "a config placement outside the scope root (fresh project, no .github/) is placed and recorded"
  local sb src out code
  sb="$(new_sandbox)"
  src="$(manifest_fixture "$sb" '{"copilot":[{"kind":"config","src":"copilot/Makefile","mode":"copy"}]}')"
  out="$(fx_install "$sb" "$src" --harness copilot)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_exists "Makefile placed at the project root" "$sb/cwd/Makefile"
  assert_record "record lists the Makefile, hash matches" "$sb/cwd/.github/.ai-personal-install.json" "$sb/cwd" "$sb/home" 0 1
}
test_manifest_config_outside_scope_root_recorded

test_manifest_bad_resourcekinds_fails_closed() {
  _head "a placement crash refuses the install instead of falling back to the whole-directory copy"
  local sb src out code
  sb="$(new_sandbox)"; src="$(manifest_fixture "$sb" "$FX_CC")"
  python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["claude-code"]["resourceKinds"]["project"]["agents"]=5; json.dump(d,open(p,"w"))' "$src/scripts/harnesses.json"
  out="$(fx_install "$sb" "$src" --harness claude-code)"; code=$?
  assert_exit "exits 1" 1 "$code"
  assert_contains "says placement failed" "$out" "manifest placement failed"
  assert_missing "nothing placed (no wholesale copy)" "$sb/cwd/.claude/suites/fx"
}
test_manifest_bad_resourcekinds_fails_closed

test_manifest_refuses_symlinked_child() {
  _head "a symlinked immediate child of an agents src is refused (dir link and file link)"
  local sb src out code kind
  for kind in dir file; do
    sb="$(new_sandbox)"; src="$(manifest_fixture "$sb" "$FX_CC")"
    if [[ $kind == dir ]]; then
      mkdir -p "$sb/outside"; printf 'KEY\n' > "$sb/outside/id_rsa"; ln -s "$sb/outside" "$src/suites/fx/claude-code/agents/evil"
    else
      ln -s a.md "$src/suites/fx/claude-code/agents/evil.md"
    fi
    out="$(fx_install "$sb" "$src" --harness claude-code)"; code=$?
    assert_exit "$kind link: exits 1" 1 "$code"
    assert_contains "$kind link: says symlink" "$out" "symlink"
    assert_missing "$kind link: nothing placed" "$sb/cwd/.claude/suites/fx"
  done
  # a link nested below a placed directory
  sb="$(new_sandbox)"; src="$(manifest_fixture "$sb" "$FX_CC")"
  mkdir -p "$sb/outside"; ln -s "$sb/outside" "$src/suites/fx/claude-code/.claude-plugin/l"
  out="$(fx_install "$sb" "$src" --harness claude-code)"; code=$?
  assert_exit "nested link: exits 1" 1 "$code"
  assert_missing "nested link: nothing placed" "$sb/cwd/.claude/suites/fx"
}
test_manifest_refuses_symlinked_child

test_manifest_tab_in_src_cannot_shift_columns() {
  _head "a tab in a manifest src is refused; it cannot turn a copy row into an rm -rf of the user's tree"
  local sb src out code
  sb="$(new_sandbox)"
  src="$(manifest_fixture "$sb" "$(printf '{"copilot":[{"kind":"instructions","src":"copilot/notes\\tdocs","mode":"copy"}]}')")"
  printf 'x\n' > "$src/suites/fx/$(printf 'copilot/notes\tdocs')"
  mkdir -p "$sb/cwd/docs"; printf 'MINE\n' > "$sb/cwd/docs/user-file"
  out="$(fx_install "$sb" "$src" --harness copilot --force)"; code=$?
  assert_exit "exits 1" 1 "$code"
  assert_contains "the user's docs/ survives" "$(cat "$sb/cwd/docs/user-file")" "MINE"
}
test_manifest_tab_in_src_cannot_shift_columns

test_manifest_refuses_dest_text_rule() {
  _head "dest text rule matches the record consumer: ~/ only for user scope, no '..' segment anywhere"
  local sb src out code tmpl
  for tmpl in '~/.bashrc.d/{basename}' '.claude/../x/{basename}' '~backup/{basename}'; do
    sb="$(new_sandbox)"; src="$(manifest_fixture "$sb" "$FX_CC")"
    python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["claude-code"]["resourceKinds"]["project"]["agents"]=sys.argv[2]; json.dump(d,open(p,"w"))' "$src/scripts/harnesses.json" "$tmpl"
    out="$(fx_install "$sb" "$src" --harness claude-code)"; code=$?
    assert_exit "project template '$tmpl': exits 1" 1 "$code"
    assert_contains "project template '$tmpl': says why" "$out" "unsafe destination"
    assert_missing "project template '$tmpl': nothing in HOME" "$sb/home/.bashrc.d"
  done
  sb="$(new_sandbox)"; src="$(manifest_fixture "$sb" "$FX_CC")"
  python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["claude-code"]["resourceKinds"]["user"]["agents"]="agents/{basename}"; json.dump(d,open(p,"w"))' "$src/scripts/harnesses.json"
  out="$(fx_install "$sb" "$src" --harness claude-code --scope user)"; code=$?
  assert_exit "user template without ~/: exits 1" 1 "$code"
  assert_missing "user template without ~/: nothing written to the project" "$sb/cwd/agents"
}
test_manifest_refuses_dest_text_rule

test_manifest_requested_suite_without_mapping() {
  _head "a harness with resourceKinds but no mapping.suites still places a requested manifest suite"
  local sb src out code
  sb="$(new_sandbox)"
  src="$(manifest_fixture "$sb" '{"h2":[{"kind":"agents","src":"claude-code/agents","mode":"copy"}]}')"
  printf '{"h2":{"label":"H2","scopes":{"project":".h2"},"mapping":{"skills":"skills/{name}"},"resourceKinds":{"project":{"agents":".h2/agents/{basename}"}}}}' > "$src/scripts/harnesses.json"
  out="$(fx_install "$sb" "$src" --harness h2)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_exists "manifest file placed" "$sb/cwd/.h2/agents/a.md"
  assert_missing "no wholesale copy" "$sb/cwd/.h2/suites"
}
test_manifest_requested_suite_without_mapping

test_manifest_dest_leaf_symlink_or_dir_skipped_even_with_force() {
  _head "a destination leaf that is a symlink or a directory is skipped even with --force"
  local sb src out d
  sb="$(new_sandbox)"; src="$(manifest_fixture "$sb" "$FX_CC")"; d="$sb/cwd/.claude/suites/fx/agents"
  mkdir -p "$d/b.md/keep"; printf 'TARGET\n' > "$sb/target"; ln -s "$sb/target" "$d/a.md"
  out="$(fx_install "$sb" "$src" --harness claude-code --force)"
  assert_contains "symlink target unchanged" "$(cat "$sb/target")" "TARGET"
  [[ -L "$d/a.md" ]] && _ok "the link is still a link" || _fail "the link is still a link"
  assert_exists "directory dest not removed" "$d/b.md/keep"
  assert_contains "says not a regular file" "$out" "not a regular file"
  out="$(fx_install "$sb" "$src" --harness claude-code --force --dry-run | grep 'agents/b.md')"
  assert_not_contains "dry run does not promise --force will replace a directory" "$out" "use --force"
}
test_manifest_dest_leaf_symlink_or_dir_skipped_even_with_force

test_manifest_parent_is_file_skips_not_aborts() {
  _head "a regular file in the way of a destination parent skips that file, not the whole install"
  local sb src out code d
  sb="$(new_sandbox)"; src="$(manifest_fixture "$sb" "$FX_CC")"; d="$sb/cwd/.claude/suites/fx"
  mkdir -p "$d"; printf 'x\n' > "$d/agents"
  out="$(fx_install "$sb" "$src" --harness claude-code)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "says why" "$out" "parent is not a directory"
  assert_exists "other placements still land" "$d/.claude-plugin/plugin.json"
}
test_manifest_parent_is_file_skips_not_aborts

test_manifest_unwritable_parent_fails_closed() {
  _head "an unwritable destination parent fails the install; it is not reported as 'parent is not a directory'"
  local sb src out code rec
  if [[ "$(id -u)" == 0 ]]; then _skip "running as root: chmod can't block mkdir"; return; fi
  sb="$(new_sandbox)"; src="$(manifest_fixture "$sb" "$FX_CC")"; rec="$sb/cwd/.claude/.ai-personal-install.json"
  mkdir -p "$sb/cwd/.claude/suites"; chmod 555 "$sb/cwd/.claude/suites"
  out="$(fx_install "$sb" "$src" --harness claude-code)"; code=$?
  chmod -R u+w "$sb/cwd/.claude"
  assert_exit "exits 1" 1 "$code"
  assert_not_contains "not mislabelled as a non-directory parent" "$out" "parent is not a directory"
  assert_missing "nothing placed" "$sb/cwd/.claude/suites/fx"
  assert_missing "nothing recorded" "$rec"
}
test_manifest_unwritable_parent_fails_closed

test_manifest_dry_run_merge_row_over_existing_file() {
  _head "a dry-run merge row over an existing file says merge leaves it untouched, not 'use --force'"
  local sb src out
  sb="$(new_sandbox)"
  src="$(manifest_fixture "$sb" '{"copilot":[{"kind":"instructions","src":"copilot/.github/copilot-instructions.md","mode":"merge"}]}')"
  mkdir -p "$sb/cwd/.github"; printf 'MINE\n' > "$sb/cwd/.github/copilot-instructions.md"
  out="$(fx_install "$sb" "$src" --harness copilot --dry-run)"
  assert_contains "says merge leaves it untouched" "$out" "merge would leave it untouched"
  assert_not_contains "does not promise --force" "$out" "use --force"
}
test_manifest_dry_run_merge_row_over_existing_file

test_manifest_empty_placement_list_is_a_skip() {
  _head "a manifest that keys the harness with no placements is noted, not silently dropped"
  local sb src out code
  sb="$(new_sandbox)"; src="$(manifest_fixture "$sb" '{"claude-code":[]}')"
  out="$(fx_install "$sb" "$src" --harness claude-code)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "notes the skip" "$out" "manifest has no placements for harness 'claude-code' — skipped"
  assert_missing "nothing placed" "$sb/cwd/.claude/suites/fx"
}
test_manifest_empty_placement_list_is_a_skip

test_manifest_instructions_needs_file_src() {
  _head "an instructions placement with a directory src is refused"
  local sb src out code
  sb="$(new_sandbox)"
  src="$(manifest_fixture "$sb" '{"copilot":[{"kind":"instructions","src":"copilot/scripts","mode":"copy"}]}')"
  out="$(fx_install "$sb" "$src" --harness copilot)"; code=$?
  assert_exit "exits 1" 1 "$code"
  assert_missing "nothing placed" "$sb/cwd/.github/copilot-instructions.md"
}
test_manifest_instructions_needs_file_src

test_manifest_dependency_messages_once_per_asset() {
  _head "a manifest suite is named once, not once per file, in dependency messages"
  local sb src out code
  sb="$(new_sandbox)"; src="$(manifest_fixture "$sb" "$FX_CC")"
  mkdir -p "$src/skills/s1"; printf -- '---\ndescription: d\n---\n' > "$src/skills/s1/SKILL.md"
  printf '["suites/fx"]' > "$src/skills/s1/dependencies.json"
  out="$(fx_install "$sb" "$src" --harness claude-code --assets skills --no-deps)"
  assert_contains "names the suite" "$out" "suites/fx"
  assert_not_contains "suite listed once, not once per file" "$out" "suites/fx suites/fx"
}
test_manifest_dependency_messages_once_per_asset

# merge placements (ADR-0013): create missing files, never touch an existing one without --force.
MG_M='{"copilot":[{"kind":"instructions","src":"copilot/.github/copilot-instructions.md","mode":"merge"},{"kind":"config","src":"copilot/scripts","mode":"merge"}]}'
mg_fixture() { # <sandbox>: merge fixture with two extra scripts
  local src; src="$(manifest_fixture "$1" "$MG_M")"
  printf 'one\n' > "$src/suites/fx/copilot/scripts/one.sh"; printf 'two\n' > "$src/suites/fx/copilot/scripts/two.sh"
  printf '%s' "$src"
}

test_merge_creates_missing_files_in_fresh_project() {
  _head "merge into a fresh project creates the files and their parents"
  local sb src out code
  sb="$(new_sandbox)"; src="$(mg_fixture "$sb")"
  out="$(fx_install "$sb" "$src" --harness copilot)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_exists "instructions created with parent" "$sb/cwd/.github/copilot-instructions.md"
  assert_exists "script created with parent" "$sb/cwd/scripts/one.sh"
  assert_not_contains "no skip summary when nothing was skipped" "$out" "left existing"
}
test_merge_creates_missing_files_in_fresh_project

test_merge_leaves_existing_files_and_lists_them_once() {
  _head "merge leaves existing files untouched and lists them once at the end"
  local sb src out n
  sb="$(new_sandbox)"; src="$(mg_fixture "$sb")"
  mkdir -p "$sb/cwd/scripts" "$sb/cwd/.github"
  printf 'MINE1\n' > "$sb/cwd/scripts/one.sh"; printf 'MINE2\n' > "$sb/cwd/scripts/two.sh"
  printf 'MINE3\n' > "$sb/cwd/.github/copilot-instructions.md"
  out="$(fx_install "$sb" "$src" --harness copilot)"
  assert_contains "one.sh untouched" "$(cat "$sb/cwd/scripts/one.sh")" "MINE1"
  assert_contains "instructions untouched" "$(cat "$sb/cwd/.github/copilot-instructions.md")" "MINE3"
  assert_exists "the missing file is still created" "$sb/cwd/scripts/run.sh"
  assert_contains "summary names a skipped file" "$out" "scripts/two.sh"
  printf 'sp\n' > "$src/suites/fx/copilot/scripts/my file.sh"; printf 'MINE4\n' > "$sb/cwd/scripts/my file.sh"
  out="$(fx_install "$sb" "$src" --harness copilot)"
  assert_contains "a path with a space is on its own line" "$(printf '%s\n' "$out" | grep -c '^ *scripts/my file.sh$')" "1"
  assert_contains "another kept file is on its own line" "$(printf '%s\n' "$out" | grep -c '^ *scripts/two.sh$')" "1"
  n="$(printf '%s\n' "$out" | grep -c "left existing")"
  [[ "$n" == 1 ]] && _ok "summary line appears exactly once" || _fail "summary line count: $n"
}
test_merge_leaves_existing_files_and_lists_them_once

test_merge_force_overwrites_per_file_only() {
  _head "merge --force overwrites that file per file; a user's extra file survives"
  local sb src out
  sb="$(new_sandbox)"; src="$(mg_fixture "$sb")"
  mkdir -p "$sb/cwd/scripts"; printf 'MINE\n' > "$sb/cwd/scripts/one.sh"; printf 'EXTRA\n' > "$sb/cwd/scripts/user.sh"
  out="$(fx_install "$sb" "$src" --harness copilot --force)"
  assert_contains "existing file overwritten" "$(cat "$sb/cwd/scripts/one.sh")" "one"
  assert_not_contains "overwritten, so no skip summary" "$out" "left existing"
  assert_contains "user's extra file survives" "$(cat "$sb/cwd/scripts/user.sh")" "EXTRA"
}
test_merge_force_overwrites_per_file_only

test_merge_record_has_created_not_skipped() {
  _head "created merge files are recorded with matching sha256; skipped ones are not"
  local sb src rec files
  sb="$(new_sandbox)"; src="$(mg_fixture "$sb")"; rec="$sb/cwd/.github/.ai-personal-install.json"
  mkdir -p "$sb/cwd/scripts"; printf 'MINE\n' > "$sb/cwd/scripts/one.sh"
  fx_install "$sb" "$src" --harness copilot >/dev/null
  assert_record "record hashes match, 3 files (4 placed minus 1 skipped)" "$rec" "$sb/cwd" "$sb/home" 0 3
  files="$(record_json "$rec" 'sorted(d["assets"]["suites/fx"]["files"])')"
  assert_not_contains "skipped file not recorded" "$files" "one.sh"
  assert_contains "created file recorded" "$files" "two.sh"
}
test_merge_record_has_created_not_skipped

test_merge_dir_or_symlink_dest_skipped() {
  _head "a merge destination that is a directory or symlink is skipped"
  local sb src out
  sb="$(new_sandbox)"; src="$(mg_fixture "$sb")"
  mkdir -p "$sb/cwd/scripts/one.sh" "$sb/outside"; printf 'KEEP\n' > "$sb/outside/t"
  ln -s "$sb/outside/t" "$sb/cwd/scripts/two.sh"
  out="$(fx_install "$sb" "$src" --harness copilot --force)"
  assert_contains "notes not a regular file" "$out" "not a regular file"
  assert_exists "directory dest left in place" "$sb/cwd/scripts/one.sh"
  assert_contains "symlink target untouched" "$(cat "$sb/outside/t")" "KEEP"
  assert_exists "other files still created" "$sb/cwd/scripts/run.sh"
}
test_merge_dir_or_symlink_dest_skipped

test_merge_dry_run_lists_create_vs_skip() {
  _head "merge --dry-run lists create vs skip and writes nothing"
  local sb src out
  sb="$(new_sandbox)"; src="$(mg_fixture "$sb")"
  mkdir -p "$sb/cwd/scripts"; printf 'MINE\n' > "$sb/cwd/scripts/one.sh"
  out="$(fx_install "$sb" "$src" --harness copilot --dry-run)"
  assert_contains "skip listed" "$out" "scripts/one.sh  (exists, merge would leave it untouched)"
  assert_contains "create listed" "$out" "scripts/two.sh"
  assert_not_contains "no skip note on the create line" "$(printf '%s\n' "$out" | grep 'two.sh')" "exists"
  assert_missing "nothing written" "$sb/cwd/scripts/two.sh"
  assert_missing "no record written" "$sb/cwd/.github/.ai-personal-install.json"
  assert_contains "existing file untouched" "$(cat "$sb/cwd/scripts/one.sh")" "MINE"
}
test_merge_dry_run_lists_create_vs_skip

test_merge_dry_run_force_says_overwrite() {
  _head "merge --dry-run --force says would overwrite, matching the real run"
  local sb src out
  sb="$(new_sandbox)"; src="$(mg_fixture "$sb")"
  mkdir -p "$sb/cwd/scripts"; printf 'MINE\n' > "$sb/cwd/scripts/one.sh"
  out="$(fx_install "$sb" "$src" --harness copilot --dry-run --force)"
  assert_contains "says would overwrite" "$out" "scripts/one.sh  (exists, would overwrite)"
  assert_not_contains "no would-skip on that line" "$(printf '%s\n' "$out" | grep 'one.sh')" "would skip"
  assert_contains "file untouched" "$(cat "$sb/cwd/scripts/one.sh")" "MINE"
}
test_merge_dry_run_force_says_overwrite

# tier-layered-teams through its real manifest.json (ADR-0008, first migrated suite).
# tlt_src <sandbox>: a minimal source (real catalog.sh, harnesses.json and the real suite) so only this suite installs.
tlt_src() {
  local src="$1/tlt_src"
  mkdir -p "$src/scripts" "$src/suites"
  cp "$REPO/scripts/catalog.sh" "$REPO/scripts/harnesses.json" "$src/scripts/"
  cp -R "$REPO/suites/tier-layered-teams" "$src/suites/"
  printf '%s' "$src"
}
tlt_install() { # <sandbox> <args...>: project scope unless --scope is passed
  local sb="$1"; shift
  ( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" bash "$INSTALL" --local "$sb/tlt_src" --assets suites "$@" ) 2>&1 </dev/null
}
# tlt_payload_diff <target>: lists every file of the copilot payload (what cp -R would put there) that is missing, differs or has another exec bit.
tlt_payload_diff() {
  local f
  ( cd "$REPO/suites/tier-layered-teams/copilot" && find . -type f | sort ) | while IFS= read -r f; do
    if [[ ! -f "$1/$f" ]]; then echo "missing $f"
    elif ! cmp -s "$REPO/suites/tier-layered-teams/copilot/$f" "$1/$f"; then echo "differs $f"
    elif [[ "$([[ -x "$REPO/suites/tier-layered-teams/copilot/$f" ]] && echo x)" != "$([[ -x "$1/$f" ]] && echo x)" ]]; then echo "mode $f"
    fi
  done
}

test_tlt_copilot_places_the_cp_r_payload() {
  _head "tier-layered-teams on copilot places exactly what cp -R of copilot/ places, and records it"
  local sb out code ref
  sb="$(new_sandbox)"; tlt_src "$sb" >/dev/null; ref="$sb/ref"; mkdir -p "$ref"
  cp -R "$REPO/suites/tier-layered-teams/copilot/." "$ref/"
  out="$(tlt_install "$sb" --harness copilot --scope project)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_exit "same file list as cp -R" 0 "$([[ "$(cd "$sb/cwd" && find . -type f ! -name .ai-personal-install.json | sort)" == "$(cd "$ref" && find . -type f | sort)" ]]; echo $?)"
  assert_exit "30 files placed" 30 "$(cd "$sb/cwd" && find . -type f ! -name .ai-personal-install.json | wc -l | tr -d ' ')"
  assert_exit "bytes and exec bits match cp -R" 0 "$(tlt_payload_diff "$sb/cwd" | wc -l | tr -d ' ')"
  [[ -x "$sb/cwd/.github/skills/astgrep-rewrite/scripts/preview-rewrite.sh" && -x "$sb/cwd/scripts/preflight.sh" ]] && _ok "scripts stay executable" || _fail "scripts stay executable"
  assert_missing "suite-root docs are not placed" "$sb/cwd/PROTOCOL.md"
  assert_missing "no suites/ copy under .github" "$sb/cwd/.github/suites"
  assert_record "record lists all 30 files, hashes match" "$sb/cwd/.github/.ai-personal-install.json" "$sb/cwd" "$sb/home" 0 30
}
test_tlt_copilot_places_the_cp_r_payload

test_tlt_copilot_second_run_touches_nothing() {
  _head "a second copilot install leaves everything untouched: per-file skips, one merge summary"
  local sb out before
  sb="$(new_sandbox)"; tlt_src "$sb" >/dev/null
  tlt_install "$sb" --harness copilot --scope project >/dev/null
  before="$(cd "$sb/cwd" && find . -type f ! -name .ai-personal-install.json -exec shasum {} + | sort)"
  out="$(tlt_install "$sb" --harness copilot --scope project)"
  assert_exit "no file changed" 0 "$([[ "$before" == "$(cd "$sb/cwd" && find . -type f ! -name .ai-personal-install.json -exec shasum {} + | sort)" ]]; echo $?)"
  assert_exit "15 copy files each get a skip note" 15 "$(printf '%s\n' "$out" | grep -c 'skip (exists)')"
  assert_exit "one merge summary" 1 "$(printf '%s\n' "$out" | grep -c 'left existing')"
  assert_contains "merge summary names a merge file" "$out" "Makefile"
  assert_record "record still lists the 30 files, hashes match" "$sb/cwd/.github/.ai-personal-install.json" "$sb/cwd" "$sb/home" 0 30
}
test_tlt_copilot_second_run_touches_nothing

test_tlt_copilot_user_owned_files_untouched() {
  _head "a project's own Makefile, .gitignore and .vscode/settings.json are left untouched and listed"
  local sb out
  sb="$(new_sandbox)"; tlt_src "$sb" >/dev/null; mkdir -p "$sb/cwd/.vscode"
  printf 'MINE-M\n' > "$sb/cwd/Makefile"; printf 'MINE-G\n' > "$sb/cwd/.gitignore"; printf 'MINE-S\n' > "$sb/cwd/.vscode/settings.json"
  out="$(tlt_install "$sb" --harness copilot --scope project)"
  assert_contains "Makefile untouched" "$(cat "$sb/cwd/Makefile")" "MINE-M"
  assert_contains ".gitignore untouched" "$(cat "$sb/cwd/.gitignore")" "MINE-G"
  assert_contains "settings.json untouched" "$(cat "$sb/cwd/.vscode/settings.json")" "MINE-S"
  assert_contains "Makefile listed" "$(printf '%s\n' "$out" | grep -c '^ *Makefile$')" "1"
  assert_contains ".gitignore listed" "$(printf '%s\n' "$out" | grep -c '^ *\.gitignore$')" "1"
  assert_contains "settings.json listed" "$(printf '%s\n' "$out" | grep -c '^ *\.vscode/settings\.json$')" "1"
  assert_exists "the other .vscode files are still created" "$sb/cwd/.vscode/tasks.json"
  assert_record "record has 27 files; the 3 user files are not in it" "$sb/cwd/.github/.ai-personal-install.json" "$sb/cwd" "$sb/home" 0 27
}
test_tlt_copilot_user_owned_files_untouched

test_tlt_claude_code_places_plugin_only() {
  _head "tier-layered-teams on claude-code places the plugin (agents + plugin.json) and no copilot/ variant"
  local sb out d rec
  sb="$(new_sandbox)"; tlt_src "$sb" >/dev/null; d="$sb/cwd/.claude/suites/tier-layered-teams"; rec="$sb/cwd/.claude/.ai-personal-install.json"
  out="$(tlt_install "$sb" --harness claude-code --scope project)"
  assert_exit "8 agent files" 8 "$(ls "$d/agents" | wc -l | tr -d ' ')"
  assert_exists "plugin.json beside agents/" "$d/.claude-plugin/plugin.json"
  assert_exit "only agents/ and .claude-plugin/ placed" 9 "$(find "$d" -type f | wc -l | tr -d ' ')"
  assert_missing "no copilot/ directory" "$d/copilot"
  assert_missing "no claude-code/ directory" "$d/claude-code"
  assert_missing "suite-root docs not placed" "$d/PROTOCOL.md"
  assert_missing "no manifest copied" "$d/manifest.json"
  assert_record "record lists the 9 files, hashes match" "$rec" "$sb/cwd" "$sb/home" 0 9
  tlt_install "$sb" --harness claude-code --scope project >/dev/null
  assert_exit "re-install keeps the 9 files" 9 "$(find "$d" -type f | wc -l | tr -d ' ')"
}
test_tlt_claude_code_places_plugin_only

test_tlt_claude_code_user_scope() {
  _head "tier-layered-teams on claude-code user scope lands under ~/.claude/suites"
  local sb d
  sb="$(new_sandbox)"; tlt_src "$sb" >/dev/null; d="$sb/home/.claude/suites/tier-layered-teams"
  tlt_install "$sb" --harness claude-code --scope user >/dev/null
  assert_exists "agent under ~/.claude" "$d/agents/01-core-orchestrator.md"
  assert_exists "plugin.json under ~/.claude" "$d/.claude-plugin/plugin.json"
  assert_missing "cwd untouched" "$sb/cwd/.claude"
  assert_record "user-scope record matches" "$sb/home/.claude/.ai-personal-install.json" "$sb/cwd" "$sb/home" 0 9
}
test_tlt_claude_code_user_scope

test_tlt_force_restores_exec_bit() {
  _head "--force over a user's non-executable scripts/preflight.sh leaves the payload's exec bit"
  local sb
  sb="$(new_sandbox)"; tlt_src "$sb" >/dev/null; mkdir -p "$sb/cwd/scripts"
  printf 'MINE\n' > "$sb/cwd/scripts/preflight.sh"; chmod 644 "$sb/cwd/scripts/preflight.sh"
  tlt_install "$sb" --harness copilot --scope project --force >/dev/null
  assert_exit "content overwritten" 0 "$(cmp -s "$sb/cwd/scripts/preflight.sh" "$REPO/suites/tier-layered-teams/copilot/scripts/preflight.sh"; echo $?)"
  [[ -x "$sb/cwd/scripts/preflight.sh" ]] && _ok "exec bit is the payload's, not the old file's mode" || _fail "preflight.sh stayed non-executable after --force"
}
test_tlt_force_restores_exec_bit

# ── --uninstall (ADR-0012 "Consumers MUST") ─────────────────────────────────────
# run_uninstall <sandbox> <args...>: --uninstall against this checkout (--local, never the network).
run_uninstall() {
  local sandbox="$1"; shift
  ( cd "$sandbox/cwd" && HOME="$sandbox/home" PATH="$sandbox/bin:$PATH" bash "$INSTALL" --local "$REPO" --uninstall "$@" )
}
# count_files <dir>: regular files and symlinks under <dir>.
count_files() { find "$1" \( -type f -o -type l \) 2>/dev/null | wc -l | tr -d ' '; }
# rec_edit <record> <python statement on d> [arg]: rewrites the record in place; the arg is sys.argv[3].
rec_edit() { python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); exec(sys.argv[2]); json.dump(d,open(p,"w"))' "$@"; }

test_uninstall_round_trip() {
  _head "--uninstall after an install leaves no installed file and no record"
  local sb out code hs h s base
  for hs in "claude-code project cwd" "claude-code user home" "copilot project cwd"; do
    read -r h s base <<< "$hs"
    sb="$(new_sandbox)"
    run_install "$sb" --harness "$h" --scope "$s" --yes-deps </dev/null >/dev/null 2>&1
    rm "$(find "$sb/$base" -name USAGE.md | head -1)"   # already gone: forgotten, not an error
    stub_curl "$sb"   # uninstall fetches harnesses.json like install, so --ref is allowed
    out="$( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
      bash "$INSTALL" --uninstall --harness "$h" --scope "$s" --ref v1 </dev/null 2>&1 )"; code=$?
    assert_exit "$h/$s: exits 0" 0 "$code"
    assert_contains "$h/$s: lists what it removed" "$out" "removed"
    assert_exit "$h/$s: no file left" 0 "$(count_files "$sb/$base")"
    assert_exit "$h/$s: empty dirs pruned up to the scope root, which stays" 1 "$(find "$sb/$base" -mindepth 1 -type d | wc -l | tr -d ' ')"
    assert_contains "$h/$s: fetched the pinned tree (stubbed curl)" "$(cat "$sb/curl.args" 2>&1)" "codeload.github.com/jean-tessier/ai-personal/tar.gz/v1"
  done
}

test_uninstall_reads_only_the_scope_root_record() {
  _head "--uninstall reads only <scope root>/.ai-personal-install.json"
  local sb out code n rec
  # a user-scope record one level below \$HOME is not the scope root's record
  sb="$(new_sandbox)"; printf 'mine\n' > "$sb/home/victim"; mkdir "$sb/home/cloned"
  python3 -c 'import hashlib,json,sys; h=hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest(); json.dump({"version":1,"harness":"claude-code","scope":"user","assets":{"skills/x":{"files":{"~/victim":"sha256:"+h}}}},open(sys.argv[2],"w"))' \
    "$sb/home/victim" "$sb/home/cloned/.ai-personal-install.json"
  out="$(run_uninstall "$sb" --harness claude-code --scope user </dev/null 2>&1)"; code=$?
  assert_exit "no record at the scope root: exits 0" 0 "$code"
  assert_contains "no record at the scope root: says so" "$out" "no install record at"
  assert_exists "a record elsewhere under \$HOME is not used" "$sb/home/victim"
  # a symlink to a sibling project's scope root is never followed out of \$PWD
  sb="$(new_sandbox)"; mkdir "$sb/other"
  ( cd "$sb/other" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
    bash "$INSTALL" --local "$REPO" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1 )
  n="$(count_files "$sb/other")"
  ln -s ../other/.claude "$sb/cwd/evil"
  out="$(run_uninstall "$sb" --harness claude-code --scope project </dev/null 2>&1)"; code=$?
  assert_exit "sibling via another name: exits 0" 0 "$code"
  assert_exit "sibling via another name: nothing deleted outside \$PWD" "$n" "$(count_files "$sb/other")"
  rm "$sb/cwd/evil"; ln -s ../other/.claude "$sb/cwd/.claude"
  out="$(run_uninstall "$sb" --harness claude-code --scope project --force </dev/null 2>&1)"; code=$?
  assert_exit "sibling as the scope root: exits 1" 1 "$code"
  assert_contains "sibling as the scope root: says why" "$out" "outside"
  assert_exit "sibling as the scope root: nothing deleted outside \$PWD" "$n" "$(count_files "$sb/other")"
  # a corrupt real record is refused even when another record exists; a valid one ignores the other
  sb="$(new_sandbox)"; rec="$sb/cwd/.claude/.ai-personal-install.json"
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  mkdir "$sb/cwd/vendor"; cp "$rec" "$sb/cwd/vendor/.ai-personal-install.json"; cp "$rec" "$sb/good.json"
  { printf '<<<<<<< HEAD\n'; cat "$sb/good.json"; } > "$rec"
  n="$(count_files "$sb/cwd")"
  out="$(run_uninstall "$sb" --harness claude-code --scope project </dev/null 2>&1)"; code=$?
  assert_exit "corrupt record: exits 1" 1 "$code"
  assert_contains "corrupt record: says why" "$out" "not valid JSON"
  assert_exit "corrupt record: nothing deleted" "$n" "$(count_files "$sb/cwd")"
  cp "$sb/good.json" "$rec"
  out="$(run_uninstall "$sb" --harness claude-code --scope project </dev/null 2>&1)"; code=$?
  assert_exit "second record elsewhere: exits 0" 0 "$code"
  assert_exit "second record elsewhere: everything installed removed, that record kept" 1 "$(count_files "$sb/cwd")"
  cmp -s "$sb/good.json" "$sb/cwd/vendor/.ai-personal-install.json" && _ok "second record elsewhere: untouched" || _fail "second record elsewhere: untouched"
}

test_uninstall_keeps_modified_asset_and_user_files() {
  _head "--uninstall keeps a modified asset whole; --force lists it, then deletes it"
  local sb out code d rec
  sb="$(new_sandbox)"; d="$sb/cwd/.claude/skills"; rec="$sb/cwd/.claude/.ai-personal-install.json"
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  printf 'edit\n' >> "$d/atomic-commits/SKILL.md"
  printf 'mine\n' > "$d/plan-dag/MINE.md"
  printf 'PRECIOUS\n' > "$sb/precious"; ln -s "$sb/precious" "$rec.tmp"   # a planted temp link is never followed
  out="$(run_uninstall "$sb" --harness claude-code --scope project </dev/null 2>&1)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "the planted temp link's target is untouched" "$(cat "$sb/precious")" "PRECIOUS"
  assert_missing "the record is rewritten through a fresh temp file" "$rec.tmp"
  assert_contains "names the modified file" "$out" "modified: .claude/skills/atomic-commits/SKILL.md"
  assert_exists "the modified file is kept" "$d/atomic-commits/SKILL.md"
  assert_exists "the rest of that asset is kept too" "$d/atomic-commits/USAGE.md"
  assert_missing "an unmodified asset is removed" "$d/plan-dag/SKILL.md"
  assert_exists "a user-added file in an asset dir survives, so its dir is not pruned" "$d/plan-dag/MINE.md"
  assert_contains "the record keeps only the kept asset" "$(record_json "$rec" 'sorted(d["assets"])')" "['skills/atomic-commits']"
  out="$(run_uninstall "$sb" --harness claude-code --scope project --force </dev/null 2>&1)"; code=$?
  assert_exit "--force: exits 0" 0 "$code"
  assert_contains "--force: lists the modified path before deleting anything" "${out%%removed*}" "atomic-commits/SKILL.md"
  assert_missing "--force: the modified asset is removed" "$d/atomic-commits"
  assert_missing "--force: the emptied record is deleted" "$rec"
  assert_exists "--force: the user-added file still survives" "$d/plan-dag/MINE.md"
}

test_uninstall_path_guards_abort_before_deleting() {
  _head "--uninstall aborts on any unsafe recorded path, deleting nothing"
  local sb out code rec n bad
  sb="$(new_sandbox)"; rec="$sb/cwd/.claude/.ai-personal-install.json"
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  mkdir "$sb/outside"; printf 'PRECIOUS\n' > "$sb/outside/f"; ln -s "$sb/outside" "$sb/cwd/.claude/esc"
  mkdir "$sb/cwd/.git"; printf 'ref: refs/heads/main\n' > "$sb/cwd/.git/HEAD"; ln -s .git "$sb/cwd/glink"
  cp "$rec" "$sb/pristine.json"; n="$(count_files "$sb/cwd")"
  for bad in "$sb/outside/f" '' '.claude/../../outside/f' '.claude/./x' '.claude//x' '.claude\x' '~/x' '.claude/esc/f' \
      $'.claude/a\e[2K' '.claude/a<NUL>b' '.claude/a<RLO>dm.LLIKS' '.git/HEAD' '.GIT/HEAD' 'glink/HEAD'; do
    cp "$sb/pristine.json" "$rec"
    rec_edit "$rec" 'd["assets"]["skills/zz"]={"files":{sys.argv[3].replace("<NUL>","\0").replace("<RLO>","‮"):"sha256:0"}}' "$bad"
    out="$(run_uninstall "$sb" --harness claude-code --scope project --force </dev/null 2>&1)"; code=$?
    assert_exit "path '$bad': exits 1" 1 "$code"
    assert_contains "path '$bad': says why" "$out" "unsafe path"
    assert_not_contains "path '$bad': no traceback" "$out" "Traceback"
    [[ "$out" != *$'\e[2K'* && "$out" != *"$(printf '\342\200\256')"* ]] && _ok "path '$bad': no raw escape printed" || _fail "path '$bad': no raw escape printed"
    assert_exit "path '$bad': nothing deleted" "$n" "$(count_files "$sb/cwd")"
  done
  assert_contains "the escape target is untouched" "$(cat "$sb/outside/f")" "PRECIOUS"
  cp "$sb/pristine.json" "$rec"
  rec_edit "$rec" 'a=d["assets"]; a["skills/x\x1b[2K"]=a.pop("skills/atomic-commits")'
  out="$(run_uninstall "$sb" --harness claude-code --scope project --force </dev/null 2>&1)"; code=$?
  assert_exit "control character in an asset name: exits 1" 1 "$code"
  assert_contains "control character in an asset name: says why" "$out" "unsafe asset name"
  assert_exit "control character in an asset name: nothing deleted" "$n" "$(count_files "$sb/cwd")"
  sb="$(new_sandbox)"; rec="$sb/home/.claude/.ai-personal-install.json"
  run_install "$sb" --harness claude-code --scope user --assets skills </dev/null >/dev/null 2>&1
  rec_edit "$rec" 'd["assets"]["skills/zz"]={"files":{".claude/x":"sha256:0"}}'
  n="$(count_files "$sb/home")"
  out="$(run_uninstall "$sb" --harness claude-code --scope user </dev/null 2>&1)"; code=$?
  assert_exit "user scope, path not ~/-anchored: exits 1" 1 "$code"
  assert_exit "user scope, path not ~/-anchored: nothing deleted" "$n" "$(count_files "$sb/home")"
  # user-scope paths are confined to the scope root, even with the right hashes
  mkdir "$sb/home/.ssh"; printf 'alias x=y\n' > "$sb/home/.zshrc"; printf 'KEY\n' > "$sb/home/.ssh/id_ed25519"
  rec_edit "$rec" 'import hashlib,os; h=lambda f: "sha256:"+hashlib.sha256(open(os.path.join(sys.argv[3],f),"rb").read()).hexdigest(); d["assets"]["skills/zz"]={"files":{"~/"+f:h(f) for f in (".zshrc",".ssh/id_ed25519")}}' "$sb/home"
  n="$(count_files "$sb/home")"
  out="$(run_uninstall "$sb" --harness claude-code --scope user </dev/null 2>&1)"; code=$?
  assert_exit "user scope, path outside the scope root: exits 1" 1 "$code"
  assert_contains "user scope, path outside the scope root: says why" "$out" "outside the scope root"
  assert_exit "user scope, path outside the scope root: nothing deleted" "$n" "$(count_files "$sb/home")"
  # .GIT through a symlinked .git resolves elsewhere: only the case-insensitive text rule sees it
  sb="$(new_sandbox)"; mkdir -p "$sb/cwd/.claude" "$sb/cwd/gitdir"; printf 'ref\n' > "$sb/cwd/gitdir/HEAD"; ln -s gitdir "$sb/cwd/.git"
  printf '{"version":1,"harness":"claude-code","scope":"project","assets":{"skills/zz":{"files":{".GIT/HEAD":"sha256:0"}}}}' \
    > "$sb/cwd/.claude/.ai-personal-install.json"
  out="$(run_uninstall "$sb" --harness claude-code --scope project --force </dev/null 2>&1)"; code=$?
  assert_exit "'.GIT/HEAD' via a symlinked .git: exits 1" 1 "$code"
  assert_exists "'.GIT/HEAD' via a symlinked .git: nothing deleted" "$sb/cwd/gitdir/HEAD"
}

# write_rec <out> <harness> <scope> <base> <key prefix> <file...>: a one-asset record listing each
# file (relative to <base>) under "<key prefix><file>" with its real sha256.
write_rec() {
  python3 -c 'import hashlib,json,os,sys; o,h,s,b,p=sys.argv[1:6]; json.dump({"version":1,"harness":h,"scope":s,"assets":{"skills/zz":{"files":{p+f:"sha256:"+hashlib.sha256(open(os.path.join(b,f),"rb").read()).hexdigest() for f in sys.argv[6:]}}}},open(o,"w"))' "$@"
}

test_uninstall_confined_when_the_record_is_in_home() {
  _head "--uninstall confines every record read from \$HOME to its scope root"
  local sb out code n src
  # a project-scope record read from $HOME is confined like a user-scope one
  sb="$(new_sandbox)"; mkdir -p "$sb/home/.claude" "$sb/home/.ssh"
  printf 'alias x=y\n' > "$sb/home/.zshrc"; printf 'KEY\n' > "$sb/home/.ssh/id_ed25519"
  write_rec "$sb/home/.claude/.ai-personal-install.json" claude-code project "$sb/home" "" .zshrc .ssh/id_ed25519
  n="$(count_files "$sb/home")"
  out="$( cd "$sb/home" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
    bash "$INSTALL" --local "$REPO" --uninstall --harness claude-code --scope project </dev/null 2>&1 )"; code=$?
  assert_exit "project scope from \$HOME: exits 1" 1 "$code"
  assert_contains "project scope from \$HOME: says why" "$out" "outside the scope root"
  assert_exit "project scope from \$HOME: nothing deleted" "$n" "$(count_files "$sb/home")"
  # a real project install made from $HOME still round-trips
  sb="$(new_sandbox)"
  ( cd "$sb/home" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
    bash "$INSTALL" --local "$REPO" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1 )
  out="$( cd "$sb/home" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
    bash "$INSTALL" --local "$REPO" --uninstall --harness claude-code --scope project </dev/null 2>&1 )"; code=$?
  assert_exit "project install from \$HOME: uninstall exits 0" 0 "$code"
  assert_exit "project install from \$HOME: no file left" 0 "$(count_files "$sb/home")"
  # a scope root that is $HOME itself (a hostile harnesses.json) confines nothing, so it is refused
  sb="$(new_sandbox)"; src="$sb/fake_src"; mkdir -p "$src/scripts" "$src/skills/s1"
  cp "$REPO/scripts/catalog.sh" "$src/scripts/"; printf -- '---\nname: s1\ndescription: d\n---\n' > "$src/skills/s1/SKILL.md"
  printf '{"h":{"label":"H","scopes":{"user":"~"},"mapping":{"skills":"skills/{name}"}}}' > "$src/scripts/harnesses.json"
  printf 'alias x=y\n' > "$sb/home/.zshrc"
  write_rec "$sb/home/.ai-personal-install.json" h user "$sb/home" "~/" .zshrc
  out="$( cd "$sb/cwd" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
    bash "$INSTALL" --local "$src" --uninstall --harness h --scope user </dev/null 2>&1 )"; code=$?
  assert_exit "scope root ~: exits 1" 1 "$code"
  assert_contains "scope root ~: says why" "$out" "itself"
  assert_exists "scope root ~: nothing deleted" "$sb/home/.zshrc"
}

# The project root is never pruned, even when it sits inside the scope root.
test_uninstall_prune_stops_at_cwd() {
  _head "--uninstall never prunes the directory it runs from"
  local sb out code rec
  sb="$(new_sandbox)"; rec="$sb/home/.claude/.ai-personal-install.json"
  run_install "$sb" --harness claude-code --scope user --assets skills </dev/null >/dev/null 2>&1
  mkdir "$sb/home/.claude/p"; printf 'x\n' > "$sb/home/.claude/p/f"
  rec_edit "$rec" 'import hashlib; d["assets"]["skills/zz"]={"files":{"~/.claude/p/f":"sha256:"+hashlib.sha256(b"x\n").hexdigest()}}'
  out="$( cd "$sb/home/.claude/p" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
    bash "$INSTALL" --local "$REPO" --uninstall --harness claude-code --scope user </dev/null 2>&1 )"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_missing "the recorded file is removed" "$sb/home/.claude/p/f"
  [[ -d "$sb/home/.claude/p" ]] && _ok "the directory it ran from stays" || _fail "the directory it ran from stays"
}

test_uninstall_refuses_bad_or_missing_record() {
  _head "--uninstall refuses a missing, corrupt or foreign record"
  local sb out code n bad i
  sb="$(new_sandbox)"
  out="$(run_uninstall "$sb" --harness claude-code --scope project </dev/null 2>&1)"; code=$?
  assert_exit "no record: exits 0" 0 "$code"
  assert_contains "no record: says so" "$out" "no install record at"
  # project scope run from $HOME writes the record --scope user would read
  ( cd "$sb/home" && HOME="$sb/home" PATH="$sb/bin:$PATH" \
    bash "$INSTALL" --local "$REPO" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1 )
  n="$(count_files "$sb/home")"
  out="$(run_uninstall "$sb" --harness claude-code --scope user </dev/null 2>&1)"; code=$?
  assert_exit "foreign scope: exits 1" 1 "$code"
  assert_contains "foreign scope: names both" "$out" "belongs to claude-code/project, not claude-code/user"
  assert_exit "foreign scope: nothing deleted" "$n" "$(count_files "$sb/home")"
  for bad in '{bad' '{"version":2,"harness":"claude-code","scope":"user","assets":{}}' '{"version":1,"harness":"claude-code","scope":"user","assets":{"s":{"files":[]}}}' \
      '{"version":1,"harness":"claude-code\u001b[2K","scope":"user","assets":{}}'; do
    printf '%s' "$bad" > "$sb/home/.claude/.ai-personal-install.json"
    out="$(run_uninstall "$sb" --harness claude-code --scope user </dev/null 2>&1)"; code=$?
    assert_exit "record '$bad': exits 1" 1 "$code"
    assert_contains "record '$bad': clean message" "$out" "install record"
    assert_not_contains "record '$bad': no traceback" "$out" "Traceback"
    assert_not_contains "record '$bad': no raw escape printed" "$out" $'\e[2K'
    assert_exit "record '$bad': nothing deleted" "$n" "$(count_files "$sb/home")"
  done
  # a FIFO record must be refused, never opened (a stuck reader is released after 60s)
  rm "$sb/home/.claude/.ai-personal-install.json"; mkfifo "$sb/home/.claude/.ai-personal-install.json"
  ( run_uninstall "$sb" --harness claude-code --scope user </dev/null > "$sb/fifo.out" 2>&1; echo $? > "$sb/fifo.code" ) &
  i=0; while [[ ! -f "$sb/fifo.code" && $i -lt 60 ]]; do sleep 1; i=$((i + 1)); done
  [[ -f "$sb/fifo.code" ]] && _ok "FIFO record: returns without waiting on it" || _fail "FIFO record: returns without waiting on it"
  python3 -c 'import os,sys; os.close(os.open(sys.argv[1], os.O_WRONLY|os.O_NONBLOCK))' "$sb/home/.claude/.ai-personal-install.json" 2>/dev/null
  wait
  assert_exit "FIFO record: exits 1" 1 "$(cat "$sb/fifo.code")"
  assert_contains "FIFO record: says why" "$(cat "$sb/fifo.out")" "not a regular file"
  if [[ "$(id -u)" == 0 ]]; then _skip "running as root: chmod can't hide the record"; return; fi
  rm "$sb/home/.claude/.ai-personal-install.json"; chmod 000 "$sb/home/.claude"
  out="$(run_uninstall "$sb" --harness claude-code --scope user </dev/null 2>&1)"; code=$?
  chmod 755 "$sb/home/.claude"
  assert_exit "unreadable scope root: exits 1" 1 "$code"
  assert_not_contains "unreadable scope root: not reported as a missing record" "$out" "no install record"
}

test_uninstall_unreadable_asset_dir_aborts() {
  _head "--uninstall aborts cleanly when it can't check a recorded path"
  local sb out code d n
  if [[ "$(id -u)" == 0 ]]; then _skip "running as root: chmod can't block lstat"; return; fi
  sb="$(new_sandbox)"; d="$sb/cwd/.claude/skills"
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  n="$(count_files "$sb/cwd")"; chmod 000 "$d/plan-dag"
  out="$(run_uninstall "$sb" --harness claude-code --scope project </dev/null 2>&1)"; code=$?
  chmod 755 "$d/plan-dag"
  assert_exit "exits 1" 1 "$code"
  assert_contains "says which path" "$out" "cannot check"
  assert_not_contains "no traceback" "$out" "Traceback"
  assert_exit "nothing deleted" "$n" "$(count_files "$sb/cwd")"
}

test_uninstall_keeps_shared_record_and_scope_root() {
  _head "--uninstall keeps paths another asset claims, the record file and the scope root"
  local sb out code d rec
  sb="$(new_sandbox)"; d="$sb/cwd/.claude/skills"; rec="$sb/cwd/.claude/.ai-personal-install.json"
  mkdir "$sb/cwd/realroot"; ln -s realroot "$sb/cwd/.claude"   # a symlinked scope root must not be unlinked
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  rec_edit "$rec" 'f=d["assets"]["skills/atomic-commits"]["files"]; d["assets"]["suites/x"]={"files":{k:v for k,v in f.items() if k.endswith("/SKILL.md")}}; d["assets"]["skills/plan-dag"]["files"].update({".claude":"sha256:0",".claude/.ai-personal-install.json":"sha256:0"})'
  out="$(run_uninstall "$sb" --harness claude-code --scope project --assets skills --force </dev/null 2>&1)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_exists "a file also claimed by an asset not uninstalled is kept" "$d/atomic-commits/SKILL.md"
  assert_missing "the rest of that asset is removed" "$d/atomic-commits/USAGE.md"
  assert_missing "a skill listing the record and scope root is still removed" "$d/plan-dag"
  [[ -L "$sb/cwd/.claude" ]] && _ok "the scope root symlink is kept" || _fail "the scope root symlink is kept"
  assert_not_contains "the record file itself is never deleted" "$out" "removed .claude/.ai-personal-install.json"
  assert_contains "the record is kept, with the other asset" "$(record_json "$rec" 'sorted(d["assets"])')" "['suites/x']"
}

test_uninstall_file_shared_by_two_uninstalled_assets() {
  _head "--uninstall with a file two uninstalled assets share"
  local sb out code d rec share='a=d["assets"]; k=".claude/skills/atomic-commits/SKILL.md"; a["skills/plan-dag"]["files"][k]=a["skills/atomic-commits"]["files"][k]'
  sb="$(new_sandbox)"; d="$sb/cwd/.claude/skills"; rec="$sb/cwd/.claude/.ai-personal-install.json"
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  rec_edit "$rec" "$share"
  out="$(run_uninstall "$sb" --harness claude-code --scope project </dev/null 2>&1)"; code=$?
  assert_exit "both removed: exits 0" 0 "$code"
  assert_missing "both removed: the shared file is gone" "$d/atomic-commits/SKILL.md"
  sb="$(new_sandbox)"; d="$sb/cwd/.claude/skills"; rec="$sb/cwd/.claude/.ai-personal-install.json"
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  rec_edit "$rec" "$share"; printf 'edit\n' >> "$d/atomic-commits/USAGE.md"
  out="$(run_uninstall "$sb" --harness claude-code --scope project </dev/null 2>&1)"; code=$?
  assert_exit "one kept as modified: exits 0" 0 "$code"
  assert_exists "one kept as modified: the file it shares is kept" "$d/atomic-commits/SKILL.md"
  assert_missing "one kept as modified: the other asset is removed" "$d/plan-dag"
}

test_uninstall_compares_files_not_spellings() {
  _head "--uninstall compares files, not path spellings (case-insensitive file systems)"
  local sb out code d rec
  sb="$(new_sandbox)"; d="$sb/cwd/.claude/skills"; rec="$sb/cwd/.claude/.ai-personal-install.json"
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  if [[ ! -e "$sb/cwd/.CLAUDE" ]]; then _skip "case-sensitive file system"; return; fi
  rec_edit "$rec" 'a=d["assets"]; a["skills/atomic-commits"]["files"][".CLAUDE/.ai-personal-install.json"]="sha256:0"; a["suites/x"]={"files":{".CLAUDE/skills/plan-dag/SKILL.md":a["skills/plan-dag"]["files"][".claude/skills/plan-dag/SKILL.md"]}}'
  out="$(run_uninstall "$sb" --harness claude-code --scope project --assets skills --force </dev/null 2>&1)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_not_contains "the record under another spelling is not deleted" "$out" "removed .CLAUDE/.ai-personal-install.json"
  assert_exists "a staying asset's claim under another spelling protects the file" "$d/plan-dag/SKILL.md"
}

test_uninstall_prune_stops_at_symlinked_dir() {
  _head "--uninstall prunes along the recorded path and stops at a symlinked directory"
  local sb out code
  sb="$(new_sandbox)"
  mkdir -p "$sb/cwd/dotfiles/claude-skills" "$sb/cwd/.claude"; ln -s ../dotfiles/claude-skills "$sb/cwd/.claude/skills"
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  out="$(run_uninstall "$sb" --harness claude-code --scope project </dev/null 2>&1)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_exit "every installed file removed" 0 "$(count_files "$sb/cwd/dotfiles")"
  [[ -L "$sb/cwd/.claude/skills" && -d "$sb/cwd/.claude/skills" ]] \
    && _ok "the symlinked dir and its target stay" || _fail "the symlinked dir and its target stay"
}

test_uninstall_skips_what_is_not_a_file() {
  _head "--uninstall never opens or deletes a FIFO or directory at a recorded path"
  local sb out code d rec
  sb="$(new_sandbox)"; d="$sb/cwd/.claude/skills/atomic-commits"; rec="$sb/cwd/.claude/.ai-personal-install.json"
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  mkfifo "$d/fifo"; mkdir "$d/dir"; ln -s fifo "$d/lnk"
  rec_edit "$rec" 'f=d["assets"]["skills/atomic-commits"]["files"]; f.update({".claude/skills/atomic-commits/"+n:"sha256:0" for n in ("fifo","dir","lnk")})'
  out="$(run_uninstall "$sb" --harness claude-code --scope project --force </dev/null 2>&1)"; code=$?
  assert_exit "exits 0" 0 "$code"
  assert_contains "the FIFO is not a file" "$out" "atomic-commits/fifo (not a file)"
  assert_contains "the directory is not a file" "$out" "atomic-commits/dir (not a file)"
  [[ -p "$d/fifo" && -d "$d/dir" ]] && _ok "both are kept" || _fail "both are kept"
  [[ ! -L "$d/lnk" ]] && _ok "--force: the symlink to the FIFO is unlinked" || _fail "--force: the symlink to the FIFO is unlinked"
}

test_uninstall_unlinks_symlink_without_following() {
  _head "--uninstall unlinks a symlink in the way, never its target"
  local sb out code f
  sb="$(new_sandbox)"; f="$sb/cwd/.claude/skills/atomic-commits/SKILL.md"
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  printf 'PRECIOUS\n' > "$sb/precious"; rm "$f"; ln -s "$sb/precious" "$f"
  out="$(run_uninstall "$sb" --harness claude-code --scope project </dev/null 2>&1)"; code=$?
  assert_exit "exits 0" 0 "$code"
  [[ -L "$f" ]] && _ok "a symlink counts as modified: kept without --force" || _fail "a symlink counts as modified: kept without --force"
  out="$(run_uninstall "$sb" --harness claude-code --scope project --force </dev/null 2>&1)"; code=$?
  assert_exit "--force: exits 0" 0 "$code"
  [[ ! -L "$f" && ! -e "$f" ]] && _ok "--force: the link is gone" || _fail "--force: the link is gone"
  assert_contains "--force: its target is untouched" "$(cat "$sb/precious")" "PRECIOUS"
}

test_uninstall_dry_run_and_flag_conflicts() {
  _head "--uninstall --dry-run changes nothing; conflicting flags are refused"
  local sb out code rec n f
  sb="$(new_sandbox)"; rec="$sb/cwd/.claude/.ai-personal-install.json"
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  printf 'edit\n' >> "$sb/cwd/.claude/skills/atomic-commits/SKILL.md"
  rec_edit "$rec" 'pass'   # compact JSON, so any rewrite shows up in cmp
  cp "$rec" "$sb/before.json"; n="$(count_files "$sb/cwd")"
  for f in "" --force; do
    out="$(run_uninstall "$sb" --harness claude-code --scope project --dry-run $f </dev/null 2>&1)"; code=$?
    assert_exit "--dry-run $f: exits 0" 0 "$code"
    assert_contains "--dry-run $f: lists what it would remove" "$out" "would remove"
    assert_contains "--dry-run $f: lists the modified file" "$out" "modified: .claude/skills/atomic-commits/SKILL.md"
    assert_exit "--dry-run $f: nothing deleted" "$n" "$(count_files "$sb/cwd")"
    cmp -s "$sb/before.json" "$rec" && _ok "--dry-run $f: record untouched" || _fail "--dry-run $f: record untouched"
  done
  for f in --yes-deps --no-deps; do
    out="$(run_uninstall "$sb" --harness claude-code --scope project $f </dev/null 2>&1)"; code=$?
    assert_exit "$f: exits 1" 1 "$code"
    assert_contains "$f: explains the conflict" "$out" "cannot be combined with --uninstall"
  done
  assert_exit "conflicting flags: nothing deleted" "$n" "$(count_files "$sb/cwd")"
}

test_uninstall_failed_delete_keeps_record_honest() {
  _head "a delete that fails part-way exits 1 and keeps what's left in the record"
  local sb out code d rec
  if [[ "$(id -u)" == 0 ]]; then _skip "running as root: chmod can't block unlink"; return; fi
  sb="$(new_sandbox)"; d="$sb/cwd/.claude/skills"; rec="$sb/cwd/.claude/.ai-personal-install.json"
  run_install "$sb" --harness claude-code --scope project --assets skills </dev/null >/dev/null 2>&1
  chmod 555 "$d/plan-dag"
  out="$(run_uninstall "$sb" --harness claude-code --scope project </dev/null 2>&1)"; code=$?
  chmod -R u+w "$sb/cwd/.claude"
  assert_exit "exits 1" 1 "$code"
  assert_not_contains "no traceback" "$out" "Traceback"
  assert_missing "other assets are removed" "$d/atomic-commits"
  assert_contains "the record keeps only the stuck asset" "$(record_json "$rec" 'sorted(d["assets"])')" "['skills/plan-dag']"
  assert_record "what the record still lists is on disk" "$rec" "$sb/cwd" "$sb/home" 0
}

test_uninstall_round_trip
test_uninstall_reads_only_the_scope_root_record
test_uninstall_keeps_modified_asset_and_user_files
test_uninstall_path_guards_abort_before_deleting
test_uninstall_prune_stops_at_cwd
test_uninstall_confined_when_the_record_is_in_home
test_uninstall_refuses_bad_or_missing_record
test_uninstall_unreadable_asset_dir_aborts
test_uninstall_keeps_shared_record_and_scope_root
test_uninstall_file_shared_by_two_uninstalled_assets
test_uninstall_compares_files_not_spellings
test_uninstall_prune_stops_at_symlinked_dir
test_uninstall_skips_what_is_not_a_file
test_uninstall_unlinks_symlink_without_following
test_uninstall_dry_run_and_flag_conflicts
test_uninstall_failed_delete_keeps_record_honest

printf "\n"
if [[ $FAIL -eq 0 ]]; then
  printf "${GRN}${BLD}%d passed, %d skipped.${NC}\n\n" "$PASS" "$SKIP"
  exit 0
else
  printf "${RED}${BLD}%d passed, %d failed, %d skipped.${NC}\n\n" "$PASS" "$FAIL" "$SKIP"
  exit 1
fi
