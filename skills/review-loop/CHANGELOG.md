# Changelog

Format: `YYYY-MM-DD · {model-version} · {what changed and why}`

2026-11-13 · Opus 5.5 · Added review-loop: an Opus reviewer, Haiku fixers for mechanical findings and Sonnet fixers for complex ones, repeated until the reviewer is SATISFIED (3 rounds max), with per-request model overrides. It saves outlining the process every time, and it supplies the review-loop step plan-dag already hands off to.

2026-11-13 · Opus 5.5 · Triage now sends a fix that offers alternatives back to the reviewer to pick one, instead of retagging it complex. In 1 of 5 clean-branch eval runs, that retag left a nit unfixed for a round and cost an extra review. Not re-evaluated.

2026-11-13 · Sonnet 5.5 · Step 1 now checks for a clean tree before any checkout, switches to a named branch (or runs the loop from the worktree that has it), and takes the merge base from the fetched remote ref. Before, a named branch other than the current one was reviewed on the wrong branch, uncommitted work followed `gh pr checkout`, and a stale local base gave an old merge base.
