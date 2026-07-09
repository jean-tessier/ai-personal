# create-changelog — usage guide

See [`SKILL.md`](SKILL.md) for the full procedure this skill follows. This file is
about *how to actually invoke it* and what a run looks like.

## How to use it

Run `/create-changelog <skill-name-or-path> [what-changed-and-why] [model-version]` right
after editing a skill, or say "log this change to the changelog". It resolves the target skill
(`skills/<name>/`), confirms it's real (`SKILL.md` present), asks one focused question if you
didn't describe the change, and appends a newest-first bullet to `CHANGELOG.md` (creating it
with the standard header if it doesn't exist yet).

```
/create-changelog atomic-commits Improved detection of Conventional Commits vs. \
  kernel-style trailers by parsing multiple recent commits instead of the latest one \
  Sonnet 5

→ skills/atomic-commits/CHANGELOG.md now contains:
  # Changelog

  Format: `YYYY-MM-DD · {model-version} · {what changed and why}`

  - 2026-06-30 · Sonnet 5 · Improved detection of Conventional Commits vs. kernel-style
    trailers by parsing multiple recent commits instead of the latest one
```
