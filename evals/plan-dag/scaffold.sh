#!/usr/bin/env bash
# Builds one eval workspace in the current (empty) directory, deterministically (same HEAD SHA every run).
# usage: scaffold.sh <absolute-case-dir> [--base-only]
# Called by each case's one-line scaffold.sh wrapper; the eval runner sets cwd to the empty workspace.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASE_DIR="${1:?usage: scaffold.sh <absolute-case-dir> [--base-only]}"
MODE="${2:-}"
case "$MODE" in
  "" | --base-only) ;;
  *) echo "usage: scaffold.sh <absolute-case-dir> [--base-only]" >&2; exit 2 ;;
esac

if [ -n "$(ls -A .)" ]; then
  echo "scaffold.sh: refusing to run in a non-empty directory: $PWD" >&2
  exit 1
fi

deinert() {
  if [ -e dotenv ]; then mv -f dotenv .env; fi
  if [ -e gitignore ]; then mv -f gitignore .gitignore; fi
  if [ -e CLAUDE.md.fixture ]; then mv -f CLAUDE.md.fixture CLAUDE.md; fi
  if [ -d dot-github ]; then
    mkdir -p .github
    cp -R dot-github/. .github/
    rm -rf dot-github
  fi
  find . -name .DS_Store -not -path './.git/*' -delete
}

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="Fixture Author" GIT_AUTHOR_EMAIL="fixture@example.invalid"
export GIT_COMMITTER_NAME="Fixture Author" GIT_COMMITTER_EMAIL="fixture@example.invalid"
g() { git -c commit.gpgsign=false -c core.autocrlf=false "$@"; }

cp -R "$HERE/fixtures/base/." .
if [ "$MODE" != "--base-only" ]; then
  cp -R "$HERE/fixtures/std/." .
fi
deinert
g init -q -b main
g add -A
GIT_AUTHOR_DATE="2026-10-01T09:00:00Z" GIT_COMMITTER_DATE="2026-10-01T09:00:00Z" \
  g commit -q -m "chore: initial tasks-api"

if [ -d "$CASE_DIR/overlay" ]; then
  msg="$(head -n 1 "$CASE_DIR/overlay.commit")"
  cp -R "$CASE_DIR/overlay/." .
  deinert
  g add -A
  GIT_AUTHOR_DATE="2026-10-15T09:00:00Z" GIT_COMMITTER_DATE="2026-10-15T09:00:00Z" \
    g commit -q -m "$msg"
fi

if [ "$MODE" != "--base-only" ]; then
  mkdir -p .claude/state
fi
