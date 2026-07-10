# Agent routing & escalation contract

Copilot has no live orchestrator agent — this always-on file plays that role. It is
the standing routing contract every request in this workspace pays for; open it before
routing anything.

## Route by capability (genre)
- Read-only task (find / count / map / aggregate)     → **research-lead**.
- Mutating task (rewrite / rename / codemod)           → **coding-lead**.
- After any mutation, `coding-lead` hands off to `review-lead` and must not report success before its verdict returns.
- Review-genre task (verdict on a diff/artifact set)   → **review-lead**.
- Never route a top-level task to a worker. `research-worker`, `coding-worker`, and
  `review-worker` are callable only by their own lead — dispatching one directly skips
  the decomposition and meshing a lead exists to do.

## Escalation defaults
- **Tool axis** (self-serve, within a role's ceiling): default **Tier 0**. Escalate
  only when a named trigger is met — volume, repetition, determinism, aggregation, or
  intermediate-hiding. Consult the `trigger-semantics` skill to pick the tier, and name
  the trigger.
- **Model axis** (decided one level up, never self-serve): default to the lowest tier
  that can do the work. A lead escalates a worker's model only on a judgment-density or
  high-stakes trigger (see `trigger-semantics`); a role that hits its ceiling reports
  ESCALATE with the trigger named rather than upgrading itself.
- Both axes share the same stay-low bias — if no trigger is met, stop at the floor.
  Cheap is the default on both axes, not a fallback.

## Model axis is advisory on this harness
Copilot Chat has no live per-request model-tier dispatcher the way the Claude Code
variant's Core Orchestrator does — run Copilot Chat itself on a frontier (Opus-class)
model for orchestration. Each `.agent.md` still carries a `model:` array (Sonnet-tier
for leads, Haiku-tier for workers) to document intent, but the per-subagent `model`
field is a known moving target on this harness — don't rely on it for cost control yet
(see the parent suite's "Validate before you trust" notes).

## Tier 3 (external / stateful)
MCP / network / OAuth calls require explicit human or orchestrator authorization — no
lead or worker reaches for one on its own. `.vscode/mcp.json` stays `{ "servers": {} }`
until that authorization exists; the empty config is the enforcement, not just a note.

## Invariants
- Before any mutation, show a dry-run/diff. (A PreToolUse hook enforces this — the hook is the gate, not this line.)
- Verify any count/aggregate two independent ways.
- After edits, run `make check`.
- Delegate high-volume research to a subagent; only the summary returns.
