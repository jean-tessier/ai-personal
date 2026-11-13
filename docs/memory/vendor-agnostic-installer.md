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
| Dependency manifest | `{category}/{name}/dependencies.json` — colocated, one file per asset, optional; flat JSON array of repo-relative paths (e.g. `["skills/create-adr", "skills/yaml-frontmatter"]`); absent means no dependencies. See [ADR-0007](../adrs/ADR-0007-colocated-dependency-manifest.md). |
| User docs | `README.md`'s `## Installing` section |
| Structural lint | `scripts/validate.sh`'s `── harnesses ──` section |

## How to validate

`bash scripts/validate.sh` lints `scripts/harnesses.json` (valid JSON; each harness has a non-empty
`label`, ≥1 `scopes` key, ≥1 `mapping` key). `bash -n install.sh` checks syntax. Neither runs
`install.sh` end-to-end.

For that, `bash scripts/test-install.sh` runs `install.sh` behaviorally: dry-run/actual installs
into both scopes, `--force` skip-vs-overwrite, unknown harness/scope/category, a harness/category
pair with no mapping, missing required flags, `-h`, the numbered-picker fallback (via
`INSTALL_FORCE_INTERACTIVE=1`), a regression test for the missing-`harnesses.json`
traceback bug described below, and dependency resolution (`test_deps_*`, 4 cases: auto-add under
`--yes-deps`, fail-closed with no flag — including under `--dry-run`, `--no-deps` skips without
queuing an install line, no duplicate when a dependency is already independently selected). Every
test runs against a throwaway `mktemp -d` sandbox with an
isolated `$PWD`/`$HOME`, removed via `trap ... EXIT` — nothing touches the real repo or the real
home directory, pass or fail. `bash scripts/test-install-docker.sh` runs the same script inside a
`--rm --network none` container for full isolation (needs Docker running).

**Gotcha this uncovered**: overriding `$HOME` to sandbox the "user" scope breaks version-manager
shims (asdf/mise/pyenv) that resolve their real interpreter via `$HOME/.tool-versions` — `python3`
silently resolves to a broken shim instead of the real interpreter, producing confusing empty
`_json` output that looks like a real `install.sh` bug but isn't. `test-install.sh` works around
this by resolving the real interpreter once (`python3 -c 'import sys; print(sys.executable)'`)
before any `$HOME` override, then symlinking it into each sandbox's own `bin/`, prepended onto
`PATH`. Any future test harness that overrides `$HOME` needs the same workaround.

It still doesn't exercise the real curl/tar network fetch — that's still the manual recipe below
(rejected as a permanent automated test because it would require either a URL-override flag,
already rejected as scope creep — see Task 3's decision — or hitting the real GitHub codeload
endpoint from a test run).

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
- **`"${arr[@]}"` on an empty array throws "unbound variable" under `set -u` on bash 3.2** (macOS's
  system `/bin/bash`), unlike bash 4.4+ where it silently expands to nothing. `resolve_dependencies()`
  avoids bash arrays for its working state entirely, using `$WORK`-scoped temp files instead
  (`dep_candidates.txt`, `dep_resolvable.tsv`) — the same file-based idiom `select_assets()` already
  uses for `$SELECTION_FILE`. Default to temp files over arrays for any future stateful loop in this
  script, since macOS ships bash 3.2 and this repo doesn't require a newer one on `PATH`.

## Known, accepted gaps (not bugs)

- Piped `curl | bash` (no explicit `--assets`) has no TTY on stdin, so it always installs every
  category rather than launching the interactive picker — documented in `README.md`.
- `copilot` has no `user` scope (`project` → `.github` only) — passing `--scope user --harness
  copilot` fails cleanly (`scope_root` lookup returns nothing → `_fail`), by design.
- `copilot.mapping` omits `suites` — `suites/{name}/` doesn't map onto Copilot's native
  layout for this repo's Claude Code-targeted suites; `tiered-escalation-suite` (Copilot-targeted)
  is a hand-copied drop-in payload instead, not something `install.sh` places.

**2026-07-08 update**: `agents`, `packs`, `tasks`, and `mcp` are no longer asset categories at
all — `prompts/`, `packs/`, and `tools/` were pruned from the repo (they held only empty
scaffolding, no real assets). `ALL_CATEGORIES` in `install.sh` is now `(skills suites)`. See
ADR-0001's, ADR-0004's, and ADR-0005's superseded notes.

**2026-07-08 update**: `workflows/` was renamed to `suites/` across the repo (directory,
`scripts/harnesses.json`'s mapping key, `scripts/catalog.sh`/`scripts/validate.sh`'s category
name, and `install.sh`'s `ALL_CATEGORIES`) to avoid implying a step-by-step workflow structure.

**2026-07-12 update**: Assets can now declare dependencies on other assets via a colocated
`dependencies.json` (e.g. `suites/handoff-workflow` depends on `skills/create-adr` and
`skills/yaml-frontmatter`). `scripts/catalog.sh` surfaces it as a `"dependencies"` field per item,
`scripts/validate.sh` checks it's valid JSON/a flat array/every path resolves, and `install.sh`'s
`resolve_dependencies()` walks selected items to a fixed point and adds/skips/prompts/fails per the
`--yes-deps`/`--no-deps` flags described above. See
[ADR-0009](../adrs/ADR-0009-colocated-dependency-manifest.md) for the full decision record.

**2026-07-13 update**: suites and skills that fit Claude Code's/Copilot's native plugin
shape now carry real `.claude-plugin/plugin.json` manifests, and the repo root has a
`.claude-plugin/marketplace.json` listing them — see
[ADR-0007](../adrs/ADR-0007-suites-as-native-plugins.md). Two `install.sh` behaviors
followed from that:

- **Dependency auto-include** — ~~selecting a suite also selects the skills it declares in its
  `plugin.json` `dependencies` array~~. **Superseded on 2026-07-16** by the colocated
  `dependencies.json` mechanism in the 2026-07-12 entry above (see
  [ADR-0009](../adrs/ADR-0009-colocated-dependency-manifest.md)); `plugin_deps_json()` and
  `plugin.json`'s `dependencies` key are gone. `pluginShaped` itself is untouched and still
  gates Copilot translation below.
- **Copilot translation**: `copilot`'s `harnesses.json` mapping now has a `suites` key,
  but only suites `catalog.sh` marks `pluginShaped` (a root `.claude-plugin/plugin.json`)
  are reachable through it — `select_assets()` filters the rest out per-item with a
  one-line notice, same compatibility-by-omission spirit as ADR-0003 applied at item
  instead of category granularity. Eligible suites get mechanically rewritten by
  `translate_to_copilot()`: `agents/*.md` → `agents/*.agent.md`, and
  `.claude-plugin/plugin.json` relocated to a root `plugin.json`. `tiered-escalation-suite`
  and `tier-layered-teams/copilot/` are drop-in payloads, not plugin-shaped, and stay
  permanently unreachable through this path — unchanged from before this decision.

**Windows gotcha found while verifying this**: a native Windows `python3.exe` (as opposed
to WSL or a Unix `python3`) writes `\r\n` to stdout even when piped, which corrupts every
`_json()` caller that does `read -r ... < <(_json ...)` or `var=$(_json ...)` — the
symptom is `cp: cannot stat '...suite'$'\r': No such file or directory` or a bash
arithmetic/`[[` syntax error pointing at a value that looks right when printed.
`install.sh`'s `_json()` and `validate.sh`'s equivalent python-heredoc call sites now
pipe through `tr -d '\r'` to strip it; `set -o pipefail` (already part of both scripts'
top-level `set -euo pipefail`) keeps the underlying python exit code flowing through that
extra pipe stage. Any new python-heredoc call site added to either script needs the same
`| tr -d '\r'`.

**2026-07-16 update**: the two dependency mechanisms above (2026-07-12's colocated
`dependencies.json` and 2026-07-13's `plugin.json`-array auto-include) were built in parallel on
separate branches and collided when `feature/asset-dependency-manifest` merged. Both had defined a
bash function named `resolve_dependencies()` at non-overlapping offsets in `install.sh` — so git's
textual merge flagged **no conflict** while leaving two definitions and two call sites (bash keeps
the later one). The merge kept ADR-0009's engine as the sole implementation and deleted the
ADR-0007 one, along with `catalog.sh`'s `plugin_deps_json()`, `install.sh`'s now-unreferenced
`suite_deps`/`item_path` `_json` modes, and `handoff-workflow`'s `plugin.json` `dependencies` key.
The lesson worth keeping: when two branches implement the same feature, a clean `git merge` says
nothing about whether the result is coherent — grep the merged file for duplicate definitions.
Two `install.sh` behavior changes came with it: a non-interactive run with unresolved dependencies
and neither `--yes-deps` nor `--no-deps` now **fails closed** (exit 1) instead of silently
auto-adding, and dependencies are declared as category-prefixed paths (`skills/create-adr`), not
bare skill names.
