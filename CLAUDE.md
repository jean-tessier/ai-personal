# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal monorepo of reusable Claude Code assets — skills and multi-component workflows — kept
in one place with consistent structure, documentation, and a vendor-agnostic installer. There is no
application code, build step, or package manager; everything is Markdown/JSON plus a handful of
Bash scripts that catalog and validate the tree.

## Commands

```bash
bash scripts/validate.sh          # structural lint; exits 1 on failures. Run before committing.
make check                        # same thing (Makefile wraps validate.sh — the single deterministic gate)
bash scripts/catalog.sh           # emit a JSON index of every named asset to stdout
bash scripts/catalog.sh > catalog.json
bash scripts/test-install.sh          # install.sh behavioral tests, sandboxed via mktemp (no disk clutter)
bash scripts/test-install-docker.sh   # same tests, fully isolated in a container (needs Docker running)
```

There is no general unit-test framework and no `npm test`/`pytest` equivalent. `scripts/validate.sh`
is a structural linter (required files present, JSON well-formed, naming conventions followed), not
a behavioral one. `scripts/test-install.sh` is the one behavioral exception: it runs `install.sh`
end-to-end against throwaway `mktemp` sandboxes (isolated `$PWD`/`$HOME`, cleaned up via `trap` on
exit) using `install.sh`'s own test seams (`--local`, `INSTALL_FORCE_INTERACTIVE`) — see
`docs/memory/vendor-agnostic-installer.md`.

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
| Skill | `skills/{name}/` (`SKILL.md` + `CHANGELOG.md` + `examples/`) | Yes | No |
| Orchestration workflow | `workflows/{name}/` — grouped, inter-referential components | No — the set moves/breaks together | No |

This repo only ships categories that have real, finished content in them — no placeholder
categories awaiting their first asset. If a new kind of asset (agent prompts, MCP manifests,
distributable skill packs, eval cases, etc.) gets real content again, add it back to this table,
`scripts/catalog.sh`, `scripts/validate.sh`, and `scripts/harnesses.json` together; don't let one
drift ahead of the others.

**Naming rule that matters across the whole repo**: a directory's kebab-case name is its canonical
identifier everywhere — in `README.md`, in any workflow that references it, and in its own
`CHANGELOG.md`.

**Don't fork a skill into a workflow.** `workflows/{name}/` is for components that only make sense
as part of that workflow. A skill that's also independently useful stays a single copy under
`skills/{name}/`, referenced by relative link/name from any workflow that uses it — never
duplicated into the workflow's own directory. Two copies of the same skill drift silently; one
already did (see git history around the `workflows/handoff-workflow` cleanup).

### The vendor-agnostic installer (`install.sh` + `scripts/harnesses.json`)

`install.sh` is a `curl | bash`-able entrypoint that fetches this repo (curl+tar, no `git` needed)
and copies selected assets into a target harness's directory layout. It is **fully data-driven**:
`scripts/harnesses.json` declares, per harness key, a `label`, the `scopes` it supports (e.g.
`claude-code` has `project`→`.claude` and `user`→`~/.claude`; `copilot` has only `project`→`.github`),
and a `mapping` from asset category to destination-path template. `install.sh` never branches on a
harness's name — adding a harness is a JSON edit, not a code change (see
`docs/adrs/ADR-0003-data-driven-harness-manifest.md`).

**Compatibility is expressed by omission, not error**: a harness's `mapping` only lists categories
that survive an unmodified copy. A missing key means "structurally incompatible for this harness" —
`install.sh` skips it with a one-line notice, never a failure. `copilot`'s mapping, for example, has
no `workflows` key — this repo's `workflows/{name}/` shape doesn't map cleanly onto Copilot's native
layout. Don't assume every harness gets every category.

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
authored/consumed by a chain of skills: `kickoff-document` (start) → `resume-handoff` /
`handoff-document` (each session's read/write pair) → `ingest-handoff` (promote durable content once
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
