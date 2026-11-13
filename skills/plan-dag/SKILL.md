---
name: plan-dag
description: Plan multi-PR work as a dependency graph (DAG) of small shippable slices, each with a cost-appropriate model, acceptance check and stop condition; ask the owner every decision and possible ADR conflict up front, then dispatch builder subagents in waves. Use when asked to plan a feature, refactor or migration across several PRs, turn a spec into an execution plan with decision checkpoints, generate a DAG, parallelise work across subagents, or run work hands-off or overnight, even without the word DAG. Not for one small change, a handoff.md, or non-code planning.
---

# Plan as a DAG, then orchestrate it

Large work goes well when five things hold: the owner decides everything that is theirs to decide, up front and
cheaply; the plan is the cheapest one that meets the goal; the work is cut into slices small enough to review and safe
to ship alone; each slice goes to the cheapest model that can do it well; and the plan lives in a file, not in the
conversation, so it survives compaction and anyone can read the status. This skill produces that plan and then runs it.

You are the orchestrator. You plan, ask, dispatch, push and queue (per the repo's merge contract) and report. Builders
build one slice each; reviewers review; the owner decides. A recommendation from you is welcome; a decision taken
quietly on the owner's behalf is not.

## Phase 1: Read before planning

- **The repo's own conventions:** `CLAUDE.md` (root and `.claude/`), `.claude/rules/`, `CONTRIBUTING.md`, the README,
  the ADRs (`docs/adrs/`, `docs/decisions/`, `adr/`), CI and merge config, and the spec sections the goal touches.
  Use what is there. Where something is missing (no merge process, no CI, no size rule), say so and use the defaults
  below or ask. Never import another project's machinery (merge-queue labels, stacking tools, cloud profiles) as if
  the repo had it.
- **The current state:** the main branch's head, open PRs and branches, recent CI or release runs, and other
  worktrees in flight (another session may be working in the same repo; don't plan over its work).
- **The premise.** Check read-only every live fact the request rests on (environment state, settings, "we haven't done
  X yet"). If the premise is wrong (already done, already true, no longer possible), say so in the first line of your
  reply and of the plan, with the evidence, then plan only what is still needed. A plan built on a stale premise wastes
  every slice after it.
- **Read-only is not harmless.** Never print secret values: list parameter and secret *names* only (for example
  `aws ssm describe-parameters --query 'Parameters[].[Name,Type]'`, never `get-parameters-by-path` or
  `--with-decryption`), and read one non-secret value by name when you need it. A value printed into a transcript is
  a leak, even if no file keeps it; if it happens, say so at the top of your reply so the owner can rotate it.

## Phase 2: Choose the cheapest plan that meets the goal

Before cutting slices, sketch two or three ways to reach the goal and estimate each: changed lines, releases, product
code touched, new running cost (hosting, accounts, CI minutes), and what can go wrong. Include the smallest one even if
it is less elegant: a configuration change, reusing an existing helper, a test-only change, or "no code: do it this
way instead".

- Recommend the cheapest option that meets the goal. If you recommend a costlier one, say what the cheaper one lacks.
- **Product code added only to serve tests or tooling** (a test-only route, a debug flag, a hook in production code)
  counts as cost and as risk. Prefer reaching the same state through what the product already exposes.
- When the options differ in what the owner gets, put the choice in the decision round (Phase 5) with each cost.

## Phase 3: Check the plan against accepted decisions

For each option you might recommend, list the accepted ADRs and project rules it touches. Any **possible** conflict,
and any ADR whose "When to Reconsider" condition the request meets, becomes an owner question. Don't settle it
yourself, even when you believe it doesn't really apply: write your reading as the recommendation and let the owner
rule. Slices that depend on the answer wait for it.

## Phase 4: Cut the work into slices and write the DAG file

One slice = one concern = one PR. Follow the repo's small-PR rule if it has one; otherwise aim for about 100 changed
lines and stay under 400.

- **Cut vertically** where you can: the smallest thing a person could name, through the layers it needs.
- **Land it inert, switch it on last.** Every slice but the last does nothing in production; the last one wires it up.
- **Prepare first:** a refactor that makes the feature easy is its own slice, behaviour-preserving.
- **Expand, then contract** for stored data or contracts that have readers outside the one deploy (other services,
  mobile apps, partners, scheduled jobs): reader first, writer later, removal last. With no such readers, changing it
  in place (one migration, a temporary view) can be the cheapest plan. Either way, an in-place change goes to the
  owner in the decision round as a choice, with its risks.
- **Decisions first:** a slice that depends on an owner decision waits for it.
- **Stack only real dependencies**, and keep a stack to about five layers.
- **Tests for behaviour that already works** can't fail first. Their acceptance check is a sabotage check instead:
  break the behaviour in a local, uncommitted change, watch the new test fail for the right reason, restore.

Write the DAG to `.claude/state/<topic>-dag.md` if that folder exists and git ignores it; otherwise to the session
scratchpad, and say where. Don't create tracked files in the repo while planning. Use `references/templates.md`. The
essentials:

- An opener: who it's for, what it decides, status, the owner decisions needed, and the premise check.
- The options compared (Phase 2) and the ADR check (Phase 3).
- One row per node: id, task, depends on, **who** (a model, `orchestrator`, or `OWNER`), why, size, what it ships on
  merge, the acceptance check (a command or observable fact), and the stop condition. Build and review nodes always
  have a real stop condition; owner, glue and "done" nodes may say "none: <why>". Nodes that apply only for one answer
  ("if the owner picks B") and owner gates go in the same table with every column filled and the condition in
  "Depends on", not in prose or a separate list.
- A hold on failure: every node that queues, merges or releases, the owner's merge and release nodes included, has
  "the newest release on the main branch is red: stop queueing and hold" in its stop condition, or "none: no release
  pipeline" if the repo has none. A watcher that only records a red release is not a hold.
- Waves, owner gates in order, and the definition of done.
- **Every cell of every table in the file is filled.** Where there is nothing to say, write "none: <why>", never a
  blank or a bare "n/a", "-" or "—". Check each table before writing.

### Choosing who does a node

| Work | Who | Why |
|---|---|---|
| Design, security, IAM, review, decision briefs, diagnosing a hard failure | Opus | Judgement is the work; mistakes here are expensive later |
| A build or fix that the brief fully specifies; doc updates; status refreshes | Sonnet | Most building is careful execution of a clear spec |
| A read-only lookup or a one-string edit in a file a later reviewer checks | Haiku, told "stop and report if this isn't trivial" | Cheap, and the stop clause turns a surprise into a question |
| Push, label, queue, watch, glue | `orchestrator` | Needs the session's permissions and context |
| Anything that needs the owner's authority, credentials or money | `OWNER` | Goes into the pre-flight, not discovered at 3 a.m. |

Haiku never pushes, deploys, changes settings or secrets, runs cloud or state-changing commands, or writes code that
no reviewer will read. When in doubt, Sonnet.

## Phase 5: Decision rounds

Collect every open decision (options from Phase 2, ADR questions from Phase 3, product calls, and anything your
checks turned up, such as a leaked secret to rotate) and ask them together. None stays as "your call" in prose.
AskUserQuestion takes **at most four questions per call**: ask the four that shape the plan most, then a second round
for the rest. The pre-flight (Phase 6) can be its own round. Each question has the recommended option first and the
consequence of each option in its description: cost, what changes, whether it can be undone. For a decision with real
trade-offs, have an Opus agent write a short decision brief first (`references/templates.md` §3).

If the premise was wrong, lead the first round with that. Then check the answers against each other and against
accepted ADRs. When two answers pull apart, ask one more question naming the conflict. Don't pick for the owner.
Record each answer in the plan; record any decision you make on the owner's behalf in the decision log
(`.claude/state/decisions-made-for-owner.md`, or a section of the DAG file) with why and a "Reverse:" line.

## Phase 6: Pre-flight (always before unattended work)

Before the owner leaves the run to work alone, list and resolve with them:

- **Writes outside git** the plan needs (cloud resources, parameters, CI settings, labels, secrets, accounts) → the
  owner does each now or allows it in settings.
- **Permissions:** every command likely to hit a permission prompt (push, opening PRs, the watcher) → allowed now, or
  the plan stops before it.
- **Budget:** CI minutes and spending caps for the number of runs the plan implies, and any new running cost. Check
  them read-only or mark them unverified.
- **What "costly" means for this run**, in concrete terms ("free parameter writes are fine; deploys are not").
- **Where the unattended part ends.** If every merge needs the owner's approval, the hands-off run ends at "reviewed
  PRs waiting for approval"; say so in the definition of done instead of planning merges nobody can approve.

If none of these applies, say so and why. One un-arranged write once held an overnight run for seven hours.

## Phase 7: Dispatch in waves

- Dispatch every node of a wave in one message so they run in parallel. Use the repo's `.claude/agents/builder.md` if
  it exists, with the brief from `references/templates.md`.
- Each builder works in its own worktree at a short path and commits locally; you push and queue.
- When a builder reports, check its size line and stop reasons, then run the **review-loop** skill on the slice before
  asking the owner to approve it.
- A builder that stops is doing its job. Re-cut the slice or take the question to the owner; don't raise the limit.

## Phase 8: Watch on events and keep the file current

- As soon as anything is queued or released, start a watcher (the Monitor tool over read-only `gh run` / `gh pr`
  calls) on the commit that will actually ship, and act on its events: merged, release green, release failed, CI failed.
- After every event, update the DAG file's status (and any status board, via the **board-refresh** skill).
- Turn a standing instruction ("refresh the board regularly") into a concrete trigger ("after every merge and every
  finished release") and follow it unprompted.
- Queue pacing follows the owner's preference. If none is stated, queue the next approved layer once its base is
  ready, and stop queueing whenever the newest release on the main branch is red.

## Phase 9: Close out

- Report: what merged, what's live, what's left, decisions made on the owner's behalf.
- Every follow-up and every approved-but-unmerged PR becomes an issue in the tracker (a note in chat is lost at the
  next compaction).
- Remove the worktrees of merged slices.
- Offer a retro (the **session-retro** skill) if the run was long or eventful.

## When you were asked for a plan only

Stop after Phase 5's questions (written in the reply with the recommendation and consequences, in rounds of at most
four with the most plan-shaping first, not asked through AskUserQuestion unless the user wants that) and Phase 6's
list. The final message leads with the premise check and the
decisions needed, then where the DAG file is, then the plan's cost; says plainly that nothing was built, dispatched,
pushed or changed; and ends by asking the owner to rule on the decisions. A DAG table in the reply keeps every
column, stop conditions included.

## Gotchas

- Read other branches without switching to them: `git show <ref>:<path>`, `git diff`, `git log <ref>`. Never check
  out, reset or pull in a working folder you share with the owner or another session; use a separate worktree if you
  must run code from another ref.

- On Windows Git Bash, `git show <ref>:<path>` needs `MSYS_NO_PATHCONV=1`, and long worktree paths can break test
  runners: keep worktrees at short paths.
