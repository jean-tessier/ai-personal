#!/usr/bin/env bash
#
# detect_dialect.sh — gather signals about a repository's commit convention
# and suggest which of the four "worlds" it lives in. This only inspects;
# it never modifies the repo. The model makes the final call.
#
# Worlds:
#   1 = Conventional Commits   (type(scope): subject; commitlint/semantic-release)
#   2 = Changesets             (primary artifact is a .changeset/*.md file)
#   3 = Trailer / kernel-style (plain subject + Signed-off-by/Fixes: trailers)
#   4 = Prose                  (well-formed imperative messages, no prefix)

set -uo pipefail

# How many recent commit subjects to sample for rate calculations.
SAMPLE=50

say() { printf '%s\n' "$*"; }
hr()  { printf -- '----------------------------------------\n'; }

# --- Are we even in a git repo? -------------------------------------------
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  say "NOT A GIT REPO: run this from inside the user's repository."
  say "Suggested world: (cannot detect) — ask the user or default to World 4 (prose)."
  exit 0
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
COMMITS="$(git rev-list --count HEAD 2>/dev/null || echo 0)"

say "Repo root: ${ROOT:-unknown}"
say "Total commits: ${COMMITS}"
hr

# --- World 1 signals: Conventional Commits config -------------------------
cc_config="no"
for f in \
  commitlint.config.js commitlint.config.cjs commitlint.config.mjs commitlint.config.ts \
  .commitlintrc .commitlintrc.js .commitlintrc.cjs .commitlintrc.json .commitlintrc.yml .commitlintrc.yaml \
  .releaserc .releaserc.json .releaserc.js .releaserc.yaml .releaserc.yml release.config.js \
  release-please-config.json .czrc cz.json ; do
  [ -e "$ROOT/$f" ] && { cc_config="yes ($f)"; break; }
done
# commitizen / semantic-release / commitlint referenced in package.json?
pkg_cc="no"
if [ -f "$ROOT/package.json" ]; then
  grep -Eq '"(commitizen|@commitlint/|semantic-release|standard-version|release-please)' "$ROOT/package.json" 2>/dev/null && pkg_cc="yes (package.json)"
fi
say "World 1 — commitlint/semantic-release config file: $cc_config"
say "World 1 — CC tooling in package.json:             $pkg_cc"

# Rate of Conventional-Commits-style subjects in recent history.
cc_rate="n/a"
if [ "$COMMITS" -gt 0 ]; then
  subjects="$(git log -n "$SAMPLE" --pretty=format:%s 2>/dev/null)"
  total="$(printf '%s\n' "$subjects" | grep -c . )"
  if [ "$total" -gt 0 ]; then
    hits="$(printf '%s\n' "$subjects" | grep -Ec '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^)]+\))?!?: ' )"
    cc_rate="$(( hits * 100 / total ))% ($hits/$total of last $total subjects)"
  fi
fi
say "World 1 — Conventional-Commits prefix rate:       $cc_rate"
hr

# --- World 2 signals: Changesets ------------------------------------------
cs_dir="no";  [ -d "$ROOT/.changeset" ] && cs_dir="yes (.changeset/)"
cs_cfg="no";  [ -f "$ROOT/.changeset/config.json" ] && cs_cfg="yes (.changeset/config.json)"
cs_dep="no"
if [ -f "$ROOT/package.json" ]; then
  grep -Eq '"@changesets/cli"' "$ROOT/package.json" 2>/dev/null && cs_dep="yes (@changesets/cli)"
fi
cs_pending="0"
if [ -d "$ROOT/.changeset" ]; then
  cs_pending="$(find "$ROOT/.changeset" -maxdepth 1 -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')"
fi
say "World 2 — .changeset directory:    $cs_dir"
say "World 2 — changesets config:       $cs_cfg"
say "World 2 — @changesets/cli dep:     $cs_dep"
say "World 2 — pending changeset files: $cs_pending"
hr

# --- World 3 signals: trailers / DCO --------------------------------------
trailer_rate="n/a"
dco_doc="no"
if [ "$COMMITS" -gt 0 ]; then
  bodies="$(git log -n "$SAMPLE" --pretty=format:'%b' 2>/dev/null)"
  n="$(git log -n "$SAMPLE" --pretty=format:'%H' 2>/dev/null | grep -c . )"
  if [ "$n" -gt 0 ]; then
    tr_hits="$(printf '%s\n' "$bodies" | grep -Ec '^(Signed-off-by|Fixes|Reviewed-by|Acked-by|Reported-by|Co-authored-by|Cc): ' )"
    trailer_rate="$tr_hits trailer line(s) across last $n commits"
  fi
fi
for d in CONTRIBUTING.md CONTRIBUTING CONTRIBUTING.rst docs/SubmittingPatches Documentation/SubmittingPatches ; do
  if [ -f "$ROOT/$d" ] && grep -Eqi 'signed-off-by|developer certificate of origin|DCO' "$ROOT/$d" 2>/dev/null; then
    dco_doc="yes ($d mentions DCO/sign-off)"; break
  fi
done
say "World 3 — recent trailer usage:    $trailer_rate"
say "World 3 — DCO/sign-off in docs:    $dco_doc"
hr

# --- Suggestion -----------------------------------------------------------
# Precedence: an active release mechanism wins over mere commit phrasing.
suggest="World 4 (prose) — no strong signal; conform to recent history."
if [ "$cs_dir" != "no" ] && [ "$cs_dep" != "no" ]; then
  suggest="World 2 (Changesets) — generate a .changeset file; commit phrasing is secondary."
elif [ "$cc_config" != "no" ] || [ "$pkg_cc" != "no" ]; then
  suggest="World 1 (Conventional Commits) — config present; emit type(scope): subject."
elif printf '%s' "$cc_rate" | grep -Eq '^([5-9][0-9]|100)%'; then
  suggest="World 1 (Conventional Commits) — high prefix rate in history."
elif printf '%s' "$trailer_rate" | grep -Eq '[1-9]'  && [ "$dco_doc" != "no" ]; then
  suggest="World 3 (Trailer/kernel-style) — trailers + DCO docs present."
fi
say "SUGGESTED: $suggest"
say ""
say "Note: this is a suggestion from heuristics. Confirm against the actual"
say "recent history (git log) and read references/dialects.md before deciding,"
say "especially when signals are mixed."
