# readme-maintenance — usage guide

See [`SKILL.md`](SKILL.md) for the full procedure this skill follows. This file is
about *how to actually invoke it* and what a run looks like.

## How to use it

Run `/readme-maintenance [workspace-filter]` (e.g. `/readme-maintenance skills`, or omit to
cover every workspace) to audit READMEs, or say "audit the READMEs" / "check the READMEs are
up to date". It reads the root README for cross-cutting conventions, then dispatches one
subagent reviewer per workspace with an 8-point quality rubric; each reviewer verifies every
claim against the real repo tree (via `ls`/`find`/`grep`) before making surgical edits, and
flags anything out-of-scope (bugs in non-README files) separately. `validate.sh` runs at the
end to confirm no structural regression; nothing is auto-committed.

```
/readme-maintenance

(a new suites/ directory was added but the root README's workspace table wasn't updated)

→ reviewer for the root README finds the gap, confirms `suites/` exists via `git ls-tree`,
  adds the missing table row, reports "Workspace table: added missing suites/ entry."
→ other reviewers check their own workspace READMEs for stale paths/commands
→ final summary: one report per workspace + a separate list of out-of-scope issues found
→ changes sit in the working tree for you to `git diff` and commit yourself
```
