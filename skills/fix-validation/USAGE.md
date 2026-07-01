# fix-validation — usage guide

See [`SKILL.md`](SKILL.md) for the full procedure this skill follows. This file is
about *how to actually invoke it* and what a run looks like.

## How to use it

Run `/fix-validation [path-filter]` (e.g. `/fix-validation skills/atomic-commits`) to clean up
structural issues across the repo, or say "fix validation issues" / "run validate.sh and fix
what it finds". It runs `bash scripts/validate.sh`, buckets each failure into auto-fixable
(syntax slips, missing boilerplate) versus needs-authorship (missing SKILL.md content, eval
cases), applies the auto-fixes directly, re-runs `validate.sh` to confirm nothing regressed,
then reports two sections: what it fixed and what still needs a human.

```
/fix-validation skills/my-new-skill

Before: skills/my-new-skill/manifest.json has a trailing-comma syntax error;
        no SKILL.md exists yet.

Fixed:
  - manifest.json syntax corrected: {"name": "my-new-skill", "tags": ["foo"]}

Needs manual authorship:
  - write skills/my-new-skill/SKILL.md
  - author eval cases in evals/skills/my-new-skill/
```
