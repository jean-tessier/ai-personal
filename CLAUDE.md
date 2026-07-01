# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal monorepo of reusable Claude Code assets — prompts, skills, workflows, tools, and eval
cases — kept in one place with consistent structure and conventions. There is no application code,
build step, or package manager; everything is Markdown/JSON/YAML plus a handful of Bash scripts
that catalog and validate the tree.

## Commands

```bash
bash scripts/validate.sh          # structural lint; exits 1 on failures. Run before committing.
make check                        # same thing (Makefile wraps validate.sh — the single deterministic gate)
bash scripts/catalog.sh           # emit a JSON index of every named asset to stdout
bash scripts/catalog.sh > catalog.json
```

There is no unit-test framework and no `npm test`/`pytest` equivalent. `scripts/validate.sh` *is*
the test suite: it's a structural linter (required files present, JSON well-formed, naming
conventions followed), not a behavioral one. Behavioral drift for a specific prompt/skill is
covered by `evals/{agents,skills,tasks}/{name}/cases.yaml` (mirrors the `prompts/`/`skills/` tree
exactly) — but no eval-runner script exists yet; `cases.yaml` is a data format only.

Installer (see Architecture below):

```bash
bash install.sh --harness claude-code --scope project --assets skills --dry-run
curl -fsSL https://raw.githubusercontent.com/jean-tessier/ai-personal/main/install.sh \
  | bash -s -- --harness claude-code --scope project
```

## Architecture

### The core asset taxonomy — read this before adding anything

Everything in this repo is one of five kinds of asset, and the kind determines where it lives.
This distinction is the single most load-bearing piece of architecture — `scripts/catalog.sh`,
`scripts/validate.sh`, and `install.sh`/`scripts/harnesses.json` all branch on it:

| Kind | Lives in | Invocable alone? | Distributable outside this repo? |
|---|---|---|---|
| Agent prompt | `prompts/agents/{name}/` (`system.md` + `CHANGELOG.md` + `examples/`) | Yes | No |
| Task prompt | `prompts/tasks/{name}.md` | Yes | No |
| Skill | `skills/{name}/` (`SKILL.md` + `CHANGELOG.md` + `examples/`) | Yes | No |
| Skill pack | `packs/{pack-name}/skills/{name}/` — same shape as a skill | Yes, per skill | Yes — installable as a Claude Code plugin, namespaced `{pack}:{skill}` |
| Orchestration workflow | `workflows/{name}/` — grouped, inter-referential components | No — the set moves/breaks together | No |

`prompts/_shared/` holds composable fragments (personas, output-formats, reasoning-modes) that are
included by reference, not standalone assets. `tools/mcp/` and `tools/functions/` hold MCP server
manifests and provider-specific function-schema shims (`_common/` canonical definition, one thin
binding shim per provider — never a duplicate definition per provider).

**Naming rule that matters across the whole repo**: a directory/file's kebab-case name is its
canonical identifier everywhere. `skills/foo/` must have a matching `evals/skills/foo/`;
`prompts/agents/bar/` must match `evals/agents/bar/`; same for `prompts/tasks/baz.md` ↔
`evals/tasks/baz/`. `scripts/validate.sh`'s "evals alignment" section warns (not fails) when this
drifts.

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
`install.sh` skips it with a one-line notice, never a failure. Notably, `claude-code`'s own mapping
omits `agents` and `mcp` too, not just `copilot`'s — this repo's own asset shapes for those two
categories don't match Claude Code's *native* subagent/MCP file formats either (see
`docs/adrs/ADR-0004-claude-code-native-formats-incompatible.md`). Don't assume "it's the native
harness" implies full category coverage.

### Two parallel, non-synced harness targets: `.claude/` vs `.github/`

This repo's actual daily driver is Claude Code (`.claude/skills/`, `.claude/scheduled_tasks.lock`).
It *also* maintains a fully separate, hand-authored GitHub Copilot/VS Code artifact set —
`.github/agents/*.agent.md`, `.github/skills/*/SKILL.md`, `.github/hooks/*.json`, and
`.vscode/{settings,tasks,mcp}.json` — built as a deliberate, complete dogfood of a
"Capability-Scoped Agent Suite" design doc (`.tmp/capability-scoped-agent-suite.html`), documented in
`docs/adrs/ADR-0001-target-copilot-vscode-for-agent-suite.md`. **These two trees are not kept in
sync and do not read from each other.** A change to `skills/{name}/SKILL.md` does not propagate to
`.github/skills/`; the Copilot suite's `surveyor`/`transformer`/`verifier` agents and its
`scripts/{ab-report,cap-output,cross-check,validate-handoff,hook-block-apply-without-diff}.sh` hook
scripts exist solely to enforce that design doc's invariants (dry-run-before-mutation, cross-checked
counts, output-size caps, handoff-schema validation) inside a VS Code + Copilot Chat session — none
of it has ever been exercised live (per the ADR). Don't assume editing one harness's artifacts
updates the other.

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
decisions from prior sessions that may bear on the current task.

## Conventions

- Commits follow Conventional Commits (`type: subject`, e.g. `feat:`, `docs:`, `fix:`, `test:`) —
  100% of recent history uses this prefix style.
- Skill/agent-prompt changes are logged in that asset's own `CHANGELOG.md`:
  `YYYY-MM-DD · {model-version} · {what changed and why}`.
- Markdown docs (ADRs, memory docs, archived handoffs) carry YAML frontmatter with `date`,
  `description` (≤120 chars), and `status`.
