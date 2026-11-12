# evals

Dev-only evals for skills in this repo, run with `claude plugin eval` (early access; Claude Code CLI 2.1.322 is
pinned). This is not an asset category: nothing here is installed by `install.sh` or listed by `scripts/catalog.sh`.
The ADR recording this decision is a later, owner-approved step.

Today there is one eval set, `evals/plan-dag/`.

## Cost warning

Every stage makes real model calls on the operator's credentials. Caps per stage: smoke $10, pilot $40, behaviour
$200, trigger $80. Reports are never published (`--no-publish` is hard-coded in `run.sh`). Do not run the full matrix
(behaviour or trigger stages) without the owner's approval; use `--dry-run` to see the commands first.

## Prerequisites

- Claude Code CLI 2.1.322 (rerun smoke after any upgrade), logged in.
- node >= 20, git.

## Running

```bash
bash evals/plan-dag/run.sh <stage> [--arm B|C] [--case GLOB] [--runs N] [--max-cost-usd USD] [--dry-run]
bash evals/plan-dag/run.sh arm B|C        # only builds and checks the arm directory
```

| Stage | Parts | Cap |
|---|---|---|
| `smoke` | harness (Haiku), behaviour-B and behaviour-C on `secret-hygiene`, trigger-B, trigger-C on `trig-01` and `trig-13` | $10 |
| `pilot` | behaviour-B, behaviour-C, 1 run per case | $40 |
| `behaviour` | behaviour-B (5 runs), behaviour-C (3 runs) | $200 |
| `trigger` | trigger-B, trigger-C (5 runs each over 32 prompts) | $80 |

Arms: A = no skill (the ablation baseline, produced by the runner), B = `skills/plan-dag` as committed, C = the same
skill body with the shorter description in `arms/C.description.txt`. `run.sh` rebuilds `work/arm/plan-dag` per arm
from `git archive HEAD:skills/plan-dag`.

- `--dry-run` does every check, builds the arm and trigger cases, writes nothing under `work/results/`, and prints
  each `claude plugin eval` command.
- A lock directory `evals/plan-dag/work/.lock` stops two runs from sharing the arm directory. Remove it only if no run
  is active.
- Dirty checks: `skills/plan-dag` and the tracked files in `arms/` must be unmodified (committed), or `run.sh` exits 3.
  There is no whole-tree check.
- Results land in `evals/plan-dag/work/results/<RUN_ID>/` (`meta.json`, `run.json`, `aggregate-result.json`,
  `report.html`, `runner.log`). `work/` is gitignored.

## Reports

```bash
node evals/plan-dag/report.mjs --out evals/plan-dag/reports/<YYYY-MM-DD>-<tree7>.md \
  evals/plan-dag/work/results/<dir> [<dir> ...]
```

`tree7` is `git rev-parse --short HEAD:skills/plan-dag`. The report is deterministic and recomputes every score from
grader results. The A vs B and B vs C verdicts are computed; the Interpretation section is written by hand. Reports
are committed, raw results are not. Test the script with `node --test evals/plan-dag/report.test.mjs`.

## Layout

```text
evals/
  README.md                this file
  plan-dag/
    run.sh                 stages, arm build, trigger-case generation, meta.json
    scaffold.sh            builds a case workspace (base + std fixture, overlay, git history)
    report.mjs             results -> markdown report (node stdlib only)
    report.test.mjs        node:test unit tests for report.mjs
    triggers.json          32 trigger prompts (24 drafted, 8 held out)
    arms/C.description.txt the shorter candidate description (arm C)
    distractors/           10 stub skills loaded beside plan-dag in trigger cases
    fixtures/base/         minimal app shared by every case
    fixtures/std/          base plus CI workflow, CONTRIBUTING, CLAUDE.md fixture, ADRs
    cases/<name>/          case.yaml, scaffold.sh wrapper, optional overlay/ and overlay.commit
    reports/               committed reports (created on first --out)
    work/                  gitignored: arm build, trigger cases, results, lock
```

The 12 cases: nine behaviour cases (`stale-premise`, `adr-conflict`, `adr-reconsider`, `cheaper-option`,
`secret-hygiene`, `oversized-slice`, `no-ci-machinery`, `decision-rounds`, `negative-small-change`) and three harness
cases (`isolation-probe`, `selftest-good`, `selftest-bad`).

## Grader classes

Graders carry a name prefix that `report.mjs` relies on.

| Prefix | Class | Scored for | Notes |
|---|---|---|---|
| `o-` | Outcome | every arm (A, B, C) | headline score; never `arm: with-only` |
| `s-` | Skill convention | B and C only | always `arm: with-only` |
| `i-` | Indicator (skill fired) | B and C only | reported, not scored |
| `v-` | Validity | every arm | a run failing any `v-` grader is dropped and counted |
| `h-` | Harness check | smoke harness cases | listed against expectations |
| `triggered` | Trigger detection | generated trigger cases | passed means the skill fired |

Blinding: outcome judges read only the final reply (`focus: last_message`), so a judge cannot see which arm produced
it. The S/with-only rule: skill-convention checks (DAG file written, cells filled, stop conditions) only make sense
when the skill is loaded, so they never run for arm A and never count toward the A vs B comparison.

## Shared judge criteria

Single source. These texts are copied verbatim into the case files that use them (`o-j3-slicing`, `o-j4-models`);
if one changes, change it here and in every case file together.

J3, standard variant (`adr-conflict`, `adr-reconsider`, `secret-hygiene`, `decision-rounds`; repository states a
200-line rule):

> PASS only if the work is split into several slices that each carry one concern; each build slice is plausibly at or
> under 200 changed lines, the repository's pull-request size rule; dependencies between slices reflect real ordering
> needs; and any change to stored data or to a public API contract is done expand-then-contract (add the new form and
> read from it first, switch writers next, remove the old form last). FAIL if a slice bundles unrelated concerns, a
> slice is clearly over 200 changed lines, or stored data or a public contract is changed in one breaking step. Judge
> only the substance of the reply; ignore any mention of tools, skills, templates or how the plan was produced.

J3, no-size-rule variant (`no-ci-machinery`):

> PASS only if the work is split into several slices that each carry one concern; each build slice is small enough to
> review on its own (a few hundred changed lines at most; the repository states no size rule); dependencies between
> slices reflect real ordering needs; and any change to stored data or to a public API contract is done
> expand-then-contract (add the new form and read from it first, switch writers next, remove the old form last). FAIL
> if a slice bundles unrelated concerns, a slice is clearly over a few hundred changed lines, or stored data or a
> public contract is changed in one breaking step. Judge only the substance of the reply; ignore any mention of tools,
> skills, templates or how the plan was produced.

J4 (`adr-conflict`, `oversized-slice`):

> PASS only if every planned task names who does it (a model tier, the orchestrating session, or the owner);
> judgement-heavy work such as design, security, review and the decisions themselves goes to the most capable model or
> to the owner; fully specified build tasks go to a mid-tier model rather than the most capable one; and no small or
> cheap model is given push, deploy, credential or secret work, or code that no one will review. FAIL if a task has no
> assignee, every task goes to the same model, or the cheapest model handles push, deploy, credentials or unreviewed
> code. Judge only the substance of the reply; ignore any mention of tools, skills, templates or how the plan was
> produced.

## Known limits of the headless child (CLI 2.1.322)

- No `AskUserQuestion`: owner questions can only be judged as text in the reply, so the "at most four questions per
  call" rule is checked as written rounds, by a judge.
- Writes under `.claude/` are denied. The DAG location rule is measured as an attempt (denied calls still count).
- `git` fails inside the subject's Bash on macOS (xcrun shim), so facts that live in history are also planted in
  files. Results are platform-specific (recorded in `meta.json`).
- `CLAUDE.md` is not auto-loaded, so the repo rules the cases depend on are also in `CONTRIBUTING.md`.
- `trace` focus for an LLM grader would leak the arm, so judges use `last_message`.
- The skill-listing budget is not observable from a trace.
- Dispatch, watch and close-out phases of the skill are out of scope; the cases are plan-only.

## Adding evals for another skill

Copy `evals/plan-dag/` to `evals/<skill>/`, rewrite the cases and `triggers.json`, and keep the shared parts (scaffold,
fixtures, report script, grader prefixes) in place until a second skill needs them; only then factor them out. The
`evals/*/work/` gitignore line already covers the new directory.
