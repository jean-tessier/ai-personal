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
  cp -R "$REPO/scripts" "$REPO/skills" "$REPO/suites" "$REPO/.claude-plugin" "$src/"
  printf '%s' '{"bogus":[],"claude-code":[{"kind":"agents","src":"../x","mode":"copy"},{"kind":["agents"],"src":"claude-code/agents","mode":"copy"}]}' \
    > "$src/suites/tier-layered-teams/manifest.json"
  out="$(bash "$src/scripts/validate.sh" </dev/null 2>&1)"; code=$?
  assert_exit "bad manifest: exits 1" 1 "$code"
  assert_contains "flags unknown harness key" "$out" "unknown harness key 'bogus'"
  assert_contains "flags non-relative src" "$out" "src must be relative"
  assert_contains "a lint crash is a FAIL, not a silent ok" "$out" "check crashed"
  rm "$src/suites/tier-layered-teams/manifest.json"
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
  cp -R "$REPO/scripts" "$REPO/skills" "$REPO/suites" "$REPO/.claude-plugin" "$src/"
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
    assert_missing "translate=$bad: nothing installed" "$sb/cwd/.github/suites"
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

printf "\n"
if [[ $FAIL -eq 0 ]]; then
  printf "${GRN}${BLD}%d passed, %d skipped.${NC}\n\n" "$PASS" "$SKIP"
  exit 0
else
  printf "${RED}${BLD}%d passed, %d failed, %d skipped.${NC}\n\n" "$PASS" "$FAIL" "$SKIP"
  exit 1
fi
