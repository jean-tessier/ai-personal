---
name: trigger-semantics
description: Decide the escalation tier for any search/find/count/rename/aggregate/
  verify task. Use BEFORE selecting a tool, whenever an operation might exceed one
  cheap call. Returns (tier, justifying-trigger).
---

# Escalation triggers (the only thing that must not drift)
Default = T0. Escalate to the lowest tier whose trigger is met; name it.

| trigger              | meaning                                                                | floor |
|----------------------|-------------------------------------------------------------------------|-------|
| volume               | >~5 files OR hundreds of matches OR >few-thousand tokens of raw reads  | T1    |
| repetition           | same op ≥3–5×                                                          | T1    |
| aggregation          | join / group / report across sources                                  | T2    |
| determinism          | must be exact & reproducible                                          | T1    |
| intermediate-hiding  | large intermediates must not enter ctx                                 | T2    |
| external/stateful    | MCP / network / OAuth                                                  | T3 (defer — Integrator, not in v1) |

# Audit format (uniform across agents) — write to ./scratch/metrics.csv
task_id, agent, tier, trigger, tool, tokens_in, tokens_out, tool_calls, make_check, crosscheck
