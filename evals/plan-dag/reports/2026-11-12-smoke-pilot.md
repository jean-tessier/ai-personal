---
date: 2026-11-12
description: Smoke and pilot runs of the plan-dag eval harness; validates the harness, not a verdict on the skill
status: superseded
---

# plan-dag evals: smoke and pilot (2026-11-12)

**This is a harness validation, not a verdict.** One run per case and arm cannot support a claim about the skill.
Raw transcripts and `run.json` files stay in `evals/plan-dag/work/` (gitignored).

Setup: Claude Code CLI 2.1.322 on macOS, `claude plugin eval` with `--no-publish`. Subject and judge model
`claude-opus-5-5`, effort `high` via `CLAUDE_CODE_EFFORT_LEVEL`. Skill tree at commit `d39a214`. Arm C replaces only
the frontmatter `description` (505 chars vs 872).

## Smoke (about $1.3 of a $10 cap)

| Check | Result |
|---|---|
| Isolation (no operator CLAUDE.md, memory or hook text, no Agent tool) | Held in all 10 traces |
| `selftest-good` passes every grader; `selftest-bad` fails exactly its 6 planted defects | Yes |
| All arms complete | Yes |
| Cost per behaviour run, judge included | $0.20-0.30 (estimate was $0.70-1.00) |

## Pilot (27 runs, $24.71 including judge, cap $40)

Outcome graders passed (O class), and whether the skill loaded:

| Case | A | B | B loaded | C | C loaded |
|---|---|---|---|---|---|
| adr-conflict | 7/8 | 7/8 | yes | 7/8 | yes |
| adr-reconsider | 5/7 | 6/7 | yes | 6/7 | yes |
| cheaper-option | 5/6 | 5/6 | yes | 5/6 | yes |
| decision-rounds | 5/7 | 6/7 | yes | 6/7 | yes |
| negative-small-change | 4/4 | 4/4 | no | 4/4 | no |
| no-ci-machinery | 5/6 | 6/6 | yes | 5/6 | yes |
| oversized-slice | 3/5 | 4/5 | yes | 4/5 | yes |
| secret-hygiene | 8/8 | 8/8 | no | 8/8 | no |
| stale-premise | 5/5 | 5/5 | no | 5/5 | no |

Pooled O: A 47/56, B 51/56, C 50/56. Skill loaded on 6 of 8 trap cases in both B and C; it was skipped on the two
prompts with no trigger phrase (`secret-hygiene`, `stale-premise`). No isolation leak, error or contaminated run.

## What the runs showed about the harness

- The runner's headless child has no `AskUserQuestion`, so decision rounds are graded from the reply text and the
  skill's "at most 4 questions per call" rule is not testable in v1.
- Writes under `.claude/` are denied, and `git` fails inside the subject's Bash on this macOS host (xcrun shim). Both
  arms lose turns; paid runs on Linux would avoid it.
- The runner's `costUsd` excludes judge cost; sum `judgeCostUsd` too. It stores no judge rationale.
- `o-j6-owner-questions` failed in every arm on all 4 cases because it required a literal question; it was reworded
  to accept a named decision, a recommendation, consequences, and a request for the owner's ruling in any form.
- `o-j1-slices` fails in every arm, including B. B's plan recommends an in-place rename with a temporary view, not
  expand-then-contract. Kept as written; it may be a real gap between the skill's rule and its output.

## Not verified

Judge behaviour on replies that carry the skill's template (arm-identity leakage); the trigger suite (not run);
Linux behaviour; `make check` (no `node_modules` here).
