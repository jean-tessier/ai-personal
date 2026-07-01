# create-changelog — usage guide

See [`SKILL.md`](SKILL.md) for the full procedure this skill follows. This file is
about *how to actually invoke it* and what a run looks like.

## How to use it

Run `/create-changelog <asset-name-or-path> [what-changed-and-why] [model-version]` right
after editing a skill or agent prompt, or say "log this change to the changelog". It resolves
whether the target is a skill (`skills/<name>/`), a packed skill (`packs/<pack-name>/skills/<name>/`),
or an agent prompt (`prompts/agents/<name>/`), confirms it's a real asset (`SKILL.md` or
`system.md` present), asks one focused question if you didn't describe the change, and appends
a newest-first bullet to `CHANGELOG.md` (creating it with the standard header if it doesn't
exist yet).

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
