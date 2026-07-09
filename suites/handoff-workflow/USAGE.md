# handoff-workflow — usage guide

See [`README.md`](README.md) for what this workflow does, its components, and the
session-loop diagram. This file is about *how to actually invoke it* for a given
piece of multi-session work.

## How to use it

Reach for this when a piece of work is too large for one session and you need the
*next* session (or a different developer) to pick up cold, without re-deriving
context from chat history. The skills operate on files in the **target project**
you're working in — `handoff.md` at its root, plus `docs/adrs/`, `docs/memory/`, and
`docs/archive/handoffs/` — not on `ai-personal` itself.

- **New multi-session effort** → invoke `handoff-document` (or its counterpart
  `kickoff-document` for the very first write) to author the initial `handoff.md`.
- **Picking work back up** → invoke `resume-handoff` at the start of the session, or
  whenever a message references `@handoff.md`.
- **Want it unattended** → invoke `drive-to-completion` to loop `resume-handoff` ↔
  `handoff-document` across subagents until every locked task is done.
- **Goal fully met, all tasks ✅** → invoke `ingest-handoff`, which classifies content
  and dispatches `create-adr` (decisions), `capture-deferred` (open items), and
  `archive-handoff` (moves `handoff.md` into `docs/archive/handoffs/`) in turn.
- **Any time you touch frontmatter on a `docs/` file** → `yaml-frontmatter` validates
  it against `docs/specs/yaml-frontmatter-spec.md`; the three terminal skills above
  already call it inline, so you rarely invoke it directly.

## Example

A 3-session effort to "refactor auth and add JWT token rotation":

```
# Session 1 — kick off the effort
/handoff-document
  → writes handoff.md: goal statement, Task 1/2/3 breakdown, Task 1 as "Next task"
    with constraints, 5 named test cases, and a Definition of Done
    (tsc clean, tests pass, no runtime errors on localhost)

# Session 2 — resume, do Task 1, hand off Task 2
/resume-handoff
  → reads the 3 files under "Read before coding" (auth module, JWT RFC,
    rotation requirements), executes Task 1, runs tests
/handoff-document
  → marks Task 1 ✅, promotes Task 2 to Next task with the new TokenPayload
    data shape and an Open item: "Confirm token lifetime: 15m or 1h?
    Default 15m; resolve if user objects."

# Session 3 — resume, resolve the open item, finish
/resume-handoff
  → resolves the open item (15m confirmed), executes Task 2
/handoff-document
  → marks all tasks ✅, declares the goal met

# Terminal: retire the completed handoff
/ingest-handoff
  → writes docs/adrs/ADR-0047-jwt-rotation-strategy.md (why rotation was
    baked in), writes docs/memory/deploy-operations.md (how to activate
    the rotation job)
  → /archive-handoff moves the handoff to
    docs/archive/handoffs/2026-06-30-auth-jwt-refactor.md and indexes it
```

A later session that asks "why did we do JWT rotation this way?" reads the ADR; one
that needs to re-enable the rotation job after a deploy finds the command in
`docs/memory/`; the full session record stays discoverable in the archive.
