# Agent routing & escalation contract

## Route by capability (genre)
- Read-only task (find / count / map / aggregate) → Surveyor.
- Mutating task (rewrite / rename / codemod)      → Transformer.
- Never route a top-level task to Verifier; it is invoked mid-task.

## Escalation default (tier)
- Default to Tier 0. Escalate only on a named trigger:
  volume (>~5 files / hundreds of matches / >few-k tokens of raw reads),
  repetition (≥3–5×), aggregation, determinism, or intermediate-data-hiding.
- Consult the trigger-semantics skill to pick the tier; name the trigger.

## Invariants
- Before any mutation, show a dry-run/diff. (Enforced by hook — do not rely on this line.)
- Verify any count/aggregate two independent ways.
- After edits, run `make check`.
- Delegate high-volume research to a subagent; only the summary returns.
