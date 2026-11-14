---
name: review-loop
description: Run a review-and-fix loop on a PR or branch with subagents. An Opus reviewer returns concrete findings tagged mechanical, complex or decision; Haiku fixers take the mechanical ones and Sonnet fixers the complex ones; fixes are committed locally and the reviewer re-reviews until it returns SATISFIED (3 rounds max). Models and the round cap can be overridden per request. Use for "review-loop", "review and fix this PR", "loop until the reviewer is happy" or polishing a branch before merge. Not for a review with no fixes.
---

# Review loop

A strong model reviews, cheaper models fix, and the strong model checks the fixes. The loop repeats until the
reviewer is satisfied or the round cap is hit. Every finding has to be concrete enough that a cheaper model can act
on it without guessing. That is what makes the split worth it: judgement stays with the reviewer, and execution goes to
the cheapest model that can do it.

You are the orchestrator. You pin the target, dispatch the reviewer and fixers, run the checks, commit, and report.
You don't review and you don't fix; if you catch yourself editing a source file, give it to a fixer instead.

## Settings and overrides

| Setting | Default | Example overrides the user might give |
|---|---|---|
| Reviewer | `opus` | "use Sonnet to review", "reviewer: fable" |
| Mechanical fixer | `haiku` | "no Haiku", "Sonnet for the mechanical ones too" |
| Complex fixer | `sonnet` | "Opus for the hard fixes" |
| Round cap | 3 | "up to 5 rounds", "one round only" |
| Push at the end | no | "…and push when it's done" |

Read overrides from the user's request in plain language and resolve each model to an alias that the Agent tool's
`model` parameter takes (today `opus`, `sonnet`, `haiku`, `fable`; each alias means the latest version of that model).
"No Haiku" means the mechanical tier moves up to the complex tier's model. "Opus for everything" sets all three.
If the user names a model the Agent tool can't take, say so and ask; don't silently substitute. Overrides last for
this run only.

Before anything else, print the resolved settings on one line so the user can catch a misread override:

```text
review-loop · reviewer opus · mechanical haiku · complex sonnet · max 3 rounds · feature/coupons vs main (base 1a2b3c4) · no push
```

Spawn every subagent as a fresh general-purpose agent with `model` set to the resolved alias. Never use a fork: it
ignores the model override and inherits your context, which defeats the point of an independent reviewer.

## 1. Pin the target

- **Working tree must be clean.** If it isn't, stop and ask whether to commit or stash first. Mixing the user's
  uncommitted work into review commits is hard to untangle afterwards. Check the tree the loop will run in: this one before any checkout, or the other worktree's if you move there.
- **PR number or URL:** `gh pr view <n> --json number,title,body,headRefName,baseRefName,url`; check out the head
  branch if it isn't already checked out (`gh pr checkout <n>`).
- **Branch name, or nothing (use the current branch):** the base is the open PR's base if there is one, otherwise
  the default branch. If a named branch isn't the current one, `git switch <branch>`; if `git worktree list` shows
  it checked out in another worktree, run the whole loop from that worktree (cd there and give that path to every
  subagent) instead of switching.
- If the base has a remote, `git fetch <remote> <base>` and fix `BASE=$(git merge-base <remote>/<base> HEAD)`;
  otherwise `BASE=$(git merge-base <base> HEAD)`. Keep `BASE` for the whole loop. Every review reads
  `git diff $BASE...HEAD`, so the fixes you commit become part of what the reviewer sees.
- **Find the repo's check command** (from CLAUDE.md, CONTRIBUTING, Makefile, package.json scripts or CI config) and
  run it once now. Record the result as the baseline, so that failures already present on the branch aren't blamed on
  fixers. If there is none, say so; the review is then the only gate.

## 2. Review

Dispatch the reviewer with the round-1 brief (below). Parse its reply into the verdict and the findings.

- **SATISFIED** with no findings left for fixers: go to step 6.
- A finding with no concrete `fix` isn't actionable. Send it back to the reviewer once, asking it to make the finding
  concrete or drop it.

For later rounds, **continue the same reviewer** (SendMessage to its agent ID) with the round-N brief, so that it
remembers what it already reviewed and doesn't rediscover the same nits. If you can't continue it, spawn a new
reviewer with the round-1 brief plus the round-N brief, and paste in the previous findings and their outcomes.

## 3. Triage and dispatch fixers

1. **Check the tiers.** Retag a finding when its tag doesn't fit the definitions in the reviewer brief: for example,
   a "mechanical" fix that spans three files or needs a new test becomes complex. Note each retag for the report.
   A fix that offers alternatives ("either X or Y") isn't concrete yet: send it back to the reviewer to pick one
   (step 2) instead of retagging it.
2. **Decide what gets fixed.** Blocking and should-fix findings always get fixed. Nits are fixed only when they are
   mechanical, because that's cheap; complex nits are listed in the report and left alone. `decision` findings go to
   the user (step 3.5), not to a fixer.
3. **Fix in two waves: mechanical first, then complex.** Each finding stays on its own tier's model, and because a
   wave finishes before the next one starts, two fixers never edit the same file at once, even when every finding is
   in one file (the usual case in a small PR). Mechanical goes first so that the complex fixers read the tidied code.
   Skip a wave that has no findings.
4. **Within a wave, group by file.** Findings that touch any of the same files go to one fixer. Dispatch all of the
   wave's fixers in one message, so that they run in parallel, each with the fixer brief and the wave's model.
5. **While the waves run, ask the decisions.** Use AskUserQuestion, at most four per call, with the reviewer's
   recommended option first. An answer that needs a code change becomes a complex finding (in the complex wave if
   it hasn't started, otherwise in a follow-up fixer this round). If nobody can answer (for example, a
   non-interactive run), carry the decision to the report and keep looping; don't wait.

When every fixer in a wave has reported:

- `ESCALATE` (a mechanical fixer found the finding wasn't mechanical): move it into the complex wave.
- `NEEDS_FILE <path>`: re-dispatch the finding with that file added, once the wave is done.
- Commit the wave (step 4.1) before the next wave starts, so that each commit holds one fixer's work.

## 4. Commit and verify

1. **Commit each fixer group separately.** Stage only the files that group reported changing (`git add <paths>`,
   never `git add -A`), then check `git status --porcelain` for stray changes and ask about any you can't place.
   Follow the repo's commit conventions; with Conventional Commits that is something like
   `fix(coupons): accept lowercase coupon codes`, with the finding ids in the body. You commit, not the fixers,
   because parallel fixers share one checkout and one git index.
2. **After the round's last wave, run the check command.** If it is worse than the baseline, send one complex fixer
   the failure output and this round's diff, and commit its repair. If it is still red after that, don't keep
   trying: give the failure to the reviewer in the next round as context.
3. **Don't push** unless the user asked for it in this request. Never force-push.

## 5. Next round, or stop

Start the next round (step 2, round-N brief) unless one of these holds:

- **The cap is reached.** After the last allowed round's fixes, the reviewer reviews once more. That review gives the
  verdict, but its new findings go into the report and are not dispatched.
- **The loop stalled.** If nothing was FIXED this round (every finding was disputed, not fixed, or a decision), the
  rest is a disagreement only the user can settle, so stop.
- **A finding was disputed twice.** It becomes a decision for the user, and it no longer blocks the loop.

## 6. Report

```markdown
## review-loop: SATISFIED after 2 rounds
(or: NOT SATISFIED: cap of 3 rounds reached | stalled in round 2)

review-loop · reviewer opus · mechanical haiku · complex sonnet · max 3 rounds · feature/coupons vs main (base 1a2b3c4)

| Round | Findings (blocking/should-fix/nit/decision) | Fixed by haiku | Fixed by sonnet | Disputed | Commits |
|---|---|---|---|---|---|
| 1 | 2/2/1/0 | 2 | 2 | 0 | 3 |
| 2 | 0/0/0/0 | – | – | – | – |

Commits on feature/coupons (not pushed; say "push" to push):
- 9f8e7d6 fix(coupons): accept lowercase coupon codes
- …

Still open: none (or: each open finding, nit, dispute and unanswered decision, one line each with its id)
Check: `npm test` green (baseline green)
Retagged: R1-3 mechanical → complex (needed a new test)
```

Use each tier's model alias in the column headers. If the user had asked to push, push at this point and replace
"not pushed" with the remote branch.

## Briefs

Fill in the placeholders. Paste the findings into fixer briefs exactly as the reviewer wrote them; a paraphrase loses
the detail a cheaper model needs.

### Reviewer, round 1

```text
You are reviewing a change before it merges. Review it like a careful senior engineer who will be paged if it
breaks. Stay read-only: don't edit files or run anything that changes state.

Change: <branch> vs <base> (merge base <BASE>). <PR #n "title", if any>
Intent: <PR description, or a summary of the commit messages>
Read: `git log --oneline <BASE>..HEAD` and `git diff <BASE>...HEAD`, then the code around each change wherever the
diff alone doesn't show whether it's right.
Repo rules: <paths to CLAUDE.md, CONTRIBUTING, lint config, ADRs, or "none found">
Check command: <command>, baseline <green | failing: summary>

Look for, most important first: correctness bugs and unhandled edge cases; security problems; behaviour that
contradicts the intent, the docs or the repo's rules; changed behaviour with missing or wrong tests; then anything a
future reader would trip on. Skip style preferences the repo's own rules and linters don't ask for.

Every finding must be actionable: where it is, the concrete fix (what to change, to what), and how to check it. If
you can't name a fix, drop the finding, or make it a decision and give the options. Three real findings beat ten
weak ones.

severity: blocking (wrong behaviour, security, data loss, broken build) | should-fix (a real problem, not urgent) |
          nit (polish)
tier:     mechanical: the fix text fully determines the edit (typo, rename, unused import, wrong constant);
                      no design choice and no new tests
          complex:    needs judgement, coordinated edits, new or changed tests, or a change in behaviour
          decision:   the author's call (product behaviour, API shape, scope); list the options and recommend one
          If you're unsure between mechanical and complex, choose complex.
where:    every file:line the fix has to touch, test files included

Reply in exactly this format and nothing else:

VERDICT: SATISFIED | CHANGES_REQUESTED

- id: R1-1
  severity: ...
  tier: ...
  where: ...
  problem: <one sentence: what's wrong and why it matters>
  fix: <the concrete change>
  check: <a command to run, a test, or what to look for>

SATISFIED means no blocking or should-fix finding remains. Nits and decisions can still be listed.
```

### Reviewer, round N

```text
Round <N>. Since your last review, the fixers made these commits:
<git log --oneline of this round's commits>
Check command now: <green | failing: summary>

Outcome of each finding you raised:
<id: FIXED | DISPUTED: fixer's evidence | NOT_FIXED: reason | SKIPPED: complex nit | DECISION: the owner's answer, or unanswered>

Review `git diff <BASE>...HEAD` again, then:
1. Start your reply with `RESOLVED: <ids>` for every finding that is now properly fixed. Any finding that isn't
   stays under its original id; correct its fix if the first attempt went wrong.
2. For each DISPUTED finding: withdraw it if the fixer is right. If you hold it, answer their evidence. If it has now
   been disputed twice, retag it as a decision.
3. Raise a new finding only if the fixes introduced or exposed it, or if it is blocking. The loop has to converge, so
   don't add should-fix items or nits about code the fixes didn't touch. Number new findings R<N>-1, R<N>-2, ...

Same format and the same meaning of SATISFIED as before.
```

### Fixer

```text
You are fixing code-review findings on branch <branch> in <repo path>. Make the smallest change that resolves each
finding. Don't refactor, rename or reformat anything else.

You may edit: <files in this group>. You may create new files, such as a new test file. If a fix needs an edit to
any other existing file, leave that finding alone and report NEEDS_FILE: other fixers are editing other files in this
checkout right now.

Don't commit, stage, stash, switch branches or touch git state in any other way. The orchestrator commits once every
fixer has finished.

Findings:
<the reviewer's finding blocks, verbatim>

Check your work with a targeted command for what you touched (for example, one test file), not the full suite: other
fixers' edits are in flight. The full check runs after everyone finishes.

If a finding is wrong (the code is already correct, or the fix would break something), don't apply it. Report it as
DISPUTED and give your evidence (file:line, test output).

<mechanical tier only:> These findings were tagged mechanical. If one turns out to need judgement (the fix text
doesn't fully determine the edit, or more than the described change is needed), leave it untouched and report
ESCALATE with one line on why. Escalating is cheaper than a wrong guess.

Reply with one line per finding, then the files you changed:
R1-2: FIXED: <what you changed>
R1-4: DISPUTED: <evidence>
R1-5: ESCALATE: <why>
R1-6: NEEDS_FILE src/other.js: <why>
R1-7: NOT_FIXED: <what blocked you>
Files changed: <paths>
```
