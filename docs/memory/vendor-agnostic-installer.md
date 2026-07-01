---
date: 2026-07-01
description: Status and operating notes for the curl | bash vendor-agnostic installer (install.sh)
status: active
tags: [installer, bash, harnesses]
---

# Vendor-agnostic installer — status and operations

## What it is

A single `curl -fsSL .../install.sh | bash -s -- ...`-able script that fetches this public repo
(no `git` dependency — `curl` + `tar` only) and copies selected asset categories into the right
place for a chosen harness/scope. Built across 6 tasks on `feature/vendor-agnostic-installer`; see
[ADR-0003](../adrs/ADR-0003-data-driven-harness-manifest.md),
[ADR-0004](../adrs/ADR-0004-claude-code-native-formats-incompatible.md), and
[ADR-0005](../adrs/ADR-0005-packs-flatten-into-skills.md) for the architectural decisions behind
its design.

## Where things live

| Surface | Path |
|---|---|
| Installer entrypoint | `install.sh` (repo root, not `scripts/`) |
| Harness manifest | `scripts/harnesses.json` — one entry per harness: `label`, `scopes` (scope key → root path), `mapping` (asset category → destination template) |
| User docs | `README.md`'s `## Installing` section |
| Structural lint | `scripts/validate.sh`'s `── harnesses ──` section |

## How to validate

`bash scripts/validate.sh` lints `scripts/harnesses.json` (valid JSON; each harness has a non-empty
`label`, ≥1 `scopes` key, ≥1 `mapping` key). `bash -n install.sh` checks syntax. Neither runs
`install.sh` end-to-end — for that, use the test seams below.

## Test-seam conventions (read this before touching `install.sh`)

`install.sh` has two undocumented seams, deliberately left out of `README.md` and `usage()` (they
are for testing, not user-facing):

- **`--local <path>`** — skips `fetch_source()`'s real `curl`/`tar` network fetch and uses
  `<path>` as `$SRC` directly. Every task's dry-run smoke test before Task 6 used this. It never
  exercises the real `codeload.github.com` fetch or `tar` extraction — only Task 6 did that, via a
  disposable local `python3 -m http.server` + a hand-built tarball (see below), never committed.
- **`INSTALL_FORCE_INTERACTIVE=1`** (env var) — bypasses `select_assets()`'s `[[ -t 0 ]]` TTY check
  so the interactive picker (`fzf` → `gum` → numbered `read`-loop) can be exercised from a script
  with no real TTY attached. Combine with stubbing `fzf`/`gum` on `PATH` (or removing them from
  `PATH`) to force a specific picker branch.

To re-run a full real-network fetch test (not just `--local`): package the working tree into a
`.tar.gz` whose top-level dir is renamed to match GitHub codeload's `{repo}-{ref}` naming
(`tar --exclude='<repo>/.git' -s '/^<repo>/<repo>-<ref>/' -czf out.tar.gz -C <parent> <repo>` — `-s`
is bsdtar's sed-style rename flag, available on stock macOS `tar`), serve it with `python3 -m
http.server` from a scratch directory, and temporarily point `fetch_source()`'s `url=` at
`http://127.0.0.1:<port>/...` — revert before finishing, never land a URL override as a permanent
flag (rejected as scope creep; see `handoff.md`'s Task 6 record and Task 3's decision against a
`--ref` flag).

## macOS bash/awk gotchas discovered building this script

- **`set -euo pipefail` + a bare trailing `cond && action` as a function's last statement**: if
  `cond` is false, `&&`'s short-circuit makes the *function's own* exit status non-zero, which
  aborts the (unguarded) caller under `-e` even though nothing actually failed. Fix: use an explicit
  `if ...; then ...; fi` for any such guard — never rely on a bare `cond && { ...; exit 1; }` as
  the last line of a function. See `install.sh`'s `parse_args()` required-flag checks and the
  Task-6 `main()` guard for the pattern to copy.
- **macOS's `/usr/bin/awk` (One True Awk, not gawk) chokes on a literal newline embedded in a `-v`
  variable assignment.** If you need to pass a multi-line value (e.g. a newline-joined list of
  selected names) into an awk script, pass it via the environment (`FOO="$val" awk '... ENVIRON["FOO"] ...'`)
  instead of `-v FOO="$val"`. See `install.sh`'s `pick_items()`.
- **bsdtar's `-s` (rename-on-extract/create) flag** is the macOS-stock-`tar` equivalent of GNU
  tar's `--transform`; syntax is sed-style (`-s '/pattern/replacement/'`). Useful for building a
  test tarball that mimics GitHub codeload's `{repo}-{ref}/...` top-level directory naming without
  a real GitHub release.
- **A fetched tree missing an expected file surfaces as a raw Python traceback, not a clean error,
  unless explicitly guarded.** `install.sh`'s `_json()` dispatcher's `load()` helper does a bare
  `open(path)` with no existence check; if `scripts/harnesses.json` isn't present in whatever
  `$SRC` points at (e.g. a fetched branch that predates this file), every `_json` call crashes with
  an unhandled `FileNotFoundError` traceback before `install.sh`'s own `_fail`/`exit 1` path ever
  runs. `main()` now checks `[[ -f "$SRC/scripts/harnesses.json" ]]` immediately after
  `build_catalog()` and `_fail`s cleanly if it's missing — add the same kind of explicit existence
  check before any future `_json` call that might run against an untrusted/older fetched tree.

## Known, accepted gaps (not bugs)

- `claude-code.mapping` and `copilot.mapping` both omit `agents` and `mcp` — this repo's
  `prompts/agents/`/`tools/mcp/` storage shapes don't match either harness's native subagent/MCP
  config format. See ADR-0004.
- Piped `curl | bash` (no explicit `--assets`) has no TTY on stdin, so it always installs every
  category rather than launching the interactive picker — documented in `README.md`.
- `copilot` has no `user` scope (`project` → `.github` only) — passing `--scope user --harness
  copilot` fails cleanly (`scope_root` lookup returns nothing → `_fail`), by design.
