# atomic-commits — usage guide

See [`SKILL.md`](SKILL.md) for the full procedure this skill follows. This file is
about *how to actually invoke it* and what a run looks like.

## How to use it

Invoke it any time you want changes recorded in git — explicit slash-command use isn't
required; phrases like "commit this", "write a commit message", "stage and commit", or "split
these into commits" trigger it too. It surveys `git status`/`git diff`, decides whether the
tree holds more than one logical change (the "does the subject need the word 'and'?" test),
detects the repo's commit dialect (Conventional Commits, Changesets, kernel-style trailers, or
prose) via `scripts/detect_dialect.sh`, then writes and commits messages that explain *why*.

```
User: commit this
(working tree has: an auth bug fix, an unrelated parser refactor, and a lodash bump)

Skill:
1. Diffs the tree, finds three unrelated concerns.
2. Proposes splitting into three commits; user confirms.
3. Detects .commitlintrc.json + @commitlint/* → Conventional Commits dialect.
4. Commits each with `git commit -F -`:
   - fix(auth): reject expired tokens on refresh
   - refactor(parser): extract token validation into TokenGuard
   - build: bump lodash to 4.17.21
```
