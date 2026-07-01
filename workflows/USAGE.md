# workflows/ — Usage Guide

`workflows/` is one workspace of the `ai-personal` monorepo: a personal library of
reusable Claude Code assets (prompts, skills, workflows, tools, evals). This workspace
specifically holds **grouped, inter-referential** prompt/skill collections that only
function together as a set — as opposed to the independently-invocable assets in
`prompts/agents/`, `prompts/tasks/`, and `skills/`.

Consumers of this file are:
- **You (a developer)**, deciding which workflow to invoke for a given situation and
  how to invoke it.
- **Claude Code itself**, reading a workflow's component skill/prompt files at
  dispatch time — this guide is the map that tells you (or Claude) which door to
  walk through first.

For directory conventions, naming rules, and the required per-workflow file layout,
see [`workflows/README.md`](README.md). This file is about *how to actually invoke
what's in here*, not the structural rules.

## How the pieces fit together

```
ai-personal/
├── prompts/, skills/         ← standalone assets, invocable alone
├── tools/, evals/
└── workflows/                ← THIS workspace: sets that only work together
    │
    ├── handoff-workflow/                 (skill-set: one dir per skill)
    │   handoff.md (in a TARGET project) ─┐
    │        │                            │  read/write loop, session to session
    │        ▼                            │
    │   resume-handoff ──► do the task ──► handoff-document ─┘
    │        │
    │        ▼ (goal met, all tasks ✅)
    │   ingest-handoff ──► create-adr / capture-deferred ──► archive-handoff
    │        │                    │                                │
    │        ▼                    ▼                                ▼
    │   docs/adrs/          docs/memory/                docs/archive/handoffs/
    │
    │   (drive-to-completion wraps the loop above in an autonomous subagent
    │    orchestration; yaml-frontmatter is a shared utility used inline by
    │    create-adr / capture-deferred / archive-handoff)
    │
    └── hub-and-spoke-orchestration/      (agent-set: numbered prompt files)
        goal ──► 01-Orchestrator (hub)
                     │  dispatches, never lets spokes talk to each other
                     ├──► 02-Planner    (goal → approach + task-DAG)
                     ├──► 03-Explorer   (read-only investigation)
                     ├──► 04-Coder      (implements a DAG node on a branch)
                     ├──► 05-Reviewer   (coverage hunt, then quality gate)
                     ├──► 06-Arbiter    (tie-break after k bounces)
                     ├──► 08-Executor   (runs tests/lint/scripts on request)
                     └──► 07-Scribe     (sole writer: docs/plans, ADRs, trace)
                     on APPROVED → merge gate → trunk
```

Both workflows in this workspace produce/consume files in a **target project** (the
repo you're actually working in), not inside `ai-personal` itself — `workflows/`
holds the reusable instructions, not the output artifacts.

## Asset index

| Asset | One-line description |
|---|---|
| [handoff-workflow](handoff-workflow/README.md) | Skill-set that carries multi-session work forward via `handoff.md`, then retires completed work into ADRs, `docs/memory/`, and a dated archive. |
| [hub-and-spoke-orchestration](hub-and-spoke-orchestration/README.md) | Agent-prompt set for an unattended multi-agent pipeline (Orchestrator hub + Planner/Explorer/Coder/Reviewer/Arbiter/Executor spokes + Scribe write-path) that plans, implements, reviews, and merges a change to trunk. |

Both are populated (no empty/placeholder workflows currently exist in this workspace).

---

## handoff-workflow

### How to use it

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

### Example

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

---

## hub-and-spoke-orchestration

### How to use it

Reach for this when you have a well-scoped software change (feature, fix,
refactor) and want a multi-agent team to plan, implement, verify, and land it on
trunk with no human in the loop between steps — deterministic replay and full
artifact traceability matter more than speed. The prompt set has no slash-command
entry point; you dispatch the Orchestrator directly with a JSON envelope, and it
dispatches every other role in turn. Start by reading
[`agents/00-shared-protocol.md`](hub-and-spoke-orchestration/agents/00-shared-protocol.md)
for the status vocabulary and envelope shapes, then
[`agents/01-orchestrator.md`](hub-and-spoke-orchestration/agents/01-orchestrator.md)
for the hub itself — spokes are referenced by role name in prose, never by filename,
so read them together.

The run ends when every task-DAG node has merged, a bounce count hits `k` (default 3,
escalating to the Arbiter for a binding ruling), or the total dispatch count hits the
safety cap (default 60).

### Example

Dispatching the Orchestrator for "Add async request handler to support non-blocking
I/O for long-running tasks":

```
# Initial dispatch to the Orchestrator
{
  "goal": "Add async request handler to support non-blocking I/O for long-running tasks",
  "repo": "<repo pointer>",
  "trunk_ref": "main",
  "k": 3,
  "cap": 60
}

# What happens next (Orchestrator-driven, no manual steps in between):
01-Orchestrator → 02-Planner
  emits PLAN_READY: approach + task-DAG
    [node-1 refactor sync handler, node-2 add request queue,
     node-3 add async handler + tests, node-4 integration tests]

01-Orchestrator → 03-Explorer (node-1)
  "How are request handlers currently structured? Where are they tested?"
  → findings with file:line pointers

01-Orchestrator → 04-Coder (node-1)
  commits refactor to branch feature/async-handler-node-1, emits TASK_DONE

01-Orchestrator → 05-Reviewer (node-1)
  phase 1 (coverage hunt): COVERAGE_GAP — "wrapper behavior untested"
  → back to Coder, adds tests, TASK_DONE
  phase 1 passes → REVIEW_NEEDS_RUN (pytest, black --check)

01-Orchestrator → 08-Executor (node-1)
  runs `pytest tests/handlers/` and `black --check src/handlers.py` → RUN_PASSED

01-Orchestrator → 05-Reviewer (node-1)
  phase 2 (quality/fit): APPROVED

01-Orchestrator → merge gate → node-1 merges to main; bounce counter resets
  (repeats the Coder → Reviewer → Executor → gate loop for node-2, node-3, node-4)

# If node-3 thrashes between Coder and Reviewer 3 times:
01-Orchestrator → 06-Arbiter
  binding ruling: "Implement retry logic for queue-full scenario;
  merge after Coder commit without further review loop."

# Throughout, 07-Scribe is the sole writer of:
docs/plans/<plan-id>.md, docs/decisions/ADR-<n>-<slug>.md,
docs/codebase/<topic>.md, docs/trace/runs/<run-id>/log.md,
docs/trace/runs/<run-id>/exec/<node>.md, docs/trace/runs/<run-id>/manifest.md

# Final status from the Orchestrator:
DONE — manifest points to every plan, ADR, script, and run log; the
feature is merged to trunk with a full, traceable decision record.
```
