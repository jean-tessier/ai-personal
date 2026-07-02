# workflows/ — Usage Guide

`workflows/` is one workspace of the `ai-personal` monorepo: a personal library of
reusable Claude Code assets (prompts, skills, workflows, tools, evals). This workspace
specifically holds **grouped, inter-referential** prompt/skill collections that only
function together as a set — as opposed to the independently-invocable assets in
`prompts/agents/`, `prompts/tasks/`, and `skills/`.

Consumers of this file are:
- **You (a developer)**, deciding which workflow to invoke for a given situation.
- **Claude Code itself**, reading a workflow's component skill/prompt files at
  dispatch time — this guide is the map that tells you (or Claude) which door to
  walk through first.

For directory conventions, naming rules, and the required per-workflow file layout,
see [`workflows/README.md`](README.md). For how to actually invoke what's inside a
given workflow — step-by-step guidance, worked examples, and any workflow-internal
diagram — see that workflow's own `USAGE.md`, linked in the index below. This file
stays at the workspace level; it doesn't duplicate what's one level down.

## How the pieces fit together

```
ai-personal/
├── prompts/, skills/         ← standalone assets, invocable alone
├── tools/, evals/
└── workflows/                ← THIS workspace: sets that only work together
    ├── handoff-workflow/                 (skill-set: one dir per skill)
    ├── hub-and-spoke-orchestration/      (agent-set: numbered prompt files)
    └── tiered-escalation-suite/          (Copilot/VS Code drop-in: .github/, .vscode/, scripts/, Makefile)
```

The first two workflows in this workspace produce/consume files in a **target project**
(the repo you're actually working in), not inside `ai-personal` itself — `workflows/`
holds the reusable instructions, not the output artifacts. `tiered-escalation-suite` is
different again: its payload is *copied wholesale* into a target project's root and
never read in place by Claude Code (it's Copilot/VS Code-native).

## Asset index

| Asset | One-line description | Usage guide |
|---|---|---|
| [handoff-workflow](handoff-workflow/README.md) | Skill-set that carries multi-session work forward via `handoff.md`, then retires completed work into ADRs, `docs/memory/`, and a dated archive. | [USAGE.md](handoff-workflow/USAGE.md) |
| [hub-and-spoke-orchestration](hub-and-spoke-orchestration/README.md) | Agent-prompt set for an unattended multi-agent pipeline (Orchestrator hub + Planner/Explorer/Coder/Reviewer/Arbiter/Executor spokes + Scribe write-path) that plans, implements, reviews, and merges a change to trunk. | [USAGE.md](hub-and-spoke-orchestration/USAGE.md) |
| [tiered-escalation-suite](tiered-escalation-suite/README.md) | Capability-scoped GitHub Copilot/VS Code agent suite — read-only Surveyor / diff-gated Transformer peers plus a Verifier gate, hard-enforced via hooks and scripts rather than prose. Deploy-and-open, not dispatch-a-prompt. | [USAGE.md](tiered-escalation-suite/USAGE.md) |

All three are populated (no empty/placeholder workflows currently exist in this workspace).
