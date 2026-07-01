# workflows/

Grouped collections of inter-referential prompts and/or skills that only function
together — as distinct from the single, independently-invocable assets in
`prompts/agents/`, `prompts/tasks/`, and `skills/`.

## When to use `workflows/`

| Asset | Lives in | Invocable alone? |
|---|---|---|
| Agent prompt | `prompts/agents/{name}/` | Yes |
| Task prompt | `prompts/tasks/{name}.md` | Yes |
| Skill | `skills/{name}/` | Yes |
| Skill pack | `packs/{pack-name}/skills/{name}/` | Yes, per skill — bundled for distribution as one plugin, not for coupling |
| Orchestration system | `workflows/{name}/` | No — components reference each other and are deployed as a set |

If moving, renaming, or deleting one file would break others in the set, the set
belongs in `workflows/`, not scattered across `prompts/agents/` or `skills/`.

## Structure per workflow

```
{workflow-name}/
├── README.md       # What the workflow does, the role of each component, the entry point
└── agents/         # Grouped prompt files, numbered in read/dispatch order
    ├── 00-....md
    ├── 01-....md
    └── ...
```

or, when the components are skills, one subdirectory per skill — same shape as
`skills/{name}/`:

```
{workflow-name}/
├── README.md
├── {skill-a}/
│   └── SKILL.md
└── {skill-b}/
    └── SKILL.md
```

Grouped files live inside a component subdirectory — never loose at the workflow's
top level — so `scripts/validate.sh` can tell a real group from an empty placeholder.

## Naming

Kebab-case, describing the orchestration pattern: `hub-and-spoke-orchestration`.

## Available workflows

| Workflow | Description |
|---|---|
| [handoff-workflow](handoff-workflow/README.md) | Multi-session work loop: `handoff.md` carries state between sessions via `resume-handoff`/`handoff-document`, then `ingest-handoff` retires a completed handoff into ADRs, `docs/memory/`, and the handoff archive. |
| [hub-and-spoke-orchestration](hub-and-spoke-orchestration/README.md) | Multi-agent software-engineering pipeline: a central Orchestrator dispatches Planner/Explorer/Coder/Reviewer/Arbiter/Executor spokes and a Scribe write-path service against one shared protocol. |
