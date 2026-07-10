---
name: trigger-semantics
description: Decide the escalation tier for any search / find / count / rename / aggregate / verify task, on the tool axis or the model axis. Use BEFORE selecting a tool or escalating a role's model, whenever an operation might exceed one cheap call. Returns the tier and the trigger; each agent's local table maps tier to concrete tool. Consult this even when the task looks small — naming the trigger is mandatory.
---

# Escalation protocol

Canonical source: `../../../../PROTOCOL.md` (suite root, this monorepo) — edit there
first, then mirror here. This note is for maintainers of the ai-personal monorepo; in
a deployed target repo this file stands alone.

## Tool axis — self-serve, within your role's ceiling

Default = T0. Escalate to the lowest tier whose trigger is met; name the trigger.
If no trigger is met: STOP at T0. Do not escalate.

| trigger             | meaning                                                         | floor |
|---------------------|-----------------------------------------------------------------|-------|
| volume              | >~5 files OR hundreds of matches OR >few-k tokens of raw reads  | T1    |
| repetition          | same op ≥3–5×                                                   | T1    |
| determinism         | must be exact & reproducible                                    | T1    |
| aggregation         | join / group / report across sources                             | T2    |
| intermediate-hiding | large intermediates must not enter context                       | T2    |
| external / stateful | MCP / network / OAuth                                           | T3 — route up; only the core orchestrator authorizes |

## Model axis — decided one level up, never self-serve

Default = the lowest tier that can do the work. Escalating a role's model tier is its
dispatcher's decision, made at dispatch time; a role that hits its ceiling reports
ESCALATE with the trigger named — it never upgrades itself.

| trigger             | meaning                                                          | floor |
|---------------------|--------------------------------------------------------------------|-------|
| judgment density    | ambiguous goal, competing tradeoffs, cross-worker synthesis      | Lead (Sonnet-tier) |
| high-stakes         | trust boundary, security, irreversible or outward-facing change  | Review lead at Opus-tier |
| cross-team conflict | team outputs contradict; arbitration needed                      | Orchestrator (Opus-tier) |

## Invariants — orthogonal to both axes; never scale down with tier

- Every mutation is preceded by a shown diff, at every tier.
- Every count/aggregate is verified two independent ways.
- After edits, the repo's deterministic gate runs (`make check` or equivalent).
- Verifier-style reports return a verdict + ≤5-line digest — never raw logs.
- Every task logs (axis, tier, trigger) for audit.

# Audit format (uniform across agents) — append one row to ./scratch/metrics.csv
task_id, agent, axis, tier, trigger, tool, tokens_in, tokens_out, tool_calls, make_check, crosscheck

# Contract with the agent tables
This skill returns the **tier** and the **trigger**, on whichever axis applies. Each
agent's local table maps that tier to its genre's concrete tool and executor skill on
the tool axis; on the model axis, escalation is the dispatcher's call, never
self-served. Keep that division stable.
