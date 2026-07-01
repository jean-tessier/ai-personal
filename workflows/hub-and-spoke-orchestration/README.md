# hub-and-spoke-orchestration

A multi-agent software-engineering pipeline built around a strict hub-and-spoke
control loop: one Orchestrator dispatches every other role and routes by its
emitted status; spokes never address each other directly except through the
Orchestrator, with a single write-path service (Scribe) as the one exception.

`agents/00-shared-protocol.md` is the source of truth — status vocabulary, envelopes,
role definitions, and loop parameters live there exactly once; every other file is
derived from it and must stay consistent with it. None of the files in `agents/`
carry YAML frontmatter. The eight role prompts (`01`–`08`) are hand-authored
system-prompt specifications meant to be loaded one per role/model-call, each with
`{{TEMPLATE_VAR}}` placeholders for runtime-injected context; `00-shared-protocol.md`
is an operator reference, not a dispatched prompt, and carries none. Components
reference each other by role name in prose (e.g. "the Orchestrator," "the Scribe"),
never by filename — read them together, starting from the shared protocol.

## Entry point

Start with [`agents/00-shared-protocol.md`](agents/00-shared-protocol.md) for the
contract, then [`agents/01-orchestrator.md`](agents/01-orchestrator.md) for the hub.

## Components

| File | Role |
|---|---|
| [00-shared-protocol.md](agents/00-shared-protocol.md) | Source of truth: status vocabulary, envelopes, role definitions, loop parameters |
| [01-orchestrator.md](agents/01-orchestrator.md) | Hub. Owns the loop counter, routes every agent by its emitted status, invokes the merge gate on green |
| [02-planner.md](agents/02-planner.md) | Turns a goal into an approach and a task-DAG with acceptance criteria |
| [03-explorer.md](agents/03-explorer.md) | Read-only codebase investigator; answers questions with evidence-backed findings |
| [04-coder.md](agents/04-coder.md) | Implements task-DAG nodes on a branch; cannot merge to trunk |
| [05-reviewer.md](agents/05-reviewer.md) | Two-phase gate — coverage hunt, then quality/fit — before a node can merge |
| [06-arbiter.md](agents/06-arbiter.md) | Tie-breaker invoked only after a node bounces `k` times; issues one binding ruling |
| [07-scribe.md](agents/07-scribe.md) | Write-path service; sole writer to the docs/knowledge/trace store |
| [08-executor.md](agents/08-executor.md) | Runs shell commands/scripts on behalf of the plan or the Reviewer; never advances trunk |

## Conventions

- Files are numbered `00`–`08`; `00` is the shared contract, `01` is the hub, `02`–`08`
  are the seven dispatchable roles.
- No YAML frontmatter — each file opens directly with a level-1 heading.
- Every role prompt (`01`–`08`) ends with a `--- STABLE PREFIX ENDS ---` marker and
  `{{TEMPLATE_VAR}}` placeholders for per-dispatch context, kept last for
  prompt-cache locality; `00-shared-protocol.md` carries neither — it's read once as
  reference, not dispatched per call.
- Cross-references are by role name, not filename — there is no internal hyperlinking
  between the prompt files themselves.
