---
name: trigger-semantics
description: Decide the escalation tier for any search / find / count / rename / aggregate / verify task. Use BEFORE selecting a tool, whenever an operation might exceed one cheap call. Returns (tier, justifying-trigger). Consult this even when the task looks small — naming the trigger is mandatory.
---

# Escalation triggers (the only thing that must not drift)
Default = T0. Escalate to the lowest tier whose trigger is met; name the trigger.

| trigger              | meaning                                                        | floor |
|----------------------|----------------------------------------------------------------|-------|
| volume               | >~5 files OR hundreds of matches OR >few-k tokens of raw reads  | T1    |
| repetition           | same op ≥3–5×                                                   | T1    |
| aggregation          | join / group / report across sources                           | T2    |
| determinism          | must be exact & reproducible                                   | T1    |
| intermediate-hiding  | large intermediates must not enter context                     | T2    |
| external / stateful  | MCP / network / OAuth                                           | T3 — defer (Integrator, not in v1) |

If no trigger is met: STOP at T0. Answer with the cheapest tool; do not escalate.

# Audit format (uniform across agents) — append one row to ./scratch/metrics.csv
task_id, agent, tier, trigger, tool, tokens_in, tokens_out, tool_calls, make_check, crosscheck

# Contract with the agent tables
This skill returns the **tier** and the **trigger**. Each agent's local table maps
that tier to its genre's concrete tool and executor skill. Keep that division stable.
