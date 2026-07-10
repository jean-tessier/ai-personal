---
name: scratch-script
description: Aggregate, join, or transform data across multiple sources with a throwaway script that writes intermediates to ./scratch and emits only a compact final artifact. Use when a task needs loops, joins, multi-file aggregation, or must keep large intermediate data out of context (Tier 2). Read OR write genre — the agent's own capability scope still applies.
allowed-tools: shell
---

# Scratch script (Tier 2)
Precondition (self-gate): aggregation OR intermediate-hiding OR repetition ≥3–5× trigger.

1. Copy `templates/aggregate.ts` to `./scratch/<task>.ts`; fill the marked TODOs.
2. Run it: it writes full data to `./scratch/<task>.json` and a compact
   `./scratch/<task>.md`, and prints ONE summary line. Only that line + the compact
   artifact enter context — never the raw intermediates.
3. Cross-check the headline number a second way (e.g. script total vs `jq` over the
   source) and surface any mismatch (`scripts/crosscheck.sh`).
4. If this script MUTATES code, it is a coding team (coding-worker) task: write the
   diff to `./scratch/handoff/pending.diff` first (the hook still applies).

Keep the final artifact small — it is the only thing the orchestrator reads.
