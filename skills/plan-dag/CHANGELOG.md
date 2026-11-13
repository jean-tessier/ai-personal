# Changelog

Format: `YYYY-MM-DD · {model-version} · {what changed and why}`

2026-11-11 · Sonnet 5.5 · Added plan-dag to the repo: plan multi-part work as a DAG of slices with cost-appropriate models, then orchestrate it wave by wave.
2026-11-12 · Opus 5.5 · Shortened the description (872 → 567 chars) and added "turn a spec into an execution plan with decision checkpoints", because the shorter draft triggered as well as the long one except on that request.
2026-11-12 · Opus 5.5 · "Every cell is filled" now covers every table in the DAG file, with a check before writing and a "none: first wave" example, because blank and bare "—" cells showed up mostly in the ADR, waves and gates tables, which the rule didn't name.
2026-11-12 · Opus 5.5 · The hold-on-red-release clause now names the owner's merge and release nodes (they had been getting a bare "none: your call"), allows "none: no release pipeline", and the template's queue-and-merge example row carries it.
2026-11-12 · Opus 5.5 · Expand-then-contract is now the recommendation even for a plain rename of stored data; an in-place change is offered to the owner as a cheaper, riskier option instead of being recommended as the cheapest plan.
2026-11-12 · Opus 5.5 · Plan-only replies now write each decision in Phase 5's form and end by asking the owner to rule, and a DAG table pasted into the reply keeps every column, because replies were dropping the stop-condition column.
2026-11-12 · Opus 5.5 · Plan-only replies now group the written decisions in rounds of at most four, most plan-shaping first, because asking the owner to rule had every decision listed at once and the rounds-of-four check fell from 3/5 to 0/4.
2026-11-13 · Sonnet 5.5 · Expand-then-contract is now recommended only for stored data or contracts with readers outside the one deploy; with none, an in-place change can be the cheapest plan, and either way it goes to the owner as a decision, because "even for a rename" contradicted Phase 2's cheapest-option rule for internal renames; NOT re-evaluated (the previous wording scored 5/5 on the expand-then-contract grader but was tuned on that grader).
