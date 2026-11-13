# Templates for plan-dag

Contents: 1. DAG file · 2. Builder brief · 3. Decision brief request · 4. Example rows

## 1. DAG file (`.claude/state/<topic>-dag.md`, or the scratchpad)

```markdown
# DAG: <the outcome, as a short sentence>

**For:** the orchestrator (dispatches, pushes, queues) and the owner (decisions, gates). **Decides:** <what this plan
settles>. **Status:** plan only | wave N running | done. Read-only checks on <date> against <main branch> at `<sha>`.
**Premise:** <holds | wrong: what is already true, with evidence>.
**Owner decisions needed:** <list, or "none">.
**Cost of the recommended plan:** <N changed lines, R releases, product code touched: yes/no, new running cost>.

## 1. What is true now
<Facts the plan rests on, with the evidence (file:line, command output). What was NOT verified, and how to check it.>

## 2. Options compared
| Option | What the owner gets | Lines | Releases | Product code touched | Running cost | Risk |
|---|---|---|---|---|---|---|
Recommended: <option>, because <one line>. <What the cheaper option lacks, if you didn't pick it.>

## 3. Accepted decisions this touches
| ADR / rule | What it says | How the plan relates | Possible conflict? → owner question |
|---|---|---|---|

## 4. The DAG
| Node | Task | Depends on | Who | Why this model | Size | Ships on merge | Acceptance check | Stop condition | Status |
|---|---|---|---|---|---|---|---|---|---|
| A1 | ... | none | sonnet | spec is complete | ~60 | nothing (inert) | `<test command>` passes | >400 lines, red existing test | not started |

## 5. Waves
| Wave | Nodes (parallel) | Waits for |
|---|---|---|
| 1 | A1 | none: first wave |

## 6. Owner gates and pre-flight (in order)
| Gate | What the owner does | When | Recommended |
|---|---|---|---|
Unattended part ends at: <e.g. reviewed PRs waiting for approval>.

## 7. Definition of done
<Observable facts: merged PRs, a green release, a live check that returns X.>

## 8. Decisions
<Owner answers, dated. Decisions made on the owner's behalf, each with why and "Reverse:".>
```

Fill every cell of every table: "none: <why>" where there is nothing to say, never a blank, "n/a", "-" or "—". Keep
the **Status** column current after every event; it is the board when there is no board.

## 2. Builder brief

```
You build one slice. Slice: <node id and task, verbatim from the DAG>.
Base: <main, or the parent layer's local branch>. Branch: <area/slice>. Worktree: <a short path>.
Read the project's rules (<files>) and: <ADRs, acceptance criteria, files>.
Test first: the smallest test that states the behaviour, run it, read the failure (it must fail for the right reason),
then the least code, then refactor. For behaviour that already works, a sabotage check instead: break it locally,
see the new test fail, restore. Name tests after acceptance-criterion ids where they exist.
Commit locally, one commit per layer. Never push, open a PR, or run cloud or state-changing commands.
Size limit: <N> counted lines. It ships on merge: <nothing / frontend / ...>.
Stop and report (with the cut you propose) if: over the limit; an existing test turns red; it would contradict an
accepted ADR; it needs product code the plan didn't list; it depends on a decision the owner has not made; you find a
second concern (report it as a follow-up).
Report: worktree, branch and SHA, files, "Size: N counted lines, M files (tests T)", what it ships, commands run and
results (say if a first run failed for the wrong reason), gaps, follow-ups, anything unverified.
```

If the repo has `.claude/agents/builder.md`, most of this is already in the agent: the brief then needs only the slice,
base, branch, files to read, size limit, ships answer and any slice-specific stop condition.

## 3. Decision brief request (Opus, before a hard question)

```
Write a decision brief for the owner on: <question>. Read <files>. Give 2–4 options, including the cheapest one that
meets the goal. For each: what changes, cost (lines, releases, money, CI minutes), risk, reversibility, and which
accepted ADRs it touches. Recommend one and say why in one paragraph. Mark every fact about live systems as checked
(how) or unverified. No code changes. Under 600 words.
```

## 4. Example rows (from a real plan)

| Node | Task | Depends on | Who | Why this model | Size | Ships on merge | Acceptance check | Stop condition |
|---|---|---|---|---|---|---|---|---|
| R1 | Red, deterministic: make the fourth response resume last so the test hangs in memory exactly as it does in CI | none | sonnet | Change fully specified; needs care to run the right filter | ~4 | nothing (test only) | the filtered test fails with the CI timeout signature | passes, or fails for another reason: stop, don't go on |
| G1 | Green, test-only: claim the gate at call time; renewal waits until the fourth has read | R1 | sonnet (same builder) | Code shape given | ~12 | nothing (test only) | same test passes; full check, typecheck, package tests green | any other test red, or diff over 40 lines |
| V1 | Prove it 50× against the real local database | G1 | orchestrator | Mechanical, needs Docker and the shell | 0 | nothing | no failure in 50 runs | one failure: the fix is wrong, don't queue |
| M1 | Queue and merge once V1 and CI are green and the owner approved | V1, P1 | orchestrator | Glue | 0 | the test fix on main | PR state MERGED | in the queue >20 min, a stacked layer dequeued, or the newest release on main is red: stop queueing and hold |
| A1 | Approve the PR by number | V1 | OWNER | Merge authority | 0 | nothing | "approve #n" in chat | none: the owner's call |
