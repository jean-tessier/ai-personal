# hub-and-spoke-orchestration — usage guide

See [`README.md`](README.md) for what this workflow does, its components, and
conventions. This file is about *how to actually dispatch it* for a given change.

## How to use it

Reach for this when you have a well-scoped software change (feature, fix,
refactor) and want a multi-agent team to plan, implement, verify, and land it on
trunk with no human in the loop between steps — deterministic replay and full
artifact traceability matter more than speed. The prompt set has no slash-command
entry point; you dispatch the Orchestrator directly with a JSON envelope, and it
dispatches every other role in turn. Start by reading
[`agents/00-shared-protocol.md`](agents/00-shared-protocol.md)
for the status vocabulary and envelope shapes, then
[`agents/01-orchestrator.md`](agents/01-orchestrator.md)
for the hub itself — spokes are referenced by role name in prose, never by filename,
so read them together.

The run ends when every task-DAG node has merged, a bounce count hits `k` (default 3,
escalating to the Arbiter for a binding ruling), or the total dispatch count hits the
safety cap (default 60).

## Example

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
