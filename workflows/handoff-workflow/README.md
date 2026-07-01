# handoff-workflow

A set of skills that carry multi-session work forward via a `handoff.md` file at a
target project's root, then retire that work into durable, indexed docs
(`docs/adrs/`, `docs/memory/`, `docs/archive/handoffs/`) once its goal is met.
Each skill is independently invocable, but they reference each other's output —
`resume-handoff` consumes what `handoff-document` writes, `ingest-handoff` reads a
completed `handoff.md` and dispatches to `create-adr`, `capture-deferred`, and
`archive-handoff` in turn — so the set belongs together rather than scattered
across `skills/`.

## Entry point

Start a fresh multi-session effort with [`handoff-document/SKILL.md`](handoff-document/SKILL.md)
(write the first `handoff.md`); resume one already in progress with
[`resume-handoff/SKILL.md`](resume-handoff/SKILL.md). For unattended execution across
many turns, [`drive-to-completion/SKILL.md`](drive-to-completion/SKILL.md) wraps the
resume/handoff pair in a subagent loop.

```
        ┌──────────────────────── next session ────────────────────────┐
        ▼                                                               │
  resume-handoff  ──►  execute the "Next task"  ──►  handoff-document  ─┘
  (read handoff.md)    (to its Definition of Done)   (re-write handoff.md)

  Repeats until handoff.md declares the overall goal met, then:

  ingest-handoff ──► create-adr / capture-deferred (as needed) ──► archive-handoff
  (classify durable    (promote decisions / deferred items)        (move handoff.md to
   vs. ephemeral)                                                   docs/archive/handoffs/)
```

## Components

| Skill | Role |
|---|---|
| [handoff-document](handoff-document/SKILL.md) | Write side of the session loop — authors/updates `handoff.md` with completed work, phase state, the Next task, and open items |
| [resume-handoff](resume-handoff/SKILL.md) | Read side of the session loop — loads `handoff.md`, executes the Next task to its Definition of Done, then hands back to `handoff-document` |
| [drive-to-completion](drive-to-completion/SKILL.md) | Orchestrates `resume-handoff` ↔ `handoff-document` across subagents autonomously until every locked task is done or a hard block surfaces |
| [ingest-handoff](ingest-handoff/SKILL.md) | Invoked once a handoff's goal is met — classifies its content as decision, operational fact, or ephemeral, and dispatches the three skills below |
| [create-adr](create-adr/SKILL.md) | Writes an Architecture Decision Record to `docs/adrs/`, updating `docs/adrs/INDEX.md` |
| [capture-deferred](capture-deferred/SKILL.md) | Appends unresolved open items and deferred work to `docs/memory/deferred-items.md` |
| [archive-handoff](archive-handoff/SKILL.md) | Moves a fully-ingested `handoff.md` to `docs/archive/handoffs/` with frontmatter, and updates its index |
| [yaml-frontmatter](yaml-frontmatter/SKILL.md) | Validates/adds/fixes YAML frontmatter on any `docs/` file against `docs/specs/yaml-frontmatter-spec.md` — the same spec the three skills above apply inline when they write frontmatter themselves |

## Conventions

- Each skill is a normal `{skill-name}/SKILL.md` with YAML frontmatter (`name`,
  `description`) — the workflow grouping is organizational, not a different file format.
- The skills operate on files in the *target* project being worked on (`handoff.md` at
  its root, `docs/adrs/`, `docs/memory/`, `docs/archive/handoffs/`), not on this repo.
- Cross-references are by skill name in prose (e.g. "invoke the `ingest-handoff` skill"),
  matching how each `SKILL.md` refers to the others.
- `docs/specs/yaml-frontmatter-spec.md` is the single source of truth for frontmatter
  fields across every skill that writes to `docs/` — read it before writing, don't
  duplicate its rules inline.
