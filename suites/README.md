# suites/

Grouped collections of inter-referential prompts and/or skills that only function
together — as distinct from the single, independently-invocable skills in `skills/`.

## When to use `suites/`

| Asset | Lives in | Invocable alone? |
|---|---|---|
| Skill | `skills/{name}/` | Yes |
| Orchestration system | `suites/{name}/` | No — components reference each other and are deployed as a set |

If moving, renaming, or deleting one file would break others in the set, the set
belongs in `suites/`, not scattered across `skills/`.

## Structure per suite

```
{suite-name}/
├── README.md       # What the suite does, the role of each component, the entry point
├── USAGE.md        # How to invoke it: step-by-step guidance and a worked example
└── agents/         # Grouped prompt files, numbered in read/dispatch order
    ├── 00-....md
    ├── 01-....md
    └── ...
```

or, when the components are skills, one subdirectory per skill — same shape as
`skills/{name}/`:

```
{suite-name}/
├── README.md
├── USAGE.md
├── {skill-a}/
│   └── SKILL.md
└── {skill-b}/
    └── SKILL.md
```

Grouped files live inside a component subdirectory — never loose at the suite's
top level — so `scripts/validate.sh` can tell a real group from an empty placeholder.

## Naming

Kebab-case, describing the orchestration pattern: `hub-and-spoke-orchestration`.

## Available suites

| Suite | Description |
|---|---|
| [handoff-workflow](handoff-workflow/README.md) | Multi-session work loop: `handoff.md` carries state between sessions via `resume-handoff`/`handoff-document`, then `ingest-handoff` retires a completed handoff into ADRs, `docs/memory/`, and the handoff archive. |
| [hub-and-spoke-orchestration](hub-and-spoke-orchestration/README.md) | Multi-agent software-engineering pipeline: a central Orchestrator dispatches Planner/Explorer/Coder/Reviewer/Arbiter/Executor spokes and a Scribe write-path service against one shared protocol. |
| [tiered-escalation-suite](tiered-escalation-suite/README.md) | Capability-scoped GitHub Copilot/VS Code agent suite (Surveyor/Transformer peers + Verifier gate), a drop-in `.github/`/`.vscode`/`scripts`/`Makefile` payload for a *target* project, not read in place by Claude Code. |
