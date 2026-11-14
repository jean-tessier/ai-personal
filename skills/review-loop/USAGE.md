# review-loop — usage guide

See [`SKILL.md`](SKILL.md) for the full procedure this skill follows. This file is
about *how to actually invoke it* and what a run looks like.

## How to use it

Run `/review-loop` with a PR number, a branch, or nothing (the current branch). It also
triggers on "review and fix this PR", "loop until the reviewer is happy", or "polish this
branch before merge". Overrides go in the same sentence, in plain words:

```text
/review-loop 42
/review-loop feature/coupons, use Sonnet to review and no Haiku
/review-loop, opus for everything, up to 5 rounds, and push when it's done
```

A run on PR 42 with the defaults:

```text
review-loop · reviewer opus · mechanical haiku · complex sonnet · max 3 rounds · feature/coupons vs main (base 1a2b3c4) · no push

→ round 1: Opus finds 5 issues (2 mechanical, 3 complex)
→ a Haiku wave fixes the mechanical findings, then a Sonnet wave the complex ones
  (fixers in a wave run in parallel, one per group of files)
→ the orchestrator commits each fixer's work, then runs the repo's check command
→ round 2: the same Opus reviewer checks the fixes → SATISFIED
→ report: per-round table, commits (not pushed), anything still open
```

Fixes are committed locally on the branch and **not pushed** unless you ask. Nothing is
posted to the PR.

## When not to use it

- You want a review and will fix things yourself: use `/code-review`.
- The working tree has uncommitted changes: commit or stash them first (the skill stops and
  asks).

## Related skills

`plan-dag` runs this skill on each slice a builder finishes, before asking the owner to
approve it.
