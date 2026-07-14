# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal monorepo of reusable Claude Code assets — skills and multi-component suites — kept
in one place with consistent structure, documentation, and a vendor-agnostic installer. The assets
themselves are Markdown/JSON with no build step; the one exception is dev-only Node tooling under
`scripts/` (the `ingest-asset` CLI, with its own `package.json`, unit tests, and typecheck) plus a
handful of Bash scripts that catalog and validate the tree.

## Commands

```bash
bash scripts/validate.sh          # structural lint; exits 1 on failures. Run before committing.
make check                        # validate.sh + node tests + typecheck (Makefile wraps them — the single deterministic gate)
bash scripts/catalog.sh           # emit a JSON index of every named asset to stdout
bash scripts/catalog.sh > catalog.json
bash scripts/test-install.sh          # install.sh behavioral tests, sandboxed via mktemp (no disk clutter)
bash scripts/test-install-docker.sh   # same tests, fully isolated in a container (needs Docker running)
node --test scripts/*.test.ts     # unit tests for the dev-only Node tooling in scripts/
npx tsc --noEmit                  # typecheck the Node tooling
npm run ingest-asset -- <path-to-source-file> [--dry-run]   # classify + scaffold a new skill or suite component
```

There is no general unit-test framework or `npm test`/`pytest` equivalent for the assets themselves.
`scripts/validate.sh` is a structural linter (required files present, JSON well-formed, naming
conventions followed), not a behavioral one — `npm test`/`npx tsc --noEmit` cover only the dev-only
Node tooling under `scripts/`. `scripts/test-install.sh` is the one behavioral exception for the
installer: it runs `install.sh` end-to-end against throwaway `mktemp` sandboxes (isolated
`$PWD`/`$HOME`, cleaned up via `trap` on exit) using `install.sh`'s own test seams (`--local`,
`INSTALL_FORCE_INTERACTIVE`) — see `docs/memory/vendor-agnostic-installer.md`.

Installer (see Architecture below):

```bash
bash install.sh --harness claude-code --scope project --assets skills --dry-run
curl -fsSL https://raw.githubusercontent.com/jean-tessier/ai-personal/main/install.sh \
  | bash -s -- --harness claude-code --scope project
```

## Architecture

### The core asset taxonomy — read this before adding anything

Everything in this repo is one of two kinds of asset, and the kind determines where it lives.
This distinction is the single most load-bearing piece of architecture — `scripts/catalog.sh`,
`scripts/validate.sh`, and `install.sh`/`scripts/harnesses.json` all branch on it:

| Kind | Lives in | Invocable alone? | Distributable outside this repo? |
|---|---|---|---|
| Skill | `skills/{name}/` (`SKILL.md` + `USAGE.md` + `CHANGELOG.md`) | Yes | No |
| Orchestration suite | `suites/{name}/` — grouped, inter-referential components | No — the set moves/breaks together | No |

This repo only ships categories that have real, finished content in them — no placeholder
categories awaiting their first asset. If a new kind of asset (agent prompts, MCP manifests,
distributable skill packs, eval cases, etc.) gets real content again, add it back to this table,
`scripts/catalog.sh`, `scripts/validate.sh`, `scripts/harnesses.json`, and `install.sh`'s
`ALL_CATEGORIES` array and `categories` mode together; don't let one drift ahead of the others.

**A suite may additionally carry a root `.claude-plugin/plugin.json`**, making it a real
Claude Code/Copilot plugin — `scripts/catalog.sh` surfaces this per suite as `pluginShaped`
and `dependencies`. This is optional, not a third kind of asset: a suite without one is
still a normal suite, just not eligible for `install.sh`'s dependency auto-include or its
Copilot translation. See `docs/adrs/ADR-0007-suites-as-native-plugins.md` for which suites
have one and why (it's only added where the suite's shape already fits — never force-fit).

**Naming rule that matters across the whole repo**: a directory's kebab-case name is its canonical
identifier everywhere — in `README.md`, in any suite that references it, and in its own
`CHANGELOG.md`.

**Don't fork a skill into a suite.** `suites/{name}/` is for components that only make sense
as part of that suite. A skill that's also independently useful stays a single copy under
`skills/{name}/`, referenced by relative link/name from any suite that uses it — never
duplicated into the suite's own directory. Two copies of the same skill drift silently; one
already did (see git history around the `suites/handoff-workflow` cleanup).

### The vendor-agnostic installer (`install.sh` + `scripts/harnesses.json`)

`install.sh` is a `curl | bash`-able entrypoint that fetches this repo (curl+tar, no `git` needed)
and copies selected assets into a target harness's directory layout. It is **fully data-driven**:
`scripts/harnesses.json` declares, per harness key, a `label`, the `scopes` it supports (e.g.
`claude-code` has `project`→`.claude` and `user`→`~/.claude`; `copilot` has only `project`→`.github`),
and a `mapping` from asset category to destination-path template. `install.sh` never branches on a
harness's name — adding a harness is a JSON edit, not a code change (see
`docs/adrs/ADR-0003-data-driven-harness-manifest.md`).

**Compatibility is expressed by omission, not error**: a harness's `mapping` only lists categories
that survive an unmodified copy (or, for `copilot`'s `suites`, translation — see below). A missing
key means "structurally incompatible for this harness" — `install.sh` skips it with a one-line
notice, never a failure. Don't assume every harness gets every category.

**Plugin-shaped suites get translated for Copilot; drop-in payloads don't.** `copilot`'s `suites`
mapping only reaches suites `scripts/catalog.sh` marks `pluginShaped` (a root
`.claude-plugin/plugin.json` — see the asset taxonomy section above and
`docs/adrs/ADR-0007-suites-as-native-plugins.md`); `install.sh`'s `select_assets()` filters the
rest out per-item with a one-line notice, same compatibility-by-omission spirit applied at item
instead of category granularity. Eligible suites are mechanically rewritten by
`translate_to_copilot()` (`agents/*.md` → `agents/*.agent.md`, `.claude-plugin/plugin.json` →
a root `plugin.json`). Drop-in Copilot payloads (`suites/tiered-escalation-suite/`,
`suites/tier-layered-teams/copilot/`) aren't plugin-shaped and stay permanently unreachable
through this path — they're deployed by hand instead (see each suite's own `USAGE.md`).

### This repo's own dogfood skill install

`.claude/skills/atomic-commits/` is a real installed copy of `skills/atomic-commits/` — kept so this
repo can use its own `atomic-commits` skill on itself while working here. It's a copy, not a
symlink, so it can drift from the canonical `skills/atomic-commits/`; refresh it (and pull in any
other skill this repo wants to dogfood on itself) with:

```bash
bash install.sh --local . --harness claude-code --scope project --assets skills --force
```

### Session continuity: the handoff loop

Multi-session efforts in *this repo itself* are tracked via a `handoff.md` at the project root,
authored/consumed by a chain of skills: `resume-handoff` / `handoff-document` (each session's
read/write pair; `handoff-document` also authors the first `handoff.md`) → `ingest-handoff` (promote durable content once
a goal is met) → `archive-handoff` (move the closed-out handoff into `docs/archive/handoffs/`).
`drive-to-completion` automates the whole loop across subagents. Durable output lands in three
indexed stores, each with its own `INDEX.md`:

| Store | Holds |
|---|---|
| `docs/adrs/` | Architectural decisions (why the codebase is shaped a certain way) |
| `docs/memory/` | Operational facts, conventions, and deferred/future-work items |
| `docs/archive/handoffs/` | Verbatim closed-out session records |

If `handoff.md` exists at the root, a prior effort is mid-flight — read it before starting
unrelated work.

**Check [`docs/memory/INDEX.md`](docs/memory/INDEX.md) and [`docs/adrs/INDEX.md`](docs/adrs/INDEX.md)
at the start of a session** — they index operational facts/deferred items and architectural
decisions from prior sessions that may bear on the current task, including superseded ones (e.g.
the retired GitHub Copilot/VS Code dogfood suite — see ADR-0001).

## Conventions

- Commits follow Conventional Commits (`type: subject`, e.g. `feat:`, `docs:`, `fix:`, `test:`) —
  100% of recent history uses this prefix style.
- Skill changes are logged in that skill's own `CHANGELOG.md`:
  `YYYY-MM-DD · {model-version} · {what changed and why}`.
- Markdown docs (ADRs, memory docs, archived handoffs) carry YAML frontmatter with `date`,
  `description` (≤120 chars), and `status`.
