# prompts/ — Usage Guide

`prompts/` is the contextual-instructions workspace of this monorepo: it holds agent
system prompts, one-shot task prompts, and shared prompt fragments that give a Claude
Code session *who it is* and *what it's doing* (as opposed to `skills/`, which teaches
*how* to do something procedurally). Consumers are Claude Code sessions (loading an
agent's `system.md` as standing context, or a task's `.md` as a one-shot instruction)
and the `evals/` tree, which mirrors `prompts/` path-for-path to test each asset.

For directory layout, naming rules, and file conventions, see
[`prompts/README.md`](README.md) — this guide is about how to actually use what's here,
not how it's structured.

**Current status: every subdirectory in `prompts/` is a placeholder.** `agents/` and
`tasks/` contain only their spec `README.md`; `_shared/` contains only `.gitkeep`
markers. No agent, task, or fragment has been added yet. The sections below document
the intended usage pattern for each, grounded in the specs, so the first real asset can
be dropped in without re-deriving conventions.

## How the pieces fit together

```
prompts/
├── agents/{name}/         standing context, invoked by directory name
│   ├── system.md          ── loaded as system prompt ──────┐
│   ├── CHANGELOG.md                                         │
│   └── examples/                                            ▼
│                                                    Claude Code session
├── tasks/{name}.md        one-shot instructions               ▲
│   └── {name}/examples/   ── pasted/loaded per task ──────────┘
└── _shared/               fragments included BY REFERENCE, not directly loaded
    ├── personas/          ─┐
    ├── output-formats/     ├─→ pulled into agents/*/system.md or tasks/*.md
    └── reasoning-modes/   ─┘

                     mirrored 1:1 for testing
prompts/agents/{name}/  ⇄  evals/agents/{name}/
prompts/tasks/{name}.md ⇄  evals/tasks/{name}/
```

Agents and tasks are the two entry points a session actually loads; `_shared/` never
loads directly — it exists to be quoted or included inside an agent's `system.md` or a
task's body so common personas/formats/reasoning scaffolds aren't duplicated across
assets. Every agent and task has a canonical name that must match its counterpart under
`evals/`, which is how these prompts get regression-tested.

## Assets

| Asset | One-line description |
|---|---|
| `agents/` | Placeholder-only directory spec for standing, independently-invocable agent configurations (`system.md` + `CHANGELOG.md` + `examples/`). |
| `tasks/` | Placeholder-only directory spec for one-shot task prompts as flat Markdown files with YAML frontmatter. |
| `_shared/` | Placeholder-only (`.gitkeep` only) directories for composable prompt fragments (`personas/`, `output-formats/`, `reasoning-modes/`) meant to be included by reference. |

### agents/

No agents exist yet — this is a specification, not a populated asset. When you add one,
you create a new kebab-case subdirectory here whose name is the agent's canonical ID
(must also exist as `evals/agents/{name}/`), containing `system.md`, `CHANGELOG.md`, and
an `examples/` folder of numbered input/output pairs. See
[`agents/README.md`](agents/README.md) for the exact minimum structure and the
`CHANGELOG.md` format.

**How to use it:** create the subdirectory, write `system.md` as the agent's standing
system prompt, log the first entry in `CHANGELOG.md`, and add at least one
`examples/001-input.md` / `001-output.md` pair to anchor expected behavior before wiring
it up to `evals/agents/{name}/`.

```
prompts/agents/code-reviewer/
├── system.md          # "You are a code reviewer that..."
├── CHANGELOG.md        # 2026-06-30 · claude-sonnet-4-5 · Initial version
└── examples/
    ├── 001-input.md    # sample code review request
    └── 001-output.md   # expected review output
```

### tasks/

No task prompts exist yet — this is a specification, not a populated asset. When you add
one, you create a single kebab-case `.md` file whose stem is the task's canonical ID
(must also exist as `evals/tasks/{name}/`), with YAML frontmatter (`name`, `description`,
`output`, `model_notes`) followed by the task instructions. Only add a sibling
`{name}/examples/` subdirectory if the task benefits from few-shot examples. See
[`tasks/README.md`](tasks/README.md) for naming rules and the frontmatter contract.

**How to use it:** write the `.md` file with frontmatter, paste/load its body as a
one-shot instruction into a session, and only add `examples/` if few-shot examples
measurably improve output quality.

```
---
name: extract-entities
description: Extract named entities from unstructured text and return structured JSON.
output: "JSON array: [{ entity, type, confidence }]"
model_notes: "Works well with claude-sonnet-4-5+; requires extended thinking for complex docs."
---

[Task prompt content here]
```

Optionally paired with `prompts/tasks/extract-entities/examples/001-input.md` and
`001-output.md`.

### _shared/

Empty (`.gitkeep` only) in all three subdirectories — no fragments exist to reuse yet.
Nothing here is directly invocable; the intended usage, once populated, is to `include`
or paste a fragment's content into an agent's `system.md` or a task's body rather than
duplicating the same persona, output format, or reasoning scaffold across multiple
assets:

- `personas/` — role and voice definitions (e.g. a "lazy-engineer persona" reused across
  several agent system prompts).
- `output-formats/` — format contracts, such as a shared JSON schema for citing sources,
  referenced from multiple tasks instead of redefined in each.
- `reasoning-modes/` — chain-of-thought scaffolds, self-critique loops, etc.

**How to use it (once populated):** when writing a new `agents/{name}/system.md` or
`tasks/{name}.md`, check `_shared/` first for an existing persona/format/reasoning-mode
fragment before inlining a new one — and if you write a fragment used by two or more
assets, move it here instead of leaving it duplicated.
