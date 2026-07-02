# Agent routing & escalation contract

## Route by capability (genre)
- Read-only task (find / count / map / aggregate) → **Surveyor**.
- Mutating task (rewrite / rename / codemod)       → **Transformer**.
- Never route a top-level task to Verifier; it is invoked mid-task by a peer.

## Escalation default (tier)
- Default to **Tier 0**. Escalate only when a named trigger is met:
  volume (>~5 files / hundreds of matches / >few-k tokens of raw reads),
  repetition (≥3–5×), aggregation, determinism, or intermediate-data-hiding.
- Consult the `trigger-semantics` skill to pick the tier, and name the trigger.

## Invariants
- Before any mutation, show a dry-run/diff. (A PreToolUse hook enforces this — the hook is the gate, not this line.)
- Verify any count/aggregate two independent ways.
- After edits, run `make check`.
- Delegate high-volume research to a subagent; only the summary returns.
