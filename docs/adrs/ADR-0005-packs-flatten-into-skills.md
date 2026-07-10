---
date: 2026-07-01
decision_date: 2026-07-01
description: A pack's skills install as plain skills (reusing the skills mapping); packs get no separate top-level mapping key
status: superseded
superseded_by: b305d3d
---

# ADR-0005: Packs Flatten Into the `skills` Destination Category

## Status

Superseded (2026-07-08) — `packs/` was deleted from the repo (it held only empty scaffolding, no
real pack, despite this ADR already having decided how one would install) as part of curating the
repo for public release. `packs` is no longer an asset category; `install.sh` no longer has any
pack-flattening logic. This ADR is kept for historical context should a real distributable pack
appear again.

## Context

This repo distinguishes standalone skills (`skills/{name}/`) from packs (`packs/{pack-name}/skills/
{name}/`, bundled with a `.claude-plugin/plugin.json` manifest so the whole pack installs as one
Claude Code plugin — see `README.md`'s "Skills vs. prompts" table). `install.sh` needed to decide
how a target harness's manifest should describe where pack contents go: give `packs` its own
top-level `mapping` key (e.g. `"packs": "plugins/{name}"`) that installs the whole pack including
its plugin manifest, or treat a pack's individual skills the same as standalone skills once
installed elsewhere via this script.

This was tracked as an open question during this effort (see `handoff.md` Open item 1) and resolved
during Task 3.

## Decision

Packs have no `packs` key in `scripts/harnesses.json`'s `mapping` objects. Instead, `install.sh`'s
`_json items "packs"` mode walks each pack's `skills[]` and emits `(name, "{pack_path}/skills/
{name}")` pairs — structurally identical to standalone skill items — and `select_assets()` maps
category `packs` to `map_key="skills"` (`install.sh`, in `select_assets()`: `[[ "$category" ==
"packs" ]] && map_key="skills"`) so a pack's skills are resolved through the harness's `skills`
mapping template and land at the same per-skill destination a standalone skill would
(`skills/{name}` under the target harness's scope root). The pack's own `.claude-plugin/
plugin.json` manifest is never copied by `install.sh` — only the individual skill directories
inside it.

## Consequences

### Positive

- No harness's manifest needs a `packs` key at all; every harness that supports `skills` gets pack
  contents "for free," with no separate mapping entry to keep in sync.
- The destination layout is uniform: a user inspecting `.claude/skills/` (or `.github/skills/`)
  can't tell, and doesn't need to care, whether a given skill came from `skills/` or from inside a
  pack — this matches how `README.md`'s "Skills vs. prompts" table already describes packs as
  "still independently invocable," not as a unit that must stay bundled once installed.

### Negative

- Installing via `install.sh` does not preserve "this came from pack X" provenance, and does not
  install the pack as an actual Claude Code plugin (no `.claude-plugin/plugin.json` is copied) —
  a user who wants the real plugin-install experience (versioning, `/plugin` marketplace flows)
  still needs to install the pack directly as a Claude Code plugin, not via this script.
- If two packs (or a pack and a standalone skill) ever ship a skill with the same `name`, they'd
  collide at the same flattened destination path — `install.sh` has no pack-scoped namespacing to
  prevent this (not currently an issue: no name collisions exist in the catalog today).

### Neutral

- This decision is specific to `install.sh`'s copy-only model; it says nothing about how packs are
  distributed or installed through Claude Code's own plugin mechanism, which is unaffected by this
  script entirely.

## References

- `install.sh` — `_json items "packs"` (the flattening logic, with its own `ponytail:` comment)
  and `select_assets()`'s `map_key="skills"` substitution for the `packs` category.
- `README.md` — "Skills vs. prompts" table, describing packs as independently-invocable skill
  bundles.
- `handoff.md` (this branch's session record) — Open item 1 ("Flatten pack skills into the
  `skills` mapping key, or give packs their own `packs` key?" — resolved in favor of flattening).
