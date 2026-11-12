# plan-dag — usage guide

See [`SKILL.md`](SKILL.md) for the full procedure this skill follows. This file is
about *how to actually invoke it* and what a run looks like.

## How to use it

Run `/plan-dag <goal>` for work that spans several PRs or subagents — a feature, a
migration, an overnight hands-off run. It also triggers on "generate a DAG", "pick the
cost-appropriate model for each task", "parallelise this across subagents", or "front-load
my questions so this can run hands-off". Not for a single small change.

```
/plan-dag migrate the session store from Redis to Postgres, hands-off overnight

→ checks the premise read-only (is Redis really still the store? any open PRs on it?)
→ compares 2-3 plans by cost and recommends the cheapest that meets the goal
→ flags every possible ADR conflict as an owner question
→ writes .claude/state/session-store-dag.md (one row per slice: model, size,
  acceptance check, stop condition)
→ asks every open decision in batches of four, then a pre-flight round
→ dispatches builders wave by wave, watches CI, keeps the DAG file current
```

Say "plan only" to stop after the decision questions and pre-flight list; nothing is
built, pushed, or dispatched.

## Related skills

`SKILL.md` hands off to `review-loop`, `board-refresh`, and `session-retro`, and prefers a
repo's `.claude/agents/builder.md`. None of those ship in this repo; install them from
elsewhere or skip those steps.
