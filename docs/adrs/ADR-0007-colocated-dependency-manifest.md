---
date: 2026-07-12
decision_date: 2026-07-12
description: Declare asset deps as a colocated dependencies.json array, not a central manifest; install.sh resolves to a fixed point
status: accepted
---

# ADR-0007: Colocated Dependency Manifest, Resolved to a Fixed Point

## Status

Accepted

## Context

Some assets in this repo only work alongside others — installing `suites/handoff-workflow`
without also installing `skills/create-adr` and `skills/yaml-frontmatter` leaves it broken, since
the suite references those skills by relative link/name (see `CLAUDE.md`'s "Don't fork a skill
into a suite" rule). Until now, `install.sh` had no way to express or act on that relationship:
selecting a suite copied only the suite's own files, and pulling in what it needed was left to the
person running the installer to know and do by hand.

This decision was made on `feature/asset-dependency-manifest`, after Task 5's commit
(`e05db75 test: cover dependency resolution in test-install.sh`); `install.sh`,
`scripts/catalog.sh`, `scripts/validate.sh`, and `scripts/test-install.sh` already implement
everything described below.

## Decision

Each asset that has dependencies declares them in a colocated `{category}/{name}/dependencies.json`
file — a flat JSON array of repo-relative asset paths, e.g.:

```json
["skills/create-adr", "skills/yaml-frontmatter"]
```

One file per asset, owned alongside it, not a single central manifest — the same "colocated over
centralized" instinct as this repo's `SKILL.md`/`USAGE.md`/`CHANGELOG.md` per-skill layout. An
asset with no dependencies simply has no `dependencies.json` file.

The mechanism spans the same three scripts that already cooperate on every other asset property:

- **`scripts/catalog.sh`** always emits a `"dependencies": [...]` field per catalog item, reading
  the colocated file if present and defaulting to `[]` if absent (`read_dependencies_json()`).
- **`scripts/validate.sh`** checks, at `_fail` severity, that a present `dependencies.json` is
  valid JSON, is a flat array of strings, and that every path in it resolves to a real asset
  (`skills/*` must have a `SKILL.md`, `suites/*` must have a `README.md`) — a dangling or
  malformed dependency fails `validate.sh`, the same gate as any other structural asset defect.
- **`install.sh`'s `resolve_dependencies()`** runs between `select_assets()` and
  `apply_selection()`. It walks to a fixed point: each pass collects the not-yet-selected
  dependencies of every currently-selected item (via `_json deps <path>`), resolves each
  candidate's category and harness-mapping destination (reusing `select_assets()`'s existing
  warn-and-skip-on-no-mapping idiom for a category unsupported by the target harness — no second
  mechanism), then decides once per pass for the whole batch: `--yes-deps` adds all, `--no-deps`
  skips all with a `_warn`, an attached TTY (or `INSTALL_FORCE_INTERACTIVE=1`) prompts once
  (`Add them? [Y/n]`), and non-interactive with neither flag fails closed (`_fail` + `exit 1`,
  naming the missing paths) — including under `--dry-run`, since a dry run should still surface
  what a real run would need decided. The loop re-scans after adding a batch so transitive
  dependencies are picked up too, stopping when a pass finds nothing new.

The mechanism is deliberately generic: any category can depend on any other (not just suite on
skill) — `resolve_dependencies()` dispatches on the dependency path's own prefix, not on the
category of the item that declared it.

## Consequences

### Positive

- Installing `suites/handoff-workflow` now also installs `skills/create-adr` and
  `skills/yaml-frontmatter` by default (or fails closed with a clear message instead of silently
  installing a broken suite), with no change needed to the suite itself beyond adding
  `dependencies.json`.
- Dependency declarations live next to the asset they describe and are covered by the same
  structural lint (`validate.sh`) as everything else about that asset — no separate manifest file
  to keep in sync or forget to update when an asset moves or is renamed.
- Reuses `select_assets()`'s existing category/harness-mapping resolution and warn-and-skip idiom
  rather than inventing a parallel one — a dependency targeting a category unsupported by the
  current harness degrades the same way a directly-requested unsupported category already did
  (ADR-0003).
- The fail-closed default for non-interactive runs (including `--dry-run`) means a scripted
  `install.sh` invocation can never silently produce a broken partial install of a dependent asset
  — it either gets the dependency or the run stops with a clear, actionable message.

### Negative

- A dependency cycle (A depends on B depends on A) is not explicitly detected. In practice the
  fixed-point loop still terminates, because a dependency already present in `$SELECTION_FILE` is
  filtered out of each pass's candidates before the cycle could re-add it — but there is no
  dedicated cycle-detection error message if someone constructs one.
- `dependencies.json`'s flat-array shape has no way to express an optional or harness-conditional
  dependency — a dependency is unconditionally required whenever its declaring asset is selected
  for a harness that supports its category.

### Neutral

- Bash 3.2 (macOS system bash) throws "unbound variable" under `set -u` when expanding
  `"${arr[@]}"` on an empty array — unlike bash 4.4+. `resolve_dependencies()` avoids bash arrays
  entirely for its working state, using `$WORK`-scoped temp files (`dep_candidates.txt`,
  `dep_resolvable.tsv`) instead, matching the file-based idiom `select_assets()` already uses for
  `$SELECTION_FILE`.

## References

- `scripts/catalog.sh`'s `read_dependencies_json()` — emits `"dependencies":[...]` per item.
- `scripts/validate.sh`'s `check_dependencies_json()` — JSON validity, flat-array shape, and
  dangling-path checks.
- `install.sh`'s `resolve_dependencies()` (with its own header comment) and the `--yes-deps`/
  `--no-deps` flags in `parse_args()`/`usage()`.
- `scripts/test-install.sh`'s `test_deps_*` functions — behavioral coverage for auto-add,
  fail-closed, `--no-deps`, and no-duplicate-on-already-selected.
- `suites/handoff-workflow/dependencies.json` — the real fixture this mechanism was built for.
- `docs/memory/vendor-agnostic-installer.md` — operating notes, extended for this feature.
- `handoff.md` (this branch's session record) — Tasks 1 through 6.
